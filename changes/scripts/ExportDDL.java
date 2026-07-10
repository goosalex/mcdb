import oracle.jdbc.OracleDriver;

import java.io.*;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;

public class ExportDDL implements Runnable {
    private final Properties config;
    private Connection c;
    private final String[] schemas;
    private final File outDir;
    private final File pgOutDir;
    private final Charset encoding = StandardCharsets.UTF_8;
    private static final String DEFAULTS_FILE_ARG = "--defaults-file=";
    private static final String DATAOUT_ARG = "--dataOutputDirectory=";
    private static final String PW_ARG = "--password=";
    private static final String PGSQLDIR_ARG = "--pgsql=";

    public static void main(String[] args) throws Exception {
        Properties p = new Properties();
        for (String arg : args) {

            if (arg.startsWith(DEFAULTS_FILE_ARG)) {
                String filename = arg.substring(DEFAULTS_FILE_ARG.length());
                try (InputStream fin = new FileInputStream(filename)) {
                    p.load(fin);
                } catch (IOException e) {
                    File f = new File(filename);
                    throw new RuntimeException("Could not load " + f.getAbsolutePath() + ": " + e.getMessage(), e);
                }
            } else if (arg.startsWith(DATAOUT_ARG)) {
                p.setProperty("dataOutputDirectory", arg.substring(DATAOUT_ARG.length()));
            } else if (arg.startsWith(PW_ARG)) {
                p.setProperty("password", arg.substring(PW_ARG.length()));
            } else if (arg.startsWith(PGSQLDIR_ARG)) {
                p.setProperty("pgsql", arg.substring(PGSQLDIR_ARG.length()));
            }
        }

        DriverManager.registerDriver(new OracleDriver());
        new ExportDDL(p).run();
    }

    public ExportDDL(Properties p) throws IOException {
        this.config = p;
        this.schemas = config.getProperty("schemas").split(",");
        this.outDir = new File(config.getProperty("dataOutputDirectory"));
        if (!outDir.exists()) outDir.mkdirs();
        if (!outDir.isDirectory()) throw new IOException("outdir not a dir: " + outDir.getAbsolutePath());
        if (config.getProperty("pgsql") != null) {
            this.pgOutDir = new File(config.getProperty("pgsql"));
            if (!pgOutDir.exists()) pgOutDir.mkdirs();
            if (!pgOutDir.isDirectory()) throw new IOException("pgsql not a dir: " + pgOutDir.getAbsolutePath());
        } else {
            this.pgOutDir = null;
        }
    }

    @Override
    public void run() {
        Properties p = new Properties();
        // user and password must exist in the properties as they are passed to the connection factory
        p.setProperty("user", config.getProperty("username"));
        p.setProperty("password", config.getProperty("password"));

        try {
            c = DriverManager.getConnection(config.getProperty("url"), p);
            expMssUsers();
            expQueueTabs();
            expCheckConstraints();
            expFKConstraints();
            for (String schema : schemas) {
                schema = schema.trim();
                expSchema(schema);
            }
            System.out.println("Done.");
        } catch (IOException | SQLException e) {
            throw new RuntimeException(e.getMessage(), e);
        } finally {
            if (c != null) try { c.close(); } catch (SQLException e) {}
        }
    }

    private static final String Q_MSS_USERS =
            "select distinct r.grantee from dba_role_privs r " +
                    " where granted_role in ('MSS_LOGIN_USER', 'MSS_SCHEMA_USER') " +
                    "   and r.grantee != 'SYS'";
    /**
     * Exports stuff of users that don't necessarily own objects.
     * Especially grants.
     */
    private void expMssUsers() throws IOException {
        PreparedStatement s = null;
        ResultSet rs = null;
        try {
            s = c.prepareStatement(Q_MSS_USERS);
            rs = s.executeQuery();
            while (rs.next()) {
                String user = rs.getString("grantee");
                expUser(user);
                expGrants(user);
            }
            expPublicGrants();
        } catch (SQLException e) {
            throw new IOException("could not obtain MSS users: " + e.getMessage(), e);
        } finally {
            if (rs != null) try { rs.close(); } catch (SQLException e) {}
            if (s != null) try { s.close(); } catch (SQLException e) {}
        }
    }

    private static final String Q_QUEUE_TABS =
            "select owner, queue_table from dba_queue_tables where owner != 'SYS' order by owner, queue_table";

    /**
     * Liquibase wrongly exports tables for AQ queues even though those are generated automatically when a queue is defined.
     * We don't want those in the generated schema file. In order to remove the later we export a list of them here.
     */
    private void expQueueTabs() throws IOException {
        System.out.println("Queue Tables");
        File f = new File(outDir, "exclude-tables.sed");
        PreparedStatement s = null;
        ResultSet rs = null;
        try (Writer out = new OutputStreamWriter(new BufferedOutputStream(new FileOutputStream(f)), encoding)) {
            s = c.prepareStatement(Q_QUEUE_TABS);
            rs = s.executeQuery();
            while (rs.next()) {
                out.write("/^CREATE TABLE ");
                out.write(rs.getString("owner"));
                out.write('.');
                out.write(rs.getString("queue_table"));
                out.write(" /d\n");
            }
        } catch (SQLException e) {
            throw new IOException("could not obtain MSS users: " + e.getMessage(), e);
        } finally {
            if (rs != null) try { rs.close(); } catch (SQLException e) {}
            if (s != null) try { s.close(); } catch (SQLException e) {}
        }
    }

    private void expUser(String user) throws IOException {
        System.out.printf("User: %s\n", user);
        List<String> legacyLogins = List.of("dbreader", "svc_zerotrust");
        List<String> legacyDataSchema = List.of("svc_zerotrust");

        int runs = (this.pgOutDir != null) ? 2 : 1;
        boolean pgDialect = false;

        while (runs-- > 0) {
            File dir = pgDialect ? new File(pgOutDir, "users") : new File(outDir, "users");
            String user_cased = pgDialect ? user.toLowerCase() : user;
            dir.mkdirs();
            File f = new File(dir, user + ".sql");
            PreparedStatement s = null;
            ResultSet rs = null;
            try (Writer out = new OutputStreamWriter(new BufferedOutputStream(new FileOutputStream(f)), encoding)) {
                if (pgDialect) {
                    String existing_user = String.format("DO\n" +
                            "$do$\n" +
                            "    DECLARE\n" +
                            "        v_user VARCHAR = '%s';\n" +
                            "        v_admin VARCHAR ='postgresadmin';\n" +
                            "    BEGIN\n" +
                            "        IF\n" +
                            "            EXISTS (SELECT\n" +
                            "                    FROM pg_catalog.pg_roles\n" +
                            "                    WHERE rolname = v_user) THEN\n" +
                            "            RAISE\n" +
                            "                NOTICE 'Role v_user already exists. Skipping.';\n" +
                            "        ELSE", user_cased);
                    out.write(existing_user);

                    if (user.toLowerCase().startsWith("svc_") && !legacyDataSchema.contains(user.toLowerCase())) {
                        out.write("\tEXECUTE format('CREATE USER %I', v_user);\n"); // default is no password, login disabled though
                        out.write("END IF;\n");
                    } else if (legacyLogins.contains(user_cased)) {
                        out.write("\tEXECUTE format('CREATE USER %I', v_user);\n"); // default is no password, login disabled though
                        out.write("END IF;\n");
                        out.write("EXECUTE format('GRANT %I TO %I', v_user, v_admin);\n");
                        out.write(String.format("CREATE SCHEMA AUTHORIZATION \"%s\";\n ", user_cased));
                    } else {
                        out.write("\tEXECUTE format('CREATE ROLE %I', v_user);\n"); // Role is a User, without login
                        out.write("END IF;\n");
                        out.write("EXECUTE format('GRANT %I TO %I', v_user, v_admin);\n");
                        out.write("EXECUTE format('CREATE SCHEMA AUTHORIZATION %I', v_user);\n");
                    }
                    out.write("EXECUTE format('ALTER ROLE %I SET search_path TO %I, public', v_user, v_user);\n");
                    out.write("END \n$do$;\n");
                } else { // Oracle, every schema is User too
                    out.write("CREATE USER \"");
                    out.write(user);
                    out.write("\" IDENTIFIED BY \"xxxxxx\" ACCOUNT LOCK\n" +
                            "DEFAULT TABLESPACE \"USERS\"\n" +
                            "TEMPORARY TABLESPACE \"TEMP\";\n");
                }

                // roles
                s = c.prepareStatement("select granted_role, default_role from dba_role_privs where grantee = ?");
                s.setString(1, user_cased);
                rs = s.executeQuery();
                while (rs.next()) {
                    String role = pgDialect ? rs.getString(1).toLowerCase() : rs.getString(1);
                    boolean isDefault = "YES".equals(rs.getString(2));

                    out.write(String.format("GRANT \"%s\" TO \"%s\"", role, user_cased));

                    if (pgDialect && !isDefault) {
                        out.write(" WITH INHERIT FALSE");
                    }
                    if (isDefault && !pgDialect) {
                        out.write(";\n"); // in ORA speak these are two statements
                        out.write(String.format("ALTER USER \"%s\"\n", user_cased));
                        out.write(String.format(" DEFAULT ROLE \"%s\"\n", role));
                    }
                    out.write(";\n");
                }

                rs.close();
                s.close();

                // quota per USer - exists in Oracle only
                if (!pgDialect) {
                    out.write(String.format("ALTER USER \"%s\"", user_cased));
                    out.write(" QUOTA UNLIMITED ON \"USERS\";\n");
                }
                // system privs - difficult to translate to other dialect
                if (!pgDialect) {
                    s = c.prepareStatement("select privilege from dba_sys_privs where grantee = ?");
                    s.setString(1, user);
                    rs = s.executeQuery();
                    while (rs.next()) {
                        String priv = rs.getString(1);
                        out.write("GRANT ");
                        out.write(priv);
                        out.write(" TO \"");
                        out.write(user);
                        out.write("\";\n");
                    }
                }
                out.flush();
            } catch (SQLException e) {
                throw new IOException("could not obtain grants: " + e.getMessage(), e);
            } finally {
                if (rs != null) try {
                    rs.close();
                } catch (SQLException e) {
                }
                if (s != null) try {
                    s.close();
                } catch (SQLException e) {
                }
            }
            pgDialect = true;
        }
    }

    private static final String Q_OBJ_GRANTS =
            "select * from dba_tab_privs where grantee = ? order by type, owner, table_name, privilege";

    /**
     * Grants are not supported by Liquibase, so we export them here.
     */
    private void expGrants(String schema) throws IOException {
        System.out.printf("Grants: %s\n", schema);
        File dir = new File(outDir, "grants");
        dir.mkdirs();
        File f = new File(dir, schema + ".sql");
        PreparedStatement s = null;
        ResultSet rs = null;
        try (Writer out = new OutputStreamWriter(new BufferedOutputStream(new FileOutputStream(f)), encoding)) {
            s = c.prepareStatement(Q_OBJ_GRANTS);
            s.setString(1, schema);
            rs = s.executeQuery();
            while (rs.next()) {
                String owner = rs.getString("owner");
                String tab = rs.getString("table_name");
                if (tab.startsWith("BIN$")) continue; // no deleted objects
                if ("AQ$_UNFLUSHED_DEQUEUES".equals(tab) && "SYS".equals(owner)) continue; // implicit
                if (tab.startsWith("QT") && tab.endsWith("_BUFFER") && "SYS".equals(owner)) continue; // implicit
                out.write("GRANT ");
                out.write(rs.getString("privilege"));
                out.write(" ON ");
                out.write(owner);
                out.write('.');
                out.write(tab);
                out.write(" TO ");
                out.write(rs.getString("grantee"));
                if ("YES".equals(rs.getString("grantable"))) {
                    out.write(" WITH GRANT OPTION");
                }
                out.write(";\n");
            }
        } catch (SQLException e) {
            throw new IOException("could not obtain grants: " + e.getMessage(), e);
        } finally {
            if (rs != null) try { rs.close(); } catch (SQLException e) {}
            if (s != null) try { s.close(); } catch (SQLException e) {}
        }
    }

    private static final String Q_OBJ_GRANTS_PUBLIC =
            "select * from dba_tab_privs where grantee = 'PUBLIC' and owner in (" + Q_MSS_USERS + ") order by type, owner, table_name, privilege";
    /**
     * Grants to public synonyms to our stuff.
     */
    private void expPublicGrants() throws IOException {
        String schema = "PUBLIC";
        System.out.printf("Grants: %s\n", schema);
        File dir = new File(outDir, "grants");
        dir.mkdirs();
        File f = new File(dir, schema + ".sql");
        PreparedStatement s = null;
        ResultSet rs = null;
        try (Writer out = new OutputStreamWriter(new BufferedOutputStream(new FileOutputStream(f)), encoding)) {
            s = c.prepareStatement(Q_OBJ_GRANTS_PUBLIC);
            rs = s.executeQuery();
            while (rs.next()) {
                String owner = rs.getString("owner");
                String tab = rs.getString("table_name");
                if (tab.startsWith("BIN$")) continue; // no deleted objects
                if ("AQ$_UNFLUSHED_DEQUEUES".equals(tab) && "SYS".equals(owner)) continue; // implicit
                if (tab.startsWith("QT") && tab.endsWith("_BUFFER") && "SYS".equals(owner)) continue; // implicit
                out.write("GRANT ");
                out.write(rs.getString("privilege"));
                out.write(" ON ");
                out.write(owner);
                out.write('.');
                out.write(tab);
                out.write(" TO ");
                out.write(rs.getString("grantee"));
                if ("YES".equals(rs.getString("grantable"))) {
                    out.write(" WITH GRANT OPTION");
                }
                out.write(";\n");
            }
        } catch (SQLException e) {
            throw new IOException("could not obtain grants: " + e.getMessage(), e);
        } finally {
            if (rs != null) try { rs.close(); } catch (SQLException e) {}
            if (s != null) try { s.close(); } catch (SQLException e) {}
        }
    }

    private void expSchema(String schema) throws IOException {
        expSequences(schema);
        expTriggers(schema);
    }

    private static final String Q_SEQUENCES =
            "select * from dba_sequences where sequence_owner=? order by sequence_name";

    /**
     * Sequence export from Liquibase includes the current value as starts with.
     * We want the initial value. Also Liquibase doesn't sort them which causes ugly diffs.
     */
    private void expSequences(String schema) throws IOException {
        System.out.printf("Sequences: %s\n", schema);
        File dir = new File(outDir, "sequences");
        dir.mkdirs();
        File f = new File(dir, schema + ".sql");
        PreparedStatement s = null;
        ResultSet rs = null;
        try (Writer out = new OutputStreamWriter(new BufferedOutputStream(new FileOutputStream(f)), encoding)) {
            s = c.prepareStatement(Q_SEQUENCES);
            s.setString(1, schema);
            rs = s.executeQuery();
            while (rs.next()) {
                String name = rs.getString("sequence_name");
                // AQ sequences are implicitly created
                if (name.startsWith("AQ$")) continue;
                out.write("CREATE SEQUENCE ");
                out.write(rs.getString("sequence_owner")); out.write('.');
                out.write(name);
                if (rs.getLong("min_value") != 1) {
                    out.write(" START WITH ");
                    out.write(rs.getString("min_value"));
                }
                if (rs.getLong("increment_by") != 1) {
                    out.write(" INCREMENT BY ");
                    out.write(rs.getString("increment_by"));
                }
                if ("Y".equals(rs.getString("order_flag"))) {
                    out.write(" ORDER");
                }
                int cache = rs.getInt("cache_size");
                if ((cache != 20) && (cache > 0)) {
                    out.write(" CACHE ");
                    out.write(cache);
                }
                out.write(";\n");
            }
        } catch (SQLException e) {
            throw new IOException("could not obtain sequences: " + e.getMessage(), e);
        } finally {
            if (rs != null) try { rs.close(); } catch (SQLException e) {}
            if (s != null) try { s.close(); } catch (SQLException e) {}
        }
    }

    private static final String Q_TRIGGERS =
            "select * from dba_triggers where owner=? order by trigger_name";

    private void expTriggers(String schema) throws IOException {
        System.out.printf("Triggers: %s\n", schema);
        File dir = new File(outDir, "triggers");
        dir.mkdirs();
        File f = new File(dir, schema + ".sql");
        PreparedStatement s = null;
        ResultSet rs = null;
        int count = 0;
        try (Writer out = new OutputStreamWriter(new BufferedOutputStream(new FileOutputStream(f)), encoding)) {
            out.write("--liquibase formatted sql logicalFilePath:triggers/" + schema + ".sql\n");
            s = c.prepareStatement(Q_TRIGGERS);
            s.setString(1, schema);
            rs = s.executeQuery();
            char[] buf = new char[512];
            while (rs.next()) {
                out.write("--changeset sys:" + (count + 1) + " runOnChange:true endDelimiter:/\n");
                out.write("CREATE OR REPLACE TRIGGER ");
                // "trigger name after|before insert or ... of ... on ... for each row"
                out.write(rs.getString("description"));
                if ("DISABLED".equals(rs.getString("status"))) {
                    out.write("DISABLE\n");
                }

                String when = rs.getString("when_clause");
                if (when != null) {
                    out.write("(\n");
                    out.write(when);
                    out.write(")\n");
                }

                try (Reader r = rs.getCharacterStream("trigger_body")) {
                    int len = 0;
                    while ((len = r.read(buf)) != -1) {
                        out.write(buf, 0, len);
                    }
                }

                out.write("\n/\n\n");
                count++;
            }
        } catch (SQLException e) {
            throw new IOException("could not obtain triggers: " + e.getMessage(), e);
        } finally {
            if (rs != null) try { rs.close(); } catch (SQLException e) {}
            if (s != null) try { s.close(); } catch (SQLException e) {}
            if (count == 0) { f.delete(); }
        }
    }


    private static final String Q_CONS =
            "select * from dba_constraints " +
                    "where constraint_type='C' " +
                    "and owner=? " +
                    "and generated != 'GENERATED NAME' " +
                    "and constraint_name not like 'BIN$%' " +
                    "order by table_name, constraint_name";

    /**
     * Liquibase does not support user defined check constraints.
     */
    private void expCheckConstraints() throws IOException {
        System.out.print("Check Constraints\n");
        File f = new File(outDir, "check-constraints.oracle.sql");
        PreparedStatement s = null;
        ResultSet rs = null;
        try (Writer out = new OutputStreamWriter(new BufferedOutputStream(new FileOutputStream(f)), encoding)) {
            s = c.prepareStatement(Q_CONS);
            char[] buf = new char[256];
            for (String schema : schemas) {
                s.setString(1, schema);
                rs = s.executeQuery();
                while (rs.next()) {
                    out.write("ALTER TABLE ");
                    out.write(rs.getString("owner")); out.write('.');
                    out.write(rs.getString("table_name"));
                    out.write(" ADD CONSTRAINT ");
                    out.write(rs.getString("constraint_name"));
                    out.write(" CHECK (");
                    try (Reader r = rs.getCharacterStream("search_condition")) {
                        int len = 0;
                        while ((len = r.read(buf)) != -1) {
                            out.write(buf, 0, len);
                        }
                    }
                    out.write(")");
                    // constraint state: [DEFERRABLE] [INITIALLY DEFERRED] [DISABLE]
                    if ("DEFERRABLE".equals(rs.getString("deferrable"))) {
                        out.write(" DEFERRABLE");
                        if ("DEFERRED".equals(rs.getString("deferred"))) {
                            out.write(" INITIALLY DEFERRED");
                        }
                    }
                    if ("DISABLED".equals(rs.getString("status"))) {
                        out.write(" DISABLE");
                    }
                    out.write(";\n");
                }
                rs.close();
                rs = null;
            }
        } catch (SQLException e) {
            throw new IOException("could not obtain check constraints: " + e.getMessage(), e);
        } finally {
            if (rs != null) try { rs.close(); } catch (SQLException e) {}
            if (s != null) try { s.close(); } catch (SQLException e) {}
        }
    }

    private static final String Q_FKCONST =
            "select c.owner, c.table_name, c.constraint_name, c.r_owner, rc.table_name r_table_name, " +
                    "c.deferrable, c.deferred, c.status, c.delete_rule, " +
                    "listagg(cc.COLUMN_NAME, ', ') within group (order by cc.POSITION) as COLUMNS, " +
                    "listagg(rcc.COLUMN_NAME, ', ') within group (order by rcc.POSITION) as R_COLUMNS " +
                    "from DBA_CONSTRAINTS c, DBA_CONS_COLUMNS cc, DBA_CONSTRAINTS rc, DBA_CONS_COLUMNS rcc " +
                    "where c.CONSTRAINT_TYPE='R' " +
                    "and cc.OWNER = c.OWNER " +
                    "and cc.TABLE_NAME = c.TABLE_NAME " +
                    "and cc.CONSTRAINT_NAME = c.CONSTRAINT_NAME " +
                    "and rc.OWNER = c.R_OWNER " +
                    "and rc.CONSTRAINT_NAME = c.R_CONSTRAINT_NAME " +
                    "and rcc.OWNER = rc.OWNER " +
                    "and rcc.TABLE_NAME = rc.TABLE_NAME " +
                    "and rcc.CONSTRAINT_NAME = rc.CONSTRAINT_NAME " +
                    "and c.owner = ? " +
                    "group by c.owner, c.table_name, c.constraint_name, c.r_owner,  rc.table_name, c.deferrable, c.deferred, c.status, c.delete_rule " +
                    "order by c.table_name, c.constraint_name";

    // Liquibase exports wrong constraint status
    private void expFKConstraints() throws IOException {
        System.out.print("FK Constraints\n");
        File f = new File(outDir, "constraints.oracle.sql");
        PreparedStatement s = null;
        ResultSet rs = null;
        try (Writer out = new OutputStreamWriter(new BufferedOutputStream(new FileOutputStream(f)), encoding)) {
            s = c.prepareStatement(Q_FKCONST);
            char[] buf = new char[256];
            for (String schema : schemas) {
                s.setString(1, schema);
                rs = s.executeQuery();
                while (rs.next()) {
                    out.write("ALTER TABLE ");
                    out.write(rs.getString("owner")); out.write('.');
                    out.write(rs.getString("table_name"));
                    out.write(" ADD CONSTRAINT ");
                    out.write(rs.getString("constraint_name"));
                    out.write(" FOREIGN KEY (");
                    out.write(rs.getString("columns"));
                    out.write(") REFERENCES ");
                    out.write(rs.getString("r_owner")); out.write('.');
                    out.write(rs.getString("r_table_name"));
                    out.write(" (");
                    out.write(rs.getString("r_columns"));
                    out.write(")");
                    // delete rule
                    String delRule = rs.getString("delete_rule");
                    if (delRule != null && !"NO ACTION".equals(delRule)) {
                        out.write(" ON DELETE ");
                        out.write(delRule);
                    }

                    // constraint state: [DEFERRABLE] [INITIALLY DEFERRED] [DISABLE]
                    if ("DEFERRABLE".equals(rs.getString("deferrable"))) {
                        out.write(" DEFERRABLE");
                        if ("DEFERRED".equals(rs.getString("deferred"))) {
                            out.write(" INITIALLY DEFERRED");
                        }
                    }
                    if ("DISABLED".equals(rs.getString("status"))) {
                        out.write(" DISABLE");
                    }
                    out.write(";\n");
                }
                rs.close();
                rs = null;
            }
        } catch (SQLException e) {
            throw new IOException("could not obtain fk constraints: " + e.getMessage(), e);
        } finally {
            if (rs != null) try { rs.close(); } catch (SQLException e) {}
            if (s != null) try { s.close(); } catch (SQLException e) {}
        }
    }

}

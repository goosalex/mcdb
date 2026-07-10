import oracle.jdbc.OracleDriver;

import java.io.*;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.Paths;
import java.sql.*;
import java.util.*;

public class ExportCsvMeta implements Runnable {
    private final Properties config;
    private Connection c;
    private final String[] schemas;
    private final File outDir;
    private final Charset encoding = StandardCharsets.UTF_8;
    private static final String DEFAULTS_FILE_ARG = "--defaults-file=";
    private static final String DATAOUT_ARG = "--dataOutputDirectory=";
    private static final String PW_ARG = "--password=";

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
            }
        }

        DriverManager.registerDriver(new OracleDriver());
        new ExportCsvMeta(p).run();
    }

    public ExportCsvMeta(Properties p) throws IOException {
        this.config = p;
        this.schemas = config.getProperty("schemas").split(",");
        this.outDir = new File(config.getProperty("dataOutputDirectory"));
        if (!outDir.exists()) outDir.mkdirs();
        if (!outDir.isDirectory()) throw new IOException("outdir not a dir: "+ outDir.getAbsolutePath());
    }

    @Override
    public void run() {
        Properties p = new Properties();
        // user and password must exist in the properties as they are passed to the connection factory
        p.setProperty("user", config.getProperty("username"));
        p.setProperty("password", config.getProperty("password"));

        try {
            c = DriverManager.getConnection(config.getProperty("url"), p);
            for (String schema : schemas) {
                schema = schema.trim();
                expSchema(schema);
            }
            System.out.println("Done.");
        } catch (IOException|SQLException e) {
            throw new RuntimeException(e.getMessage(), e);
        } finally {
            if (c != null) try { c.close(); } catch (SQLException e) {}
        }
    }


    private void expSchema(String schema) throws IOException {
        File dir = new File(outDir, schema);
        if (!dir.exists()) return;
        if (!dir.isDirectory()) throw new IOException(dir.getAbsolutePath() +" is not a dir");
        File[] files = dir.listFiles(new FilenameFilter() {
            @Override
            public boolean accept(File dir, String name) {
                return name.endsWith(".csv");
            }
        });
        if ((files == null) || (files.length == 0)) return;
        for (File file : files) {
            String xml = replaceExt(file.getName(), "xml");
            File targetXml = new File(dir, xml);
            if (!(targetXml.exists()) || targetXml.length()==0)
                expMeta(file, targetXml);
        }
    }

    private static final String Q_COLS = "select column_name, data_type from dba_tab_columns " +
            "where owner=? and table_name=? " +
            "order by column_id";
    private static final Map<String, String> LQB_TYPE_BY_ORA = Map.of(
            "VARCHAR2", "STRING",
            "NUMBER", "NUMERIC",
            "TIMESTAMP", "DATE",
            "TIMESTAMP(6)", "DATE",
            "RAW", "skip"
    );

    private void expMeta(File file, File targetXml) throws IOException {
        String schema = file.getParentFile().getName().toUpperCase();
        String table = stripExt(file.getName()).toUpperCase();
        System.out.println(String.format("Generating new file %s / %s",schema,targetXml.getName()));
        PreparedStatement ps = null;
        ResultSet rs = null;
        try (Writer out = new OutputStreamWriter(new BufferedOutputStream(new FileOutputStream(targetXml)), encoding)) {
            ps = c.prepareStatement(Q_COLS);
            ps.setString(1, schema);
            ps.setString(2, table);
            rs = ps.executeQuery();
            while (rs.next()) {
                String col = rs.getString("column_name");
                String type = rs.getString("data_type");
                String lqbType = mapType(type);
                out.write("<column name=\"");out.write(col);
                out.write("\" type=\""); out.write(lqbType);
                out.write("\" />\n");
            }
        } catch (SQLException e) {
            throw new IOException("could not obtain columns: "+e.getMessage(), e);
        } finally {
            if (rs != null) try { rs.close(); } catch (SQLException e) {}
            if (ps != null) try { ps.close(); } catch (SQLException e) {}
        }
    }

    private String mapType(String oraType) {
        String lqbType = LQB_TYPE_BY_ORA.get(oraType);
        if (lqbType == null) lqbType = oraType;
        return lqbType;
    }

    private String replaceExt(String fn, String newExt) {
        int dot = fn.lastIndexOf('.');
        if (dot == -1) return fn;
        return fn.substring(0, dot+1)+newExt;
    }

    private String stripExt(String fn) {
        int dot = fn.lastIndexOf('.');
        if (dot == -1) return fn;
        return fn.substring(0, dot);
    }
}

package ch.open.osdb.build.changelog;

import ch.open.mss.orm.codegen.Configuration;
import ch.open.mss.orm.codegen.java.Sql2Java;
import liquibase.Contexts;
import liquibase.LabelExpression;
import liquibase.Liquibase;
import liquibase.Scope;
import liquibase.database.Database;
import liquibase.database.DatabaseFactory;
import liquibase.database.jvm.JdbcConnection;
import liquibase.resource.SearchPathResourceAccessor;
import oracle.jdbc.datasource.OracleDataSource;
import org.testcontainers.containers.OracleContainer;
import org.testcontainers.containers.wait.strategy.Wait;
import org.testcontainers.images.PullPolicy;
import org.testcontainers.utility.DockerImageName;

import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Duration;
import java.time.ZoneId;
import java.util.Arrays;
import java.util.Map;
import java.util.Properties;
import java.util.stream.Collectors;
import java.util.zip.ZipOutputStream;

/**
 * This is a glue class combining a lot of legacy code with testcontainers.org
 * as an environment for running oracle and a Zip output
 *
 * Pretty sure, the generated code will not win beauty contests, but honestly: do you care ?
 * It's tons of straight-forward generated POJOs for an ORM layer, you ain't gonna read read it!
 *
 * ...and also not modify it. Thou shalt not! And beware of the wicked and cursed MegaLinter.
 * Thus, go write the holy word "[nolint]" in thy commit message,
 * begin every gospel that touches the ORM with that magic formula,
 * and so will heaven, angels and your patient soul rejoyce.
 *
 * the final "amen", is fully upon thee, solely if you wish to do so.
 */
public class WriteORM {
    private static final String PROP_PATH = "osdb/mcdb/changes";
    private static final String JAVA_DEFAULT_TARGET = "applications/customer-portal/libs/java/core/src/main/";

    private String java_target_path = JAVA_DEFAULT_TARGET;

    private static final DockerImageName DEV_LOCAL_XEPDB1 = DockerImageName.parse(
                    "artifacts.open.ch/central-docker-prod-local/osdb/local_ora_mcdb:2")
            .asCompatibleSubstituteFor("gvenzl/oracle-xe");

    private OracleContainer xepdb1;

    public WriteORM() {
        this(JAVA_DEFAULT_TARGET);
    }

    public WriteORM(String javaTargetDir) {
        this.java_target_path = javaTargetDir;
    }

    /**
     *
     * @param args [0]Java_Library_Path [1]output_file.zip
     * @throws Exception
     */
    public static void main(String[] args) throws Exception {
        WriteORM writeORM;
        // recent Docker Desktop versions (Docker >v29) have a newver API as default
        System.setProperty("api.version", "1.44");
        if (args.length >= 2) {
            if (Files.exists(Paths.get(args[1]))) {
                System.err.println("Output file does already exist: " + args[1]);
                printUsage();
                System.exit(-1);
            }
            if (!Files.exists(Paths.get(args[0]))) {
                System.err.println("Can't find input main directory: " + args[0]);
                printUsage();
                System.exit(-1);
            }
            System.out.println("Goal: Zipping ORM output into " + args[1]);
            writeORM = new WriteORM(args[0]);
            writeORM.run(args[1]);
        } else {
            System.err.println("Output file is not specified");
            printUsage();
            System.exit(-1);
        }
    }

    public static void printUsage() {
        System.err.println("Usage: WriteORM <Base Path for Java ORM Sources & Resources> <outputZIPfile>");
    }

    public void run(String outputZipFile) throws Exception {
        try (OracleContainer oracleContainer = createContainer()) {
            oracleContainer.start();
            xepdb1 = oracleContainer;
            applyChangelog();
            printLastChangelogEntry();
            System.out.println("building ORM in " + this.java_target_path);
            rebuildORM(this.java_target_path);
            System.out.println("zipping it into " + outputZipFile);
            spitZip("generate", outputZipFile);
        }
    }

    private static OracleContainer createContainer() {
        return new OracleContainer(DEV_LOCAL_XEPDB1)
                .withImagePullPolicy(PullPolicy.alwaysPull())
                .withPassword("password")
                .withExposedPorts(1521)
                .waitingFor(Wait.forLogMessage("DATABASE IS READY TO USE!.*\\n", 1))
                .withStartupTimeout(Duration.ofSeconds(300));
    }

    public Properties readProperties() throws IOException {
        String prop_path = PROP_PATH + "/liquibase-orm.properties";
        Properties props = new Properties(15);
        props.load(new FileReader(prop_path));
        return props;
    }

    public void applyChangelog() throws Exception {

        if (!xepdb1.isRunning()) throw new Exception("Oracle XE Container has not been started");
        final Properties config = readProperties();
        System.setProperty("liquibase.secureParsing", "false");
        System.setProperty("liquibase.catalogName", config.getProperty("liquibase.catalogName", "LQB"));

        Scope.child((Map<String, Object>) null, () -> {
            try (Connection connection = openConnection(config);
                    Database database = DatabaseFactory.getInstance()
                            .findCorrectDatabaseImplementation(new JdbcConnection(connection))) {
                // This is needed to translate the relative (to the current pwd) searchPath in
                // containers/liquibase-orm.properties in correct
                // relative Paths to Panta Root, as guaranteed by the buildkite pipeline when run by bazel.
                String searchpath = Arrays.stream(
                                config.getProperty("liquibase.searchPath", ".").split(","))
                        .map(s -> {
                            if (s.startsWith(".")) {
                                return PROP_PATH + "/" + s;
                            } else {
                                return s;
                            }
                        })
                        .collect(Collectors.joining(","));

                // Begin of LOADING the "master" DB changelog, so your DB has the same structure as CURRENT master
                Liquibase liquibase = new liquibase.Liquibase(
                        config.getProperty("changelogFile", "root-changelog.xml"),
                        new SearchPathResourceAccessor(searchpath),
                        database);
                liquibase.getChangeLogParameters().set("liquibase.secureParsing", "false");

                // empty Context and Labels means: all of them
                liquibase.update(new Contexts(), new LabelExpression());
                // End of "master" Changelog.
                // You can repeat this step now for private changelogs,e.g. to load test fixtures ...
            }
        });
    }

    public void printLastChangelogEntry() throws Exception {
        Properties config = readProperties();
        PreparedStatement ps = null;
        ResultSet rs = null;
        try (Connection c = openConnection(config)) {
            ps = c.prepareStatement("select ID,AUTHOR,DATEEXECUTED,COMMENTS from LQB.DATABASECHANGELOG "
                    + "WHERE ORDEREXECUTED = (SELECT MAX(ORDEREXECUTED) FROM LQB.DATABASECHANGELOG WHERE EXECTYPE = 'EXECUTED')"
                    + " AND EXECTYPE = 'EXECUTED'");
            rs = ps.executeQuery();
            while (rs.next()) {
                System.out.printf(
                        "Last applied changelog entry: %s:%s on %Tc \\n%s",
                        rs.getString(1),
                        rs.getString(2),
                        rs.getTimestamp(3).toInstant().atZone(ZoneId.systemDefault()),
                        rs.getString(4));
            }
        } finally {
            if (rs != null)
                try {
                    rs.close();
                } catch (SQLException e) {
                }
            if (ps != null)
                try {
                    ps.close();
                } catch (SQLException e) {
                }
        }
    }

    public void rebuildORM(String java_target_path) throws Exception {
        Properties config = readProperties();
        Configuration sql2JavaConfiguration = new Configuration();
        /*
            output.path=$BAZEL_OUT \
        -d database.url=jdbc:oracle:thin:@localhost:1521/XEPDB1 -d database.user='SYS AS SYSDBA' -d database.pass=password \
        -d java.source.path=$PANTA_ROOT/dx/libs/java/core/src/main/java \
        -d java.resources.path=$PANTA_ROOT/dx/libs/java/core/src/main/resources -d schema.inspect.list=APPID,AUTH,CERTS,ESP,FW,FYI,GETNODES,GUMA2,MAIL,MC,MCAUDIT,MSS,NIDS,OSAG,PRX,REPORT,STOP,SVC_ZEROTRUST,TIM,TT,VPN
             */
        sql2JavaConfiguration.setProperty("database.url", xepdb1.getJdbcUrl());
        sql2JavaConfiguration.setProperty("database.user", config.getProperty("username"));
        sql2JavaConfiguration.setProperty("database.pass", config.getProperty("password"));
        sql2JavaConfiguration.setProperty("java.source.path", java_target_path + "/java");
        sql2JavaConfiguration.setProperty("mcdb.path", "osdb/mcdb");
        sql2JavaConfiguration.setProperty("output.path", "generate");
        sql2JavaConfiguration.setProperty("java.resources.path", java_target_path + "/resources");
        sql2JavaConfiguration.setProperty(
                "schema.inspect.list",
                "APPID,AUTH,CERTS,ESP,FW,FYI,GETNODES,GUMA2,MAIL,MC,MCAUDIT,MSS,NIDS,OSAG,OSIXINFO,PRX,REPORT,STOP,SVC_ZEROTRUST,TIM,TT,VPN");
        if (new File("generate").exists()) {
            if (!new File("generate").isDirectory()) throw new Exception("output.path is not a directory!");
        }
        new File("generate/java").mkdirs();
        new File("generate/resources/META-INF").mkdirs();
        if (!new File("generate/java").exists()) {
            throw new Exception("$output.path/java NOT created");
        }

        Sql2Java sql2Java = new Sql2Java(sql2JavaConfiguration);
        sql2Java.generate();
    }

    public void spitZip(String input_path, String target_file) throws IOException {
        FileOutputStream fos = new FileOutputStream(target_file);
        ZipOutputStream zipOut = new ZipOutputStream(fos);
        ZipDirectory.zipFile(new File(input_path), "main", zipOut);
        zipOut.close();
        fos.close();
    }

    private Connection openConnection(Properties config) throws SQLException {
        OracleDataSource ods = new oracle.jdbc.pool.OracleConnectionPoolDataSource();
        ods.setURL(xepdb1.getJdbcUrl());
        ods.setUser(config.getProperty("username"));
        ods.setPassword(config.getProperty("password"));
        System.out.println(ods.getURL());
        return ods.getConnection();
    }
}

package ch.open.osdb.build.changelog;

import ch.open.mss.orm.codegen.Configuration;
import ch.open.mss.orm.codegen.java.Sql2Java;
import jdk.jfr.Enabled;
import liquibase.Contexts;
import liquibase.LabelExpression;
import liquibase.Liquibase;
import liquibase.Scope;
import liquibase.database.Database;
import liquibase.database.DatabaseFactory;
import liquibase.database.jvm.JdbcConnection;
import liquibase.resource.SearchPathResourceAccessor;
import oracle.jdbc.datasource.OracleDataSource;
import org.apache.commons.collections4.iterators.EnumerationIterator;
import org.junit.jupiter.api.*;
import org.testcontainers.containers.OracleContainer;
import org.testcontainers.containers.wait.strategy.Wait;
import org.testcontainers.images.PullPolicy;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Duration;
import java.util.*;
import java.util.stream.Collectors;

@Testcontainers
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
public class ApplyTest {
    private static final String PROP_PATH = "osdb/mcdb/changes";
    private static final DockerImageName DEV_LOCAL_XEPDB1 = DockerImageName.parse(
                    "artifacts.open.ch/central-docker-prod-local/osdb/local_ora_mcdb:2")
            .asCompatibleSubstituteFor("gvenzl/oracle-xe");

    @Container
    private static final OracleContainer xepdb1 = createContainer();

    private static OracleContainer createContainer() {
        return new OracleContainer(DEV_LOCAL_XEPDB1)
                .withImagePullPolicy(PullPolicy.alwaysPull())
                .withPassword("password")
                .withExposedPorts(1521)
                .waitingFor(Wait.forLogMessage("DATABASE IS READY TO USE!.*\\n", 1))
                .withStartupTimeout(Duration.ofSeconds(300));
    }

    public Properties readProperties() throws IOException {
        String prop_path = PROP_PATH + "/liquibase-container.properties";
        Properties props = new Properties(15);
        props.load(new FileReader(prop_path));
        return props;
    }

    @Test
    @Order(1)
    public void _00applyChangelog() throws Exception {

        Assertions.assertTrue(xepdb1.isRunning());
        System.setProperty("liquibase.secureParsing", "false");

        final Properties config = readProperties();
        Map<String, Object> scopeConfig = new HashMap<>(20);
        config.entrySet().stream()
                .forEach(objectObjectEntry ->
                        scopeConfig.put(objectObjectEntry.getKey().toString(), objectObjectEntry.getValue()));

        scopeConfig.put("liquibase.catalogName", "LQB");
        Scope.child((Map<String, Object>) scopeConfig, () -> {
            try (Connection connection = openConnection(config);
                    Database database = DatabaseFactory.getInstance()
                            .findCorrectDatabaseImplementation(new JdbcConnection(connection))) {
                // This is needed to translate the relative (to the current pwd) searchPath in
                // containers/liquibase-container.properties in correct
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

    //@Test
    public void _10demoTestCase() throws Exception {
        Properties config = readProperties();
        PreparedStatement ps = null;
        ResultSet rs = null;
        try (Connection c = openConnection(config)) {
            ps = c.prepareStatement("select 2 from dual");
            rs = ps.executeQuery();
            while (rs.next()) {
                // do something
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

    //@Test
    @Order(2)
    public void rebuildORM() throws Exception {
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
        sql2JavaConfiguration.setProperty("java.source.path", "dx/libs/java/core/src/main/java");
        sql2JavaConfiguration.setProperty("mcdb.path", "osdb/mcdb");
        sql2JavaConfiguration.setProperty("output.path", "bazel-out/_tmp");
        sql2JavaConfiguration.setProperty("java.resources.path", "dx/libs/java/core/src/main/resources");
        sql2JavaConfiguration.setProperty(
                "schema.inspect.list",
                "APPID,AUTH,CERTS,ESP,FW,FYI,GETNODES,GUMA2,MAIL,MC,MCAUDIT,MSS,NIDS,OSAG,PRX,REPORT,STOP,SVC_ZEROTRUST,TIM,TT,VPN");
        new File("bazel-out/generate/java").mkdirs();
        new File("bazel-out/generate/resources").mkdirs();
        Sql2Java sql2Java = new Sql2Java(sql2JavaConfiguration);
        sql2Java.generate();
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

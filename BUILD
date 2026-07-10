load("//3rdparty/jvm:utils.bzl", "sources")
load("//3rdparty/jvm/testing/junit5:junit5.bzl", "java_junit5_test")

package(default_visibility = ["//visibility:public"])

sources()

java_library(
    name = "testlib",
    testonly = True,
    srcs = glob(["tests/src/test/java/**/*.java"]),
    data = glob([
        "changes/**",
        "ddl/src/**",
        "masterdata/**/*jdo_properties.csv",
        "mappingdata/**",
    ]),
    resources = ["tests/src/test/resources/testcontainers.properties"],
    visibility = ["//visibility:public"],
    deps = [
        ":tests_dependencies",
        "//3rdparty/jvm/default/com/oracle/database/jdbc:ojdbc10",
        "//3rdparty/jvm/default/org/liquibase:liquibase_core",
        "//3rdparty/jvm/default/org/testcontainers:oracle_xe",
        "//applications/customer-portal/tools/orm-codegen",
    ],
)

java_library(
    name = "tests_dependencies",
    testonly = True,
    exports = [
        "//3rdparty/jvm/default/org/junit/jupiter:junit_jupiter_api",
        "//3rdparty/jvm/default/org/junit/jupiter:junit_jupiter_params",
        "//3rdparty/jvm/default/org/testcontainers:junit_jupiter",
        "//3rdparty/jvm/default/org/testcontainers:oracle_xe",
    ],
    runtime_deps = [
        "//3rdparty/jvm/default/org/apache/logging/log4j:log4j_slf4j2_impl",
    ],
)

filegroup(
    name = "current_ddl",
    srcs = glob([
        "changes/**",
        "ddl/src/**",
        "mappingdata/*.sql",
        "masterdata/**/*jdo_properties.csv",
    ]),
)

java_binary(
    name = "changelog2java",
    srcs = [
        "tests/src/main/java/ch/open/osdb/build/changelog/WriteORM.java",
        "tests/src/main/java/ch/open/osdb/build/changelog/ZipDirectory.java",
    ],
    data = [
        "changes/liquibase-orm.properties",
        ":current_ddl",
        "//applications/customer-portal/libs/java/core/src/main/java/ch/open:java_sources",
        "//applications/customer-portal/libs/java/core/src/main/resources:datanucleus.properties",
        "//applications/customer-portal/libs/java/core/src/main/resources:orm_layer_properties",
    ],
    main_class = "ch.open.osdb.build.changelog.WriteORM",
    resources = ["tests/src/main/resources/testcontainers.properties"],
    visibility = ["//visibility:public"],
    runtime_deps = [
        "//3rdparty/jvm/default/org/apache/logging/log4j:log4j_slf4j2_impl",
    ],
    deps = [
        "//3rdparty/jvm/default/com/oracle/database/jdbc:ojdbc10",
        "//3rdparty/jvm/default/org/liquibase:liquibase_core",
        "//3rdparty/jvm/default/org/slf4j:slf4j_api",
        "//3rdparty/jvm/default/org/testcontainers:oracle_xe",
        "//applications/customer-portal/tools/orm-codegen",
    ],
)

genrule(
    name = "gen_sql2orm",
    srcs = [
        "tests/src/main/resources/testcontainers.properties",
        ":current_ddl",
        "changes/liquibase-orm.properties",
        "//applications/customer-portal/libs/java/core/src/main/java/ch/open:java_sources",
        "//applications/customer-portal/libs/java/core/src/main/resources:datanucleus.properties",
        "//applications/customer-portal/libs/java/core/src/main/resources:orm_layer_properties",
    ],
    outs = ["orm_layer.zip"],
    # ORM source and resource files are supposed to live under the same base.
    cmd = "TESTCONTAINERS_RYUK_DISABLED=true $(location :changelog2java) applications/customer-portal/libs/java/core/src/main $(OUTS)",
    tools = [":changelog2java"],
    tags = [
        "manual",
        "no-cache",
    ],
)

java_junit5_test(
    name = "tests",
    # see https://bazel.build/reference/test-encyclopedia#role-test-runner
    size = "large",
    data = glob([
        "changes/**",
        "ddl/src/**",
        "mappingdata/**",
    ]),
    library = [
        ":tests_dependencies",
        ":testlib",
    ],
    test_package = "ch.open.osdb.build.changelog",
)

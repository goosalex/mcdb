#!/bin/bash



# REPO_ROOT=$(pwd)
# assuming position osdb/mcdb/tests , go back to REPOROOT
cd "$(dirname "$(readlink -f "$0")")"/../../.. || exit

rm -f bazel-bin/osdb/mcdb/orm_layer.zip
# start a new Oracle container and derive ORM from current DDL and changelog
bazel build  "//osdb/mcdb:gen_sql2orm" --verbose_failures --sandbox_debug
# produces a new ORM Layer as a ZIP file (because a bazel gen_rule would need to give every single expected file..)
unzip -o -u -d applications/customer-portal/libs/java/core/src bazel-bin/osdb/mcdb/orm_layer.zip

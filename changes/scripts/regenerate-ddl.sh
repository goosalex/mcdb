#!/bin/bash
# typically pass --defaults-file=liquibase-prod.properties --password=... as arguments to this script
set -e
which liquibase >/dev/null || {
  echo "Liquibase not installed" >&2
  exit 1
}

(sed --version 2>/dev/null | grep -q GNU) || which gsed &>/dev/null || {
  echo "GNU sed not installed. Run: brew install gnu-sed" >&2
  exit 1
}
which gsed &>/dev/null || alias gsed=sed

# liquibase workdir
cd "$(dirname $(readlink -f $0))"/..
SCHEMA="../ddl/generated/schema.oracle.sql"
[ -e "${SCHEMA}" ] || {
  echo "Existing schema not found" >&2
>"${SCHEMA}"
liquibase generate-changelog "$@" --changelog-file="${SCHEMA}" --overwriteOutputFile=true --includeSchema=true --diffTypes=tables,views,columns,indexes,primarykeys,uniqueconstraints

}

echo "Running custom exporter"
scripts/exportddl.sh "$@"


# strip liquibase comments: we are not going to use them and the generated change IDs produce more diffs than necessary
gsed -i -e '/^--.*/d' "${SCHEMA}"

# strip excluded tables
gsed -i -f ../ddl/generated/exclude-tables.sed "${SCHEMA}"

# quote identifier where necessary
gsed -i -E '/^ALTER TABLE \S+ ADD CONSTRAINT .+ USING INDEX [A-Z]/ s/USING INDEX ([^.]+)\./USING INDEX "\1"./'  "${SCHEMA}"
# remove excess quoting
gsed -i -E '/""[A-Z]+""/ s/""/"/g' "${SCHEMA}"

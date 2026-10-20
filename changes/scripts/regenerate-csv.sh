#!/bin/bash
#Recreates the masterdata CSV files from the database
# typically pass --defaults-file=liquibase-prod.properties --password=... as arguments to this script
#set -e
shopt -s nullglob

function csv_sort() {
  local f="$1"
  # ignore empty files
  [ -s "${f}" ] || return
  # number of columns before the ID column: remove everything after "ID", then everything but the commas and count
  local C=$(head -1 "${f}" | sed -e 's/"ID".*//' -e 's/[^,]//g')
  C=${#C}
  # values are quoted, so abuse the quote char as separator: 2 quotes per field, start with 1
  C=$(( (C + 1) * 2 ))
  # join multi-lines with vertical tab
  gsed -z -E ' s/\n\n/\v\v/g ; s/\n([^"])/\v\1/g ' -i "${f}"
  local SORTED=$(mktemp)
  # use head for the header
  (head -1 "${f}" && tail -n +2 "${f}" | sort -t\" -k$C -n) >"${SORTED}"
  cat "${SORTED}" >"${f}"
  rm -f "${SORTED}"
  # revert vertical tabs
  gsed -e 's/\v/\n/g' -i "${f}"
}

# main
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
OUT="../masterdata"


for d in "${OUT}"/*; do
  CL="/tmp/lqb-${RANDOM}-${d}.oracle.sql"
  SCHEMA=$(basename "${d}")
  echo "Exporting CSV for ${SCHEMA}"
  OBJS=""
  for f in "${d}"/*.csv; do
    f=$(basename -s .csv "$f")
    f=$(echo $f | tr "[:lower:]" "[:upper:]")
    [ -n "${OBJS}" ] && OBJS="${OBJS},"
    OBJS="${OBJS}table:${f}"
  done

  # NPE in lqb? https://github.com/liquibase/liquibase/issues/3491
  [ -n "${OBJS}" ] && liquibase "$@" --includeObjects="${OBJS}" generate-changelog --schemas="${SCHEMA}" --changelog-file="${CL}" --dataOutputDirectory="${d}" --diffTypes=data
  echo "exported $OBJS"
  rm -f "${CL}"

  # sort by ID column
  for f in "${d}"/*.csv; do
    csv_sort "${f}"
  done
  echo "OK $SCHEMA"
done

echo "all OK"

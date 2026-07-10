#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset


# this file should be called by a ci-hook. It tests if the ORM layer needs to be updated in consequence of a database change
# because it modifies the local repo copy in the course of execution, it cannot be run as a test.

function inline_link {
  LINK=$(printf "url='%s'" "$1")

  if [ $# -gt 1 ]; then
    LINK=$(printf "%s;content='%s'" "$LINK" "$2")
  fi

  printf '\033]1339;%s\a\n' "$LINK"
}


__panta=$(git rev-parse --show-toplevel)
cd "$__panta"  || exit
. "$__panta/platforms/cicd/ci-scripts/include/common.sh"

status_close "Check ORM layer for changes after DB update."



CURRENT_COMMIT=$(buildkite-agent meta-data get current-commit)
# for better interpretation of the results, output of what is going to be checked
info "CURRENT_COMMIT $CURRENT_COMMIT"
# Ensure we have the reference branch
git fetch origin master:refs/remotes/origin/master || true
FORK_POINT=$(git merge-base --fork-point origin/master "$CURRENT_COMMIT" || true)
if [ -z "$FORK_POINT" ]; then
  # --fork-point failed, fall back to normal merge-base
  FORK_POINT=$(git merge-base origin/master "$CURRENT_COMMIT")
fi
info "FORK_POINT $FORK_POINT"
info "========  Difference  ======"
info "$(git diff "$FORK_POINT..$CURRENT_COMMIT" -- osdb/mcdb/changes/changelog*.sql)"
info "============================"

ORM_CHANGES=1
if git diff --quiet --exit-code "$FORK_POINT..$CURRENT_COMMIT" -- osdb/mcdb/mappingdata applications/customer-portal/tools/orm-codegen >/dev/null; then
  ORM_CHANGES=0
fi

DB_CHANGES=1
if git diff --quiet -G "ALTER|alter|DROP|drop|CREATE|create|JDO_PROPERTIES|jdo_properties" --exit-code "$FORK_POINT..$CURRENT_COMMIT" -- osdb/mcdb/changes/changelog*.sql >/dev/null; then
  DB_CHANGES=0
fi


if [ "$ORM_CHANGES" = "0" ] && [ "$DB_CHANGES" = "0" ]; then
  info "No obvious modifications to DB or ORM code generation found"
  info "between $FORK_POINT and $CURRENT_COMMIT"
  info "(No changes to changelog, mappingdata or generating code)"
  exit 0
fi

info "possible modifications to DB or ORM code generation found."
info "Regenerating ORM Layer"


if [ "$(arch)" = "arm64" ]; then
  info "This can at the moment only be run on Intel-based machines or the CI!"
  info "Check the output artifacts of the failing CI step for the necessary patch"
  exit 0
fi

# Will launch a new oracle container, applies the latest changelog and regenerates the ORM layer
# by extracting all DB-generated classes and files over the ORM in the current repository
rm -f bazel-bin/osdb/mcdb/orm_layer.zip
# start a new Oracle container and derive ORM from current DDL and changelog. On CI, Ryuk containers can die unexpectedly,
# without logs or reasons given. As the environment is always cleaned, stale containers are not a problem.
bazel build  "//osdb/mcdb:gen_sql2orm" --action_env=TESTCONTAINERS_RYUK_DISABLED=true --verbose_failures #--sandbox_debug
# produces a new ORM Layer as a ZIP file (because a bazel gen_rule would need to give every single expected file..)
# clear all directories containing DB classes from previous ORM files (to catch removed tables)
grep -l 'This code is auto generated' applications/customer-portal/libs/java/core/src/main/java/ch/open/mss/db/*/*.java | xargs -I % sh -c 'rm %'
# extract the newly generated classes and resources and sql-files (the latter two should not change names)
unzip -o -u -d applications/customer-portal/libs/java/core/src bazel-bin/osdb/mcdb/orm_layer.zip

# any uncommitted modifications due to changes in the DB will show up in a git diff afterwards
git add ./applications/customer-portal/libs/java/core/src/main/\*

if git diff --cached --ignore-all-space --quiet ./applications/customer-portal/libs/java/core/src/main && true; then
  info "The ORM update script was run or no changes in ORM ensued from these commits"
else
  error "The ORM update script was *not* run."
  error "We found differences to the output of CI-run ./osdb/mcdb/tests/update_dx_orm.sh "
  error "Please first commit the resulting changes to the ORM layer"
  error "in applications/customer-portal/libs/java/core/src/main"
  error "see also:"
  inline_link 'https://open-systems.atlassian.net/wiki/x/G4w7AQ' 'https://docs.open.ch/docs/display/DOC/OSDB%3A+How-to+generate+the+ORM+Layer+from+the+Database'
  git diff --cached --ignore-all-space --patch --output=dx_orm.patch ./applications/customer-portal/libs/java/core/src/main
      if [ "${CI:-}" = "true" ]; then
          buildkite-agent artifact upload dx_orm.patch
          info "Download and apply the build artifact dx_orm.patch"
          inline_link 'artifact://dx_orm.patch'
      else
          info "Not running in CI mode."
          info "You can apply dx_orm.patch, but do not commit it!"
      fi
  exit 1
fi

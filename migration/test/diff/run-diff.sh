#!/usr/bin/env bash
# migration/test/diff/run-diff.sh
#
# The DIFFERENTIAL half of the harness: run the same scenario against a real Oracle
# database (the MCDB Oracle container) and against the PostgreSQL translations,
# normalise both outputs (normalize.py) and diff them. "Oracle says X, PostgreSQL
# says X" evidence -- complementing run-tests.sh, whose assertions come from specs
# derived by static analysis.
#
# Usage:
#   run-diff.sh [--scenario NAME ...| --all]
#               [--ora-container NAME] [--ora-user USER] [--ora-service SVC]
#               [--pg-db NAME] [--pg-timezone TZ] [--install DIR | --no-install]
#               [--keep]
#               [--ora-capture DIR | --ora-from DIR] [--pg-capture DIR]
#
#   --scenario NAME   Run one scenario directory under scenarios/ (repeatable).
#   --all             Run every scenario (default when no --scenario is given).
#   --ora-container   Oracle container name. Default: $MCDB_ORA_CONTAINER or mcdb-ora.
#                      It is used READ-ONLY (docker exec sqlplus); this script never
#                      starts, stops or builds a container.
#   --ora-user        Connect as this user for every scenario, overriding meta.env's
#                      ORA_USER. Password: $MCDB_ORA_PASSWORD (default "password",
#                      the container's uniform schema password).
#   --ora-service     PDB service. Default: $MCDB_ORA_SERVICE or XEPDB1.
#   --pg-db NAME      Target database (must match bootstrap.sh's allowlist
#                      ^mcdb_(test|tmpl|harness)[a-z0-9_]*$). Default mcdb_test_diff.
#                      Rebuilt from mcdb_tmpl at the start of every run.
#   --pg-timezone TZ  Session timezone on the PostgreSQL side. Default: UTC -- the
#                      Oracle container has no TZ set, so SYSDATE there is UTC too
#                      (the preflight records Oracle's offset in oracle.env; a mismatch
#                      prints a warning).
#   --install DIR     Load every *.sql under DIR into the database before running,
#                      sorted by path, ON_ERROR_STOP=on. Default: migration/pgsql.
#   --no-install      Skip the install step (database already prepared).
#   --keep            Keep the PostgreSQL database and the .work/ files afterwards
#                      (they are always kept on DIFF/ERROR; --keep also keeps PASS).
#   --ora-capture DIR Save every raw Oracle capture as DIR/<scenario>.ora.raw plus
#                      DIR/oracle.env, for later offline replay.
#   --ora-from DIR    Do not connect to Oracle; replay DIR/<scenario>.ora.raw instead.
#   --pg-capture DIR  Save every raw PostgreSQL capture as DIR/<scenario>.pg.raw
#                      (used by the harness self-test in README.md).
#
# Per scenario, the result is one of:
#   PASS         normalised outputs identical
#   KNOWN        they differ, and the difference equals the scenario's known.diff
#                 (a documented, accepted deviation -- e.g. a DEVIATION(ORACLE-BUG))
#   STALE-KNOWN  known.diff exists but the sides now agree -> the file is stale (fails)
#   DIFF         they differ (the diff is printed)
#   NO-ORACLE    no Oracle data for this scenario (container not running and no
#                 --ora-from capture); the PostgreSQL side still ran
#   ERROR        a side produced no probe output at all (connect failure, compose error)
#
# Exit code: 0 only if every scenario is PASS or KNOWN and at least one scenario ran
# against Oracle data (live or replay). 2 when scenarios ran but none had Oracle data
# (nothing was compared). 1 otherwise.
#
# Needs bash 4+ (associative arrays), python3, docker.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
PG="${TEST_DIR}/../db/pg.sh"
PKGNAME_PY="${TEST_DIR}/lib/pkgname.py"
SCENARIOS_DIR="${SCRIPT_DIR}/scenarios"
WORK_DIR="${SCRIPT_DIR}/.work"
COMPOSE_PY="${SCRIPT_DIR}/compose.py"
NORMALIZE_PY="${SCRIPT_DIR}/normalize.py"

ORA_CONTAINER="${MCDB_ORA_CONTAINER:-mcdb-ora}"
ORA_SERVICE="${MCDB_ORA_SERVICE:-XEPDB1}"
ORA_PASSWORD="${MCDB_ORA_PASSWORD:-password}"
ORA_USER_OVERRIDE=""
PG_DB="mcdb_test_diff"
PG_TZ="UTC"
INSTALL_DIR="${REPO_ROOT}/migration/pgsql"
NO_INSTALL=0
KEEP=0
ORA_CAPTURE=""
ORA_FROM=""
PG_CAPTURE=""
SCENARIOS=()
ALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario) SCENARIOS+=("$2"); shift 2 ;;
    --all) ALL=1; shift ;;
    --ora-container) ORA_CONTAINER="$2"; shift 2 ;;
    --ora-user) ORA_USER_OVERRIDE="$2"; shift 2 ;;
    --ora-service) ORA_SERVICE="$2"; shift 2 ;;
    --pg-db) PG_DB="$2"; shift 2 ;;
    --pg-timezone) PG_TZ="$2"; shift 2 ;;
    --install) INSTALL_DIR="$2"; shift 2 ;;
    --no-install) NO_INSTALL=1; shift ;;
    --keep) KEEP=1; shift ;;
    --ora-capture) ORA_CAPTURE="$2"; shift 2 ;;
    --ora-from) ORA_FROM="$2"; shift 2 ;;
    --pg-capture) PG_CAPTURE="$2"; shift 2 ;;
    -h|--help) sed -n '2,60p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -n "$ORA_CAPTURE" && -n "$ORA_FROM" ]]; then
  echo "FATAL: --ora-capture and --ora-from are mutually exclusive" >&2; exit 1
fi
if [[ ! "$PG_DB" =~ ^mcdb_(test|tmpl|harness)[a-z0-9_]*$ || "$PG_DB" == "mcdb_tmpl" ]]; then
  echo "FATAL: --pg-db '${PG_DB}' is not an allowed disposable database name" >&2; exit 1
fi

# --- 1. Discover + validate scenarios against the name-map SSOT (D-P9) ------------

if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
  ALL=1
fi
if [[ "$ALL" -eq 1 ]]; then
  SCENARIOS=()
  while IFS= read -r d; do
    [[ -n "$d" ]] && SCENARIOS+=("$(basename "$d")")
  done < <(find "$SCENARIOS_DIR" -mindepth 1 -maxdepth 1 -type d -not -name '.*' | sort)
fi
if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
  echo "FATAL: no scenarios found under ${SCENARIOS_DIR}" >&2; exit 1
fi
for s in "${SCENARIOS[@]}"; do
  if [[ ! -d "${SCENARIOS_DIR}/${s}" ]]; then
    echo "FATAL: scenario directory does not exist: ${SCENARIOS_DIR}/${s}" >&2; exit 1
  fi
  # The scenario directory is named like a test file minus .sql; pkgname.py validates
  # the (pg_schema, oracle_package) pair against migration/mapping/name-map.csv.
  if ! python3 "$PKGNAME_PY" --list "${s}.sql" >/dev/null; then
    echo "FATAL: pkgname.py rejected scenario name '${s}' (SSOT violation)" >&2; exit 1
  fi
done

mkdir -p "$WORK_DIR"
[[ -n "$ORA_CAPTURE" ]] && mkdir -p "$ORA_CAPTURE"
[[ -n "$PG_CAPTURE" ]] && mkdir -p "$PG_CAPTURE"

# --- 2. Oracle availability --------------------------------------------------------

ORA_MODE="none"   # live | replay | none
if [[ -n "$ORA_FROM" ]]; then
  if [[ ! -d "$ORA_FROM" ]]; then
    echo "FATAL: --ora-from directory does not exist: ${ORA_FROM}" >&2; exit 1
  fi
  ORA_MODE="replay"
  echo "run-diff.sh: Oracle side replayed from ${ORA_FROM}"
else
  state="$(docker container inspect -f '{{.State.Status}}' "$ORA_CONTAINER" 2>/dev/null || echo absent)"
  if [[ "$state" == "running" ]]; then
    ORA_MODE="live"
    echo "run-diff.sh: Oracle container ${ORA_CONTAINER} is running -- live mode"
  else
    echo "run-diff.sh: Oracle container ${ORA_CONTAINER} is ${state} -- no Oracle side (use --ora-from DIR to replay a capture)"
  fi
fi

# sqlplus is driven through stdin (`sqlplus -s /nolog` + CONNECT line) so the password
# never appears on a command line inside the container.
run_sqlplus() {  # USER SCRIPT_FILE > stdout
  local user="$1" script="$2"
  {
    echo "CONNECT ${user}/${ORA_PASSWORD}@localhost:1521/${ORA_SERVICE}"
    cat "$script"
  } | timeout 900 docker exec -i "$ORA_CONTAINER" sqlplus -s /nolog 2>&1 || true
}

ORA_ENV_FILE="${WORK_DIR}/oracle.env"
if [[ "$ORA_MODE" == "live" ]]; then
  cat > "${WORK_DIR}/preflight.sql" <<'EOF'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF ECHO OFF TRIMOUT ON
WHENEVER SQLERROR CONTINUE
-- package constants are not usable in plain SQL (PLS-221); PRODUCT_COMPONENT_VERSION is public
SELECT 'ORA_VERSION=' || MAX(version_full) FROM product_component_version WHERE product LIKE 'Oracle%';
SELECT 'ORA_SESSIONTIMEZONE=' || SESSIONTIMEZONE FROM dual;
SELECT 'ORA_DBTIMEZONE=' || DBTIMEZONE FROM dual;
SELECT 'ORA_SYSTIMESTAMP_TZ=' || TO_CHAR(SYSTIMESTAMP, 'TZH:TZM') FROM dual;
SELECT 'ORA_SYSDATE=' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM dual;
SELECT 'ORA_PREFLIGHT_USER=' || USER FROM dual;
SELECT 'ORA_TT_TICKET_INTERFACE_BODY=' || status FROM all_objects WHERE owner = 'TT' AND object_name = 'TICKET_INTERFACE' AND object_type = 'PACKAGE BODY';
SELECT 'ORA_MSS_OSAG_IP_BODY=' || status FROM all_objects WHERE owner = 'MSS' AND object_name = 'OSAG_IP' AND object_type = 'PACKAGE BODY';
EXIT
EOF
  run_sqlplus "${ORA_USER_OVERRIDE:-tt}" "${WORK_DIR}/preflight.sql" > "${WORK_DIR}/preflight.out"
  grep -E '^ORA_[A-Z_]+=' "${WORK_DIR}/preflight.out" > "$ORA_ENV_FILE" || true
  if ! grep -q '^ORA_VERSION=' "$ORA_ENV_FILE"; then
    echo "FATAL: Oracle preflight failed (container up, but sqlplus could not run the probe):" >&2
    cat "${WORK_DIR}/preflight.out" >&2
    exit 1
  fi
  echo "run-diff.sh: Oracle preflight:"; sed 's/^/    /' "$ORA_ENV_FILE"
  ora_off="$(sed -n 's/^ORA_SYSTIMESTAMP_TZ=//p' "$ORA_ENV_FILE")"
  if [[ "$PG_TZ" == "UTC" && -n "$ora_off" && "$ora_off" != "+00:00" ]]; then
    echo "WARNING: Oracle SYSTIMESTAMP offset is ${ora_off} but the PostgreSQL session runs in UTC; pass --pg-timezone to match" >&2
  fi
  [[ -n "$ORA_CAPTURE" ]] && cp "$ORA_ENV_FILE" "${ORA_CAPTURE}/oracle.env"
elif [[ "$ORA_MODE" == "replay" && -f "${ORA_FROM}/oracle.env" ]]; then
  cp "${ORA_FROM}/oracle.env" "$ORA_ENV_FILE"
  echo "run-diff.sh: replayed capture's oracle.env:"; sed 's/^/    /' "$ORA_ENV_FILE"
fi

# --- 3. PostgreSQL side: fresh clone of the template + install -------------------

bash "$PG" start

pg_db_exists() {
  [[ "$(bash "$PG" psql -tAc "SELECT 1 FROM pg_database WHERE datname = '${PG_DB}'")" == "1" ]]
}

prepare_pg() {
  if [[ "$NO_INSTALL" -eq 1 ]] && pg_db_exists; then
    # --no-install means "the database is already prepared": reuse it as it is.
    echo "run-diff.sh: --no-install, reusing existing database ${PG_DB}"
    return 0
  fi
  echo "run-diff.sh: bootstrap.sh --db ${PG_DB} --template mcdb_tmpl"
  bash "${TEST_DIR}/bootstrap.sh" --db "$PG_DB" --template mcdb_tmpl >/dev/null
  if [[ "$NO_INSTALL" -eq 0 ]]; then
    if [[ ! -d "$INSTALL_DIR" ]]; then
      echo "FATAL: --install directory does not exist: ${INSTALL_DIR}" >&2; exit 1
    fi
    echo "run-diff.sh: installing *.sql from ${INSTALL_DIR} (sorted by path)..."
    local f
    while IFS= read -r -d '' f; do
      if ! bash "$PG" psql -X -q -v ON_ERROR_STOP=on -d "$PG_DB" -f "$f" >"${WORK_DIR}/install.log" 2>&1; then
        echo "FATAL: load failed for ${f}" >&2
        cat "${WORK_DIR}/install.log" >&2
        exit 1
      fi
    done < <(find "$INSTALL_DIR" -type f -name '*.sql' -print0 | sort -z)
  fi
}

prepare_pg
PG_DIRTY=0

# --- 4. Run every scenario -------------------------------------------------------

declare -A RESULT=()
declare -A ORASRC=()
declare -A NPROBES=()
ORACLE_RUNS=0

meta_get() {  # SCENARIO KEY DEFAULT
  local v
  v="$(sed -n -E "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"?([^\"#]*)\"?.*/\1/p" "${SCENARIOS_DIR}/$1/meta.env" 2>/dev/null | head -1 | sed 's/[[:space:]]*$//')"
  echo "${v:-$3}"
}

for s in "${SCENARIOS[@]}"; do
  sdir="${SCENARIOS_DIR}/${s}"
  w="${WORK_DIR}/${s}"
  rm -rf "$w"; mkdir -p "$w"
  commits="$(meta_get "$s" COMMITS no)"
  ora_user="${ORA_USER_OVERRIDE:-$(meta_get "$s" ORA_USER tt)}"
  echo ""
  echo "=== ${s}  (ORA_USER=${ora_user}, COMMITS=${commits}) ==="

  # compose both scripts first: a compose error is an ERROR before anything runs
  if ! python3 "$COMPOSE_PY" --dialect ora --scenario "$sdir" > "${w}/ora.sql" 2> "${w}/compose.err" \
     || ! python3 "$COMPOSE_PY" --dialect pg --scenario "$sdir" --pg-timezone "$PG_TZ" > "${w}/pg.sql" 2>> "${w}/compose.err"; then
    cat "${w}/compose.err" >&2
    RESULT["$s"]="ERROR"; ORASRC["$s"]="-"; NPROBES["$s"]="0"
    continue
  fi
  NPROBES["$s"]="$(python3 "$COMPOSE_PY" --dialect pg --scenario "$sdir" --count-probes)"

  # --- PostgreSQL side
  if [[ "$commits" == "yes" || "$PG_DIRTY" -eq 1 ]]; then
    prepare_pg   # a committing scenario gets -- and leaves behind -- a fresh clone
    PG_DIRTY=0
  fi
  [[ "$commits" == "yes" ]] && PG_DIRTY=1
  # pg.sh attaches no stdin, so the composed script is passed with -f; the repo tree is
  # mounted at the same path inside the container.
  (cd "$REPO_ROOT" && bash "$PG" psql --csv -X -q -v ON_ERROR_STOP=0 -d "$PG_DB" -f "${w}/pg.sql") > "${w}/pg.raw" 2>&1 || true
  [[ -n "$PG_CAPTURE" ]] && cp "${w}/pg.raw" "${PG_CAPTURE}/${s}.pg.raw"
  python3 "$NORMALIZE_PY" --dialect pg --meta "${sdir}/meta.env" "${w}/pg.raw" > "${w}/pg.norm"

  # --- Oracle side
  case "$ORA_MODE" in
    live)
      run_sqlplus "$ora_user" "${w}/ora.sql" > "${w}/ora.raw"
      [[ -n "$ORA_CAPTURE" ]] && cp "${w}/ora.raw" "${ORA_CAPTURE}/${s}.ora.raw"
      ORASRC["$s"]="live"
      ;;
    replay)
      if [[ -f "${ORA_FROM}/${s}.ora.raw" ]]; then
        cp "${ORA_FROM}/${s}.ora.raw" "${w}/ora.raw"
        ORASRC["$s"]="replay"
      else
        echo "    no capture ${ORA_FROM}/${s}.ora.raw"
        RESULT["$s"]="NO-ORACLE"; ORASRC["$s"]="-"
        continue
      fi
      ;;
    none)
      RESULT["$s"]="NO-ORACLE"; ORASRC["$s"]="-"
      if ! grep -q '^## probe' "${w}/pg.norm"; then
        echo "    PostgreSQL side produced no probe output:"; head -20 "${w}/pg.raw" | sed 's/^/    /'
        RESULT["$s"]="ERROR"
      fi
      continue
      ;;
  esac
  ORACLE_RUNS=$(( ORACLE_RUNS + 1 ))
  python3 "$NORMALIZE_PY" --dialect ora --meta "${sdir}/meta.env" "${w}/ora.raw" > "${w}/ora.norm"

  if ! grep -q '^## probe' "${w}/ora.norm"; then
    echo "    Oracle side produced no probe output (connect failure?):"; head -20 "${w}/ora.raw" | sed 's/^/    /'
    RESULT["$s"]="ERROR"; continue
  fi
  if ! grep -q '^## probe' "${w}/pg.norm"; then
    echo "    PostgreSQL side produced no probe output:"; head -20 "${w}/pg.raw" | sed 's/^/    /'
    RESULT["$s"]="ERROR"; continue
  fi

  # --- compare
  if diff -u --label "oracle/${s}" --label "postgresql/${s}" "${w}/ora.norm" "${w}/pg.norm" > "${w}/diff.txt"; then
    if [[ -f "${sdir}/known.diff" ]]; then
      echo "    sides agree but known.diff exists -- stale accepted deviation"
      RESULT["$s"]="STALE-KNOWN"
    else
      RESULT["$s"]="PASS"
    fi
  else
    grep -E '^[-+]' "${w}/diff.txt" | grep -vE '^(---|\+\+\+) ' > "${w}/diff.body" || true
    if [[ -f "${sdir}/known.diff" ]] && diff -q "${sdir}/known.diff" "${w}/diff.body" >/dev/null; then
      RESULT["$s"]="KNOWN"
      echo "    difference matches known.diff (accepted deviation):"
      sed 's/^/    /' "${w}/diff.body"
    else
      RESULT["$s"]="DIFF"
      echo "--- DIFF: ${s} (- oracle, + postgresql) ---"
      cat "${w}/diff.txt"
    fi
  fi
done

# --- 5. Table ---------------------------------------------------------------------

echo ""
printf '%-48s | %-7s | %-6s | %s\n' "SCENARIO" "ORACLE" "PROBES" "RESULT"
printf '%-48s-+-%-7s-+-%-6s-+-%s\n' "------------------------------------------------" "-------" "------" "-----------"
PASS=0; FAIL=0; NOORA=0
for s in "${SCENARIOS[@]}"; do
  r="${RESULT[$s]:-ERROR}"
  case "$r" in
    PASS|KNOWN) PASS=$(( PASS + 1 )) ;;
    NO-ORACLE) NOORA=$(( NOORA + 1 )) ;;
    *) FAIL=$(( FAIL + 1 )) ;;
  esac
  printf '%-48s | %-7s | %-6s | %s\n' "$s" "${ORASRC[$s]:--}" "${NPROBES[$s]:-0}" "$r"
done
echo ""
echo "TOTAL: ${#SCENARIOS[@]} scenarios, ${PASS} pass/known, ${FAIL} diff/error, ${NOORA} without Oracle data (oracle: ${ORA_MODE})"
echo "work files: ${WORK_DIR}/<scenario>/{ora,pg}.{sql,raw,norm} diff.txt"

# --- 6. Cleanup + exit code -------------------------------------------------------

if [[ "$KEEP" -eq 0 && "$FAIL" -eq 0 ]]; then
  bash "$PG" psql -X -q -c "DROP DATABASE IF EXISTS ${PG_DB};" >/dev/null 2>&1 || true
else
  echo "database ${PG_DB} kept"
fi

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
if [[ "$ORACLE_RUNS" -eq 0 ]]; then
  echo "NOTE: no scenario had Oracle data -- nothing was compared (exit 2)" >&2
  exit 2
fi
exit 0

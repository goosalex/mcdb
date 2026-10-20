# migration/test/

The dual test harness for the Oracle → PostgreSQL migration (Phase 2, HARN-01/02/04).
Every later plan in this phase — and Phase 4's bulk translation after it — runs its
verification through this harness. **A green result this harness reports is only
meaningful because the harness has been observed rejecting a wrong answer.** If you
change any part of this tree, re-run the falsifiability proof below before trusting
it again.

## Layout

```
migration/test/
├── bootstrap.sh              Disposable-database builder (--bare | --template)
├── bootstrap/
│   └── 00_extensions.sql     CREATE EXTENSION orafce; CREATE EXTENSION pgtap;
├── run-tests.sh              The one command: runs both harness halves, prints
│                              a per-package pass/fail table
├── redgreen.sh                The red-before/green-after gate (mechanised
│                              success criterion 5)
├── lib/
│   └── pkgname.py             Package-identity resolution against
│                              migration/mapping/name-map.csv (D-P9)
├── pgtap/
│   └── <pg_schema>__<oracle_package_lower>__<topic>.sql   pgTAP assertion files
├── regress/
│   ├── sql/<...>.sql          Plain-SQL scripts, run via psql
│   ├── expected/<...>.out     Golden output, diffed against results/
│   └── results/                Actual output from the last run (gitignored)
└── .gitignore                 regress/results/, *.log
```

## Database container

The harness runs against PostgreSQL 18.6 with orafce, pgTAP and `pg_prove`, in a Docker container managed by [`migration/db/pg.sh`](../db/pg.sh) (image: [`migration/db/Dockerfile`](../db/Dockerfile)). No local PostgreSQL installation is needed; Docker is.

- Every entry point (`bootstrap.sh`, `build-template.sh`, `run-tests.sh`, `run-all.sh`, `redgreen.sh`, the `bootstrap/*.sh` steps and `../regenerate.sh`) runs `pg.sh start` first. It builds the image when the Dockerfile changed, starts or recreates the container `mcdb-pg`, and waits until the server accepts connections.
- Every `psql` and `pg_prove` call goes through `pg.sh psql|pg_prove`, which runs the tool inside the container as `postgres`, in the caller's working directory.
- The container mounts the `mcdb` project and the targets of its `ddl/` and `masterdata/` symlinks read-only at their host paths, so `-f` paths, relative paths and `\ir` includes resolve as on the host.
- Data lives in the Docker volume `mcdb-pg-data`, so `mcdb_tmpl` survives container restarts. `pg.sh stop` removes the container and keeps the data; `pg.sh reset` removes both.
- The image build needs `deb.debian.org` and `apt.postgresql.org`. `pg.sh` forwards `http_proxy`/`https_proxy`/`no_proxy` from the environment to the build.
- `pg.sh shell` opens an interactive `psql` session; `pg.sh status` shows the container state.

`run-tests.sh` and `../spec/provenance_lint.sh` need bash 4 or later (associative arrays, `mapfile`); on macOS run them with a Homebrew bash.

## The three commands

### `bootstrap.sh --db NAME [--template TMPL] [--bare]`

Builds a disposable PostgreSQL database, run as the `postgres` superuser in the PostgreSQL 18.6 container (see [Database container](#database-container)).

- `--bare`: drop-if-exists, create empty, apply `bootstrap/00_extensions.sql`
  only. No schema. Used when no template exists yet (this plan, 02-01).
- `--template TMPL` (default `mcdb_tmpl` once plan 02-03 builds it): drop-if-exists,
  `CREATE DATABASE NAME TEMPLATE TMPL`. Near-instant — this is what lets several
  plans in the same wave run against isolated databases without racing each other
  or re-loading the ~9.7k-line `ddl/migrated` schema each time (D-P8).

Safety: `NAME` (and `TMPL`) must match `^mcdb_(test|tmpl|harness)[a-z0-9_]*$` or the
script refuses to run — a typo must never `DROP DATABASE` something real (T-02-01).

### `run-tests.sh [--db NAME] [--install DIR] [--package PKG] [--filter GLOB]`

The one command that runs both harness halves and reports one row per Oracle
package:

- **pgTAP half (HARN-01):** every `pgtap/*.sql` file is run through `pg_prove`;
  `plan()`/`ok()`/`is()`/`finish()` assertions produce a TAP stream.
- **Expected-output half (HARN-02):** every `regress/sql/*.sql` file is run through
  `psql -X -q -v ON_ERROR_STOP=0`, and its captured output is diffed against the
  matching `regress/expected/*.out` golden file. `ON_ERROR_STOP=0` is deliberate —
  an expected-output test is allowed to provoke an error and assert on the error
  text, which is how exception-code expectations get pinned.

Before either half runs, `lib/pkgname.py --list` validates every discovered file's
`(pg_schema, oracle_package)` pair against `migration/mapping/name-map.csv` — the
Phase 1 SSOT. A file naming a package that isn't a real pair in that CSV aborts the
whole run non-zero (D-P9): nobody invents a package name outside the SSOT.

Exit code is 0 only if every package passed **and at least one test ran**. Zero
tests discovered is treated as a failure — an empty suite silently "passing" is
exactly the failure mode this harness exists to prevent.

### `redgreen.sh --db NAME --install DIR [--package PKG]`

The mechanised form of "red-before, green-after": rebuilds `NAME` from the template
without installing `DIR` and asserts `run-tests.sh` fails (RED), then rebuilds and
installs `DIR` and asserts it passes (GREEN). If the RED phase does **not** fail,
`redgreen.sh` aborts loudly with `RED PHASE DID NOT FAIL` — that is the single most
valuable thing it does, because it catches a test suite that would pass even
against a translation that doesn't exist yet.

## Naming convention (D-P9)

Test files — both `pgtap/*.sql` and `regress/sql/*.sql` (with its matching
`regress/expected/*.out`) — are named:

```
<pg_schema>__<oracle_package_lower>__<topic>.sql
```

`pkgname.py` parses this filename and rejects any file whose `(pg_schema,
oracle_package)` pair is not a real pair in `migration/mapping/name-map.csv`, with
one reserved exception: the literal schema `_canary`, used only for this harness's
own self-tests (never a real Oracle package).

## Design decisions carried from the plan

- **D-P1 — lives under `migration/test/`.** Not under `pg_migration/` (untrusted
  ora2pg output) and not under `tests/` (the pre-existing Java/Testcontainers ORM
  harness — unrelated, must not be disturbed).
- **D-P8 — isolation via template database.** See `bootstrap.sh` above.
- **D-P9 — package identity comes from `migration/mapping/name-map.csv`, never
  re-derived.** See "Naming convention" above.

## The standing rule

**A green suite that was never seen red proves nothing.** This is not a platitude —
it is the literal thing `redgreen.sh` checks by construction, and it is the thing
that was proven by hand for this harness itself in plan 02-01's Task 3 (see
`.planning/phases/02-spec-method-test-harness-pilot/02-01-SUMMARY.md` for the
recorded exit codes and diffs of the two deliberate mutations: a flipped pgTAP
assertion, and a corrupted golden file — both drove the harness to a non-zero exit,
and both were reverted afterward).

Every later plan that adds real translation tests to `pgtap/` and `regress/sql/`
should run `redgreen.sh` against those tests, not just `run-tests.sh` — a run that
only ever sees GREEN cannot tell you whether the test was exercising the
translation at all.

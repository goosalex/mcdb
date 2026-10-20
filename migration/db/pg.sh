#!/usr/bin/env bash
# migration/db/pg.sh -- the PostgreSQL the migration pipeline runs against.
#
# Replaces the former assumption of a local PostgreSQL reached via `sudo -u postgres`.
# Every regeneration and test entry point runs `pg.sh start` before doing anything
# else, and every psql/pg_prove call goes through `pg.sh psql|pg_prove`.
#
#   pg.sh start              build the image if needed, start the container, wait until ready
#   pg.sh psql ARGS...       run psql inside the container as the postgres superuser
#   pg.sh pg_prove ARGS...   run pg_prove inside the container as the postgres superuser
#   pg.sh shell              interactive psql session
#   pg.sh status             print container state
#   pg.sh stop               stop and remove the container (data volume is kept)
#   pg.sh reset              stop and remove the container AND its data volume
#
# Image: PostgreSQL 18.6 + orafce + pgTAP + pg_prove (migration/db/Dockerfile).
#
# File access: the container mounts the mcdb project root, plus the targets of its
# top-level symlinks (ddl/, masterdata/ -> osdb/mcdb), read-only at their HOST paths.
# psql/pg_prove run with the caller's working directory, so absolute paths, relative
# -f paths and psql \ir includes resolve exactly as they did with a local server.
#
# Data lives in a named volume, so mcdb_tmpl and test databases survive restarts.
#
# Environment overrides:
#   MCDB_PG_CONTAINER  container name   (default: mcdb-pg)
#   MCDB_PG_VOLUME     data volume name (default: mcdb-pg-data)
#   MCDB_PG_IMAGE      image tag        (default: mcdb-pg:18.6)
#   http_proxy, https_proxy, no_proxy (and upper-case variants) are forwarded to the
#   image build, which needs to reach deb.debian.org and apt.postgresql.org.
#   MCDB_ARTIFACT_REPO  company|public  which artifact repository to pull the base image
#                      from. Default: auto-detect -- "company" (artifacts.open.ch) when
#                      the mirror answers, "public" (Docker Hub, same digest) otherwise.
#
# Must stay bash 3.2 compatible (macOS /bin/bash).
set -euo pipefail

DB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Project root. When pg.sh is invoked from a git WORKTREE (agents run the harness
# concurrently from .claude/worktrees/*), use the MAIN checkout's root: the mount set is
# part of the container's identity, and a different root per worktree would make every
# `pg.sh start` recreate mcdb-pg with other mounts, killing the sessions of everyone else.
# The worktree itself is still mounted (mount_dirs adds it if it lies outside the root).
WORKTREE_ROOT="$(cd "${DB_DIR}/../.." && pwd)"
MCDB_ROOT="$WORKTREE_ROOT"
if command -v git >/dev/null 2>&1; then
  common_dir="$(cd "$WORKTREE_ROOT" && git rev-parse --git-common-dir 2>/dev/null || true)"
  if [ -n "$common_dir" ]; then
    common_dir="$(cd "$WORKTREE_ROOT" && cd "$common_dir" 2>/dev/null && pwd -P || true)"
    [ -n "$common_dir" ] && [ -d "$(dirname "$common_dir")/migration" ] && MCDB_ROOT="$(dirname "$common_dir")"
  fi
fi

CONTAINER="${MCDB_PG_CONTAINER:-mcdb-pg}"
VOLUME="${MCDB_PG_VOLUME:-mcdb-pg-data}"
IMAGE="${MCDB_PG_IMAGE:-mcdb-pg:18.6}"
READY_TIMEOUT_S=120

die() { echo "pg.sh: $*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker is required but not installed"

dockerfile_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${DB_DIR}/Dockerfile" | cut -d' ' -f1
  else
    shasum -a 256 "${DB_DIR}/Dockerfile" | cut -d' ' -f1
  fi
}

# Physical path of a directory (resolves symlinks).
physical_dir() { (cd "$1" && pwd -P); }

COMPANY_MIRROR="artifacts.open.ch"
COMPANY_DOCKER_PREFIX="${COMPANY_MIRROR}/public-docker-virtual/"

# Which artifact repository is reachable from here: prints "company" or "public".
# Inside the company network artifacts.open.ch answers (any HTTP status counts, the
# probe is reachability only, not product specific); anywhere else the connection fails
# or times out (curl prints 000) and the public upstreams are used.
# MCDB_ARTIFACT_REPO=company|public overrides the probe.
artifact_repo() {
  case "${MCDB_ARTIFACT_REPO:-}" in
    company|public) echo "$MCDB_ARTIFACT_REPO"; return ;;
    "") ;;
    *) die "MCDB_ARTIFACT_REPO must be 'company' or 'public', got '${MCDB_ARTIFACT_REPO}'" ;;
  esac
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://${COMPANY_MIRROR}/" 2>/dev/null || true)"
  if [ -n "$code" ] && [ "$code" != "000" ]; then echo company; else echo public; fi
}

# The base image reference for the given repository. The Dockerfile's ARG default is
# the single source of truth for name + pinned digest; the public form is the same
# reference with the company mirror prefix removed (public-docker-virtual proxies Docker
# Hub, so the digest is identical).
base_image() {
  local company_ref
  company_ref="$(sed -n 's/^ARG BASE_IMAGE=//p' "${DB_DIR}/Dockerfile" | head -1)"
  [ -n "$company_ref" ] || die "no 'ARG BASE_IMAGE=' line in ${DB_DIR}/Dockerfile"
  case "$1" in
    company) echo "$company_ref" ;;
    public)  echo "${company_ref#"$COMPANY_DOCKER_PREFIX"}" ;;
  esac
}

# Directories to mount: the project root plus every top-level symlink target outside
# it. One absolute path per line, sorted, deduplicated.
mount_dirs() {
  {
    physical_dir "$MCDB_ROOT"
    # a worktree outside the main root must be visible too (relative -f paths resolve there)
    case "$(physical_dir "$WORKTREE_ROOT")/" in
      "$(physical_dir "$MCDB_ROOT")"/*) ;;
      *) physical_dir "$WORKTREE_ROOT" ;;
    esac
    local link target
    for link in "$MCDB_ROOT"/*; do
      [ -L "$link" ] && [ -d "$link" ] || continue
      target="$(physical_dir "$link")"
      case "$target/" in
        "$(physical_dir "$MCDB_ROOT")"/*) ;;  # already inside the project mount
        *) echo "$target" ;;
      esac
    done
  } | sort -u
}

container_state() {
  # Some docker versions print "error: no such object" on stdout, so rely on the
  # exit status only and never on the captured text of a failed inspect.
  local state
  if state="$(docker container inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null)"; then
    echo "$state"
  else
    echo "absent"
  fi
}

build_image_if_needed() {
  local want have
  want="$(dockerfile_hash)"
  have="$(docker image inspect -f '{{index .Config.Labels "mcdb.dockerfile-sha256"}}' "$IMAGE" 2>/dev/null || true)"
  [ "$want" = "$have" ] && return 0

  echo "pg.sh: building ${IMAGE} (Dockerfile changed or image missing)" >&2
  local args=() v
  for v in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
    if [ -n "${!v:-}" ]; then args+=(--build-arg "${v}=${!v}"); fi
  done
  local repo base
  repo="$(artifact_repo)"
  base="$(base_image "$repo")"
  echo "pg.sh: artifact repository '${repo}' -> base image ${base}" >&2
  args+=(--build-arg "BASE_IMAGE=${base}")
  docker build -q ${args[@]+"${args[@]}"} \
    --label "mcdb.dockerfile-sha256=${want}" \
    -t "$IMAGE" "$DB_DIR" >/dev/null
}

wait_ready() {
  local waited=0
  # The image's entrypoint runs a temporary init server that only listens on the
  # Unix socket. Checking TCP on 127.0.0.1 waits for the real server.
  until docker exec -u postgres "$CONTAINER" pg_isready -q -h 127.0.0.1 >/dev/null 2>&1; do
    if [ "$(container_state)" != "running" ]; then
      docker logs --tail 30 "$CONTAINER" >&2 || true
      die "container ${CONTAINER} stopped while starting"
    fi
    if [ "$waited" -ge "$READY_TIMEOUT_S" ]; then
      docker logs --tail 30 "$CONTAINER" >&2 || true
      die "PostgreSQL in ${CONTAINER} not ready after ${READY_TIMEOUT_S}s"
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

cmd_start() {
  build_image_if_needed

  local image_id mounts
  image_id="$(docker image inspect -f '{{.Id}}' "$IMAGE")"
  mounts="$(mount_dirs | tr '\n' ':')"

  if [ "$(container_state)" != "absent" ]; then
    local have_image have_mounts
    have_image="$(docker inspect -f '{{.Image}}' "$CONTAINER")"
    have_mounts="$(docker inspect -f '{{index .Config.Labels "mcdb.mounts"}}' "$CONTAINER")"
    if [ "$have_image" != "$image_id" ] || [ "$have_mounts" != "$mounts" ]; then
      echo "pg.sh: recreating ${CONTAINER} (image or mounts changed; data volume kept)" >&2
      docker rm -f "$CONTAINER" >/dev/null
    elif [ "$(container_state)" != "running" ]; then
      docker start "$CONTAINER" >/dev/null
    fi
  fi

  if [ "$(container_state)" = "absent" ]; then
    local run_args=() dir
    while IFS= read -r dir; do
      run_args+=(-v "${dir}:${dir}:ro")
    done < <(mount_dirs)
    docker run -d --name "$CONTAINER" \
      --label "mcdb.mounts=${mounts}" \
      -e POSTGRES_HOST_AUTH_METHOD=trust \
      -v "${VOLUME}:/var/lib/postgresql" \
      --shm-size=256m \
      "${run_args[@]}" \
      "$IMAGE" >/dev/null
  fi

  wait_ready
}

# Run a tool inside the container as postgres, in the caller's working directory when
# that directory is visible in the container. No stdin is attached: callers run these
# inside `while read` loops whose input must not be consumed.
exec_tool() {
  [ "$(container_state)" = "running" ] || die "container ${CONTAINER} is not running -- run 'pg.sh start' first"
  local workdir="/" dir here
  here="$(pwd -P)"
  while IFS= read -r dir; do
    case "$here/" in "$dir"/*) workdir="$here" ;; esac
  done < <(mount_dirs)
  exec docker exec -u postgres -w "$workdir" "$CONTAINER" "$@"
}

case "${1:-}" in
  start)    cmd_start ;;
  psql)     shift; exec_tool psql "$@" ;;
  pg_prove) shift; exec_tool pg_prove "$@" ;;
  shell)    shift; [ "$(container_state)" = "running" ] || cmd_start
            exec docker exec -it -u postgres "$CONTAINER" psql "$@" ;;
  status)   echo "${CONTAINER}: $(container_state)" ;;
  stop)     docker rm -f "$CONTAINER" >/dev/null 2>&1 || true ;;
  reset)    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
            docker volume rm "$VOLUME" >/dev/null 2>&1 || true ;;
  *)        sed -n '2,32p' "${BASH_SOURCE[0]}" >&2; exit 2 ;;
esac



#!/usr/bin/env bash
mkdir -p "/var/mount/pgdata_5431"
docker run  --env="POSTGRES_PASSWORD=password" --env="PGDATA=/var/lib/postgresql/data/pgdata" --env="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" --env="GOSU_VERSION=1.17" --env="LANG=en_US.utf8" --env="PG_MAJOR=16" --env="PG_VERSION=16.9" --env="PG_SHA256=07c00fb824df0a0c295f249f44691b86e3266753b380c96f633c3311e10bd005" --env="DOCKER_PG_LLVM_DEPS=llvm19-dev" \
    --volume="$HOME/var/mount/pgdata_5431:/var/lib/postgresql/data" --volume="/var/lib/postgresql/data" --network="bridge" --workdir="/" -p "5431:5432" --restart="no" --runtime="runc" -d "postgres:16-alpine"


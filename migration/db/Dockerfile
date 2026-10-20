# PostgreSQL 18.6 for the MCDB Oracle -> PostgreSQL migration pipeline.
#
# orafce: Oracle compatibility functions the translations may use (TRAN-01).
# pgTAP + pg_prove: the pgTAP half of the test harness (HARN-01); bootstrap/00_extensions.sql
# creates both extensions and run-tests.sh runs pg_prove.
#
# Built and started by migration/db/pg.sh; nothing else should build this image.
#
# Base image: the company mirror (artifacts.open.ch) by default. Outside the company
# network pg.sh detects that the mirror is unreachable and passes the public Docker Hub
# reference instead -- same image digest, so the result is identical either way.
ARG BASE_IMAGE=artifacts.open.ch/public-docker-virtual/postgres:18.6@sha256:74935e72241653ca55e0414067e6d8763aceb8a810eb51b452253ec3dcfc4336
FROM ${BASE_IMAGE}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        postgresql-18-orafce \
        postgresql-18-pgtap \
        libtap-parser-sourcehandler-pgtap-perl \
    && rm -rf /var/lib/apt/lists/*



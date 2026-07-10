# Fixes the base artifact on ARM64 ! This build will not Start correctly on AMD64/x86!
# see https://artifacts.open.ch/ui/repos/tree/DockerV2Info/public-docker-virtual/gvenzl/oracle-free/23.7/list.manifest.json
FROM artifacts.open.ch/public-docker-virtual/gvenzl/oracle-free:23.7@sha256:90fda7cf4204951665af74eb918872eb6bf66c70bc5b9d8eb45c542a3a8d15fa AS base

USER root
RUN mkdir -p /mcdb && chown -R oracle:oinstall /mcdb
USER oracle

COPY --chown=oracle:oinstall osdb/mcdb/container/docker_orafree_based/shutdown.sh /opt/oracle/
COPY --chown=oracle:oinstall osdb/mcdb/container/docker_orafree_based/test.sh /opt/oracle/
COPY --chown=oracle:oinstall applications/customer-portal/libs/java/core/src/main/sql/ /mcdb/mappingdata/

COPY --chown=oracle:oinstall osdb/mcdb/ddl/ /mcdb/ddl/
COPY --chown=oracle:oinstall osdb/mcdb/masterdata/ /mcdb/masterdata/
COPY --chown=oracle:oinstall osdb/mcdb/changes/ /mcdb/changes/
COPY --chown=oracle:oinstall osdb/mcdb/container/container-entrypoint-initdb.d/ /container-entrypoint-initdb.d/
COPY --chown=oracle:oinstall osdb/mcdb/container/container-entrypoint-startdb.d/ /container-entrypoint-startdb.d/

RUN ORACLE_PASSWORD=password ORACLE_DATABASE=XEPDB1 container-entrypoint.sh --nowait; \
    test.sh && shutdown.sh

EXPOSE 1521

FROM base AS test

RUN echo "TEST TO BE RUN HERE!!!"

FROM test AS final

Prepopulated Docker container based on the Standard Version of Oracle Free 21:
See https://github.com/gvenzl/oci-oracle-free/blob/main/ImageDetails.md if you feel like features were missing 
ARCHIVELOG: NO
FLASHBACK: NO

* For Dev & Production releases of AMD64 / x86 build, use the Kaeter module `ch.open.osdb.mcdb.container:local_ora_mcdb` in this directory.
* To build and release a Dev version of the ARM86 / AppleSilicon build, use the [arm64/Makefile](./arm64/Makefile) `VERSION=2.x.y make build release` to push a new version to  [artifacts.open.ch/central-docker-dev-local/osdb/local_ora_mcdb_arm](https://artifacts.open.ch/ui/repos/tree/General/central-docker-dev-local/osdb/local_ora_mcdb_arm)
* use [nolint] as some scripts are too complicated for the linter to understand.
* Artifact repositories: the Dockerfiles default to the company mirror `artifacts.open.ch` (what the Kaeter build uses). Outside the company network pass `--build-arg BASE_IMAGE=<public reference>` (the value in each Dockerfile's `ARG BASE_IMAGE` line without the `artifacts.open.ch/public-docker-virtual/` prefix, same digest). `110_run_initial_load.sh` probes the mirror at run time and falls back to the public GitHub release URLs for the JDK and Liquibase; `MCDB_ARTIFACT_REPO=company|public` overrides the probe.
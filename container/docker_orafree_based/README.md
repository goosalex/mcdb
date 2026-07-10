Prepopulated Docker container based on the Standard Version of Oracle Free 21:
See https://github.com/gvenzl/oci-oracle-free/blob/main/ImageDetails.md if you feel like features were missing 
ARCHIVELOG: NO
FLASHBACK: NO

* For Dev & Production releases of AMD64 / x86 build, use the Kaeter module `ch.open.osdb.mcdb.container:local_ora_mcdb` in this directory.
* To build and release a Dev version of the ARM86 / AppleSilicon build, use the [arm64/Makefile](./arm64/Makefile) `VERSION=2.x.y make build release` to push a new version to  [artifacts.open.ch/central-docker-dev-local/osdb/local_ora_mcdb_arm](https://artifacts.open.ch/ui/repos/tree/General/central-docker-dev-local/osdb/local_ora_mcdb_arm)
* use [nolint] as some scripts are too complicated for the linter to understand.
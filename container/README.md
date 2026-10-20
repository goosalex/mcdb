# Container DB

Run an MC database in a container running Oracle EE 19c.

## Run the existing Container
Please refer to the [Container DB](https://docs.open.ch/docs/display/DOC/OSDB%3A+DB+Schema+in+Panta#OSDB:DBSchemainPanta-ContainerDBContainerDB) section
of the DB Schema in Panta docs page.

This directory contains files that go into the container that is built by bazel BUILD in the parent directory.

## Additional Features

TCPS is active on port 2484. The self-signed Oracle Wallet location in the container : `/opt/oracle/oradata/dbconfig/EE/.tls-wallet`

There is a very basic GUI under https://localhost:5500/em/ (if you chose to expose the port 5500). Login with ` SYS / password / XEPDB1 `


## Creating a new Container from Scratch
This is a task for the Configuration Team only.

- create new branch from master: `git switch -c update/local_ora_mcdb`

If you want to truncate the changelog and incorporate the current PROD status:
- add a new dummy change to changes/changelog-current.sql with a tag attribute stating the next version (see [versions.yaml](docker_orafree_based/versions.yaml)):
  ```
   --changeset ogl:2000 tag:v2.1.2
   --comment: Base of new container
   SELECT 1 FROM DUAL;
  ```

- run and use the output to update `schemas` in [liquibase-prod.properties](../changes/liquibase-prod.properties):
```sql
select listagg(distinct grantee, ',') within group (order by grantee)
from (select r.grantee
      from dba_role_privs r
      where granted_role in ('MSS_SCHEMA_USER')
        and r.grantee not in ('SYS', 'ASERTO_TEST', 'LQB'));
```
- `cd $PANTA_HOME/osdb/mcdb/changes`
- Make sure PROD DB is uptodate: `liquibase  --defaults-file=liquibase-prod.properties --password=... update`
- `rm ../ddl/generated/schema.oracle.sql`
- `rm ../ddl/generated/users/*.sql`
- run: `scripts/regenerate-ddl.sh --defaults-file=liquibase-prod.properties --password=...`
- run: `scripts/regenerate-csv.sh --defaults-file=liquibase-prod.properties --password=...`
- run: `scripts/exportcsvmeta.sh --defaults-file=liquibase-prod.properties --password=...`
- Commit the changes and create a PR
- Review the changes carefully

Then build the new container:
- `cd $PANTA_HOME/osdb/mcdb/container/docker_orafree_based/arm64`
- build the new container locally: `make build`
- shell into the container: `make run` and check the logs in `/mcdb/output`
- Adapt CHANGELOG.md and versions.yaml and run `kaeter ar`. See [also here](docker_orafree_based/README.md).
- Submit a PR
- Check the created snapshot on OSDP DEV:
```
apiVersion: v1
kind: Pod
metadata:
name: mcdb
labels:
sidecar.istio.io/inject: "false"
spec:
containers:
- name: mcdb1
  #image: artifacts.open.ch/central-docker-prod-local/osdb/local_ora_mcdb:2.0.3
  image: artifacts.open.ch/central-docker-dev-local/osdb/local_ora_mcdb:snapshot
  ports:
  - containerPort: 1521
```
Checks to perform:
  * `liquibase update` works and doesn't run unwanted updates, it runs the unit tests
  * `select max(id) from lqb.DATABASECHANGELOG where filename like 'changelog%.sql'` is consistent with changelog-current.sql
  * `select * from dba_objects where OBJECT_TYPE='PACKAGE' and owner in ('MSS', 'AUTH', 'STOP')` packages are present
  * `select * from dba_objects where OBJECT_TYPE='TRIGGER' and owner in ('MSS', 'AUTH', 'STOP')` triggers are present

- When all is fine, merge the PR into master. This will release the versioned artifact in the PROD repository and a snapshot in DEV.
- Create another PR with the version for all users: `git grep 'osdb/local_ora_mcdb'`
### Release local-DB for Apple Silicon Macs with Arm64
- change to [arm64](./docker_orafree_based/arm64/Makefile) dir and execute: `VERSION=X.Y.Z make build release` to release an ARM64 build with the same version Tag in the DEV repository 
- There will not be any PROD release of ARM64 for the moment.
- The Build runs can take anything between 5 and 15 minutes. We only push to DEV, that's why then can be run on developer machines.

## :2 .. :3 to the rescue
Instead of automatically building snapshots, we trigger only versioned containers. Every new version X.Y.Z will also be tagged with :X.
This way everybody can simply depend on :2, as long as we not increase the major version. Especially the test cases and developers.

Using older containers is still possible by referencing a version tag.

## CHANGELOG

See [CHANGELOG](docker_orafree_based/CHANGELOG.md) 


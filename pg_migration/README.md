# PoC Migration of MCDB to PostgreSQL

## Assumptions
* The Oracle MCDB is already set up and contains the necessary data.
* The PostgreSQL instance is available and configured to accept connections.
* You have the necessary permissions to create databases and schemas in PostgreSQL.
* You have the necessary tools locally installed, such as `Liquibase`, `gsed`, and `psql`.
* The Oracle DB has Flashback enabled, so that the data transfer can be done in a consistent state.
  * Or: No changes are made to the Oracle MCDB during the migration process,
* The migration is done in a single step, meaning that the entire schema and data are transferred at once or at least with no DDL changes in between.
* CDC (Change Data Capture) is not used after this migration process.
* Oracle MCDB continiues to be the source of truth for the MCDB data during and after the migration process.


## Migration Steps
1. Finish all DDL changes in the Oracle MCDB.
   - Ensure that all outstanding changes to the schema are completed and tested in the Oracle environment.
   - Freeze the Liquibase changelog files.
   - Establish the baseline SCN (System Change Number) in Oracle for the migration.: 
     - `SELECT CURRENT_SCN FROM V$DATABASE;` in Oracle.
     - This SCN will be used to ensure that the data transfer is consistent and reflects the state of the database at a specific point in time.
     - 
2. Export the MCDB schema from Oracle via Ora2Pg on a developer machine.
      - Start a Schema Export on Oracle using ../changes/scripts/export_prod_schema.sh 
      - and then ../scripts/changes/regenerate_ddl.sh to regenerate the DDL files in `../ddl/generated`.
      - and then ../changeS/Scripts/migrate-ddl.sh to export the schema and code from Oracle to PostgreSQL compatible code in `../ddl/migrated` .
      - Ensure that the exported schema is compatible with PostgreSQL by running steps 3 & 4 first against a local PostgreSQL instance (example: `run_local_pgsql.sh`).
3. (optional) Create a new PostgreSQL database for the MCDB.
      - use the scripts in preparation/ to create a new database mcdb and necessary common roles for the users
4. Import the exported schema into PostgreSQL.
       - execute the .sh and .sql files in apply/ in alphabetical order. The .sql files are executed by `psql` logging on with the postgres(admin) superuser, the .sh files are executed by bash.
5.  - Container) Transfer only Masterdata: 
   - use ../changes/scripts/regenerate-csv.sh to regenerate the masterdata CSV files from the Oracle MCDB.
   - Apply the masterdata CSV files to the PostgreSQL MCDB using the scripts .... [TODO: specify the scripts here].

6   - Snapshot of Server) Transfer Masterdata together with all data from the Oracle MCDB to the PostgreSQL MCDB.
    - Prepare a K8s namespace connected (egress) to the desired Oracle and PostgreSQL instances.
    - Run k8s/deploy_k8s_dev_datatransfer.sh to deploy the data transfer jobs. 
      This script runs first the parallelized transfers for normal data, master data tables,
      and the most recent entries of the big tables containing CLOBs first
      and then the bulk transfer of older entries of the big tables containing CLOBs.

## Post-Migration Steps

### [simple stress test](load_sim/README.md)
see ## CHANGELOG

See [CHANGELOG](load_sim/CHANGELOG.md).
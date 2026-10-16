This is a Oracle 19c database which we want to convert to PostgreSql 17+
Folder ddl/export is the raw dump of the DDL at the last full export.
Folder ddl/generated is the same, but split and prepared for recreating the DB from scratch
Folder changes contains the liquibase changelog (starting from the latest "tagged" changelog) to apply on top of the export to get the current state
Folder src contains the source for all programmatic elements, e.g. proceduress at the time of last export
Folder masterdata contains the content of the tables that we consider master tables and which we prefill in any new container
Folder ddl/migrated contains the already batch-migrated to Postgresql ddl. This was don with "ora2pg" It might contains errors.
Folder pg_migration contains the naive output of the "ora2pg" conversion of the programmatic elements. It for sure contains errors, ora2pg is not capable of translating the program code. For organization, we chose to put the Oracle package name as a prefix to all elements that were organized in an Oracle package.

Your task is to translate the PL/SQL code into valid Postgres Code so that we can migrate the whole database.   

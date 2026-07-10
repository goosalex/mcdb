--liquibase formatted sql logicalFilePath:pkg/mcdb_checks_consistency.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE MCDB_CHECKS.CONSISTENCY AUTHID DEFINER AS
    PROCEDURE execute_checks_group(
        group_name IN varchar2,
        level_log  IN BOOLEAN DEFAULT false,
        edge_log   IN BOOLEAN DEFAULT true
    );
END CONSISTENCY;
/

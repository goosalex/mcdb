--liquibase formatted sql logicalFilePath:pkgb/mc_monitoring_state.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY mc.monitoring_state IS
    -- body should be empty! This package just provides constants for monitoring.sql.
END monitoring_state;
/

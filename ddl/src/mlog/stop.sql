-------------------------------------------------------------------------------
--
-- create_mat_view_logs.sql: Create materialized view logs for the stop schema
--
-- written by cl@open.ch, December 2007;
-- copyright 2007 Open Systems AG, Switzerland
--
-------------------------------------------------------------------------------

-- needed as we run this as sys
GRANT CREATE TABLE TO stop;

-- materialized view log for the materialized view AUTH.MV_SERVICE_ACCESS
CREATE MATERIALIZED VIEW LOG ON STOP.COMPANY
    LOGGING WITH ROWID (ID, DEFAULT_COMPANY_UNIT_ID)
    INCLUDING NEW VALUES;


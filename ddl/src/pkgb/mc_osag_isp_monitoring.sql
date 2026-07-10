--liquibase formatted sql logicalFilePath:pkgb/mc_osag_isp_monitoring.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
create or replace PACKAGE BODY mc.osag_isp_monitoring IS

-------------------------------------------------------------------------------
-- unixts_to_date
-- Private function
-------------------------------------------------------------------------------
  FUNCTION unixts_to_date(unixts IN PLS_INTEGER) RETURN DATE IS
    /* no longer used */
    /**
     * Converts a UNIX timestamp into an Oracle DATE (timezone is kept)
     * found at http://oracletuts.net/tutorials/how-to-convert-unix-timestamp-to-date-format-in-plsql/
     *
     * Then convert UTC time to DB local system time.
     *  http://blog.watashii.com/2009/11/oracle-timezone-conversions-gmt-to-localtime/
     *  https://forums.oracle.com/forums/thread.jspa?threadID=2428671
     */
    unix_epoch DATE := TO_DATE('19700101000000','YYYYMMDDHH24MISS');
    max_ts PLS_INTEGER := 2145916799; -- 2938-12-31 23:59:59
    min_ts PLS_INTEGER := -2114380800; -- 1903-01-01 00:00:00
    oracle_date DATE; -- assumed to be UTC, provided that unixts is UTC
    oracle_date_local DATE;
  BEGIN
    IF unixts > max_ts THEN
      RAISE_APPLICATION_ERROR(
      -20901,
      'UNIX timestamp too large for 32 bit limit'
        );
    ELSIF unixts < min_ts THEN
      RAISE_APPLICATION_ERROR(
      -20901,
      'UNIX timestamp too small for 32 bit limit' );
    ELSE
      -- convert UNIX TS to Oracle Date (same timezone)
      oracle_date := unix_epoch + NUMTODSINTERVAL(unixts, 'SECOND');
    END IF;

    -- convert timezone (from GMT to Local)
    oracle_date_local := CAST(
    FROM_TZ( oracle_date, 'UTC')
      AT LOCAL
      AS DATE );

    RETURN (oracle_date_local);
  END unixts_to_date;


-------------------------------------------------------------------------------
-- update_isp_link_status:
-- !! wrapper procedure; used for a smooth transition !!
-- * updates the isp_link and isp_link_history tables
-- * does a sanity check with p_revious_status
-------------------------------------------------------------------------------
  PROCEDURE update_isp_link_status
  (
    p_isp_link_id      mc.isp_link_history.isp_link_id%type,
    p_status           mc.isp_link_status_type.id%type,
    p_previous_status  mc.isp_link_status_type.id%type,
    p_change_timestamp PLS_INTEGER,
    p_reported_by      mc.isp_link_history.reporting_host_id%type
  ) IS


  BEGIN
    plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
    update_isp_link_status2( p_isp_link_id,
                             p_status,
                             p_previous_status,
                             p_reported_by );

  END update_isp_link_status;

-------------------------------------------------------------------------------
-- update_isp_link_status2:
-- * updates the isp_link and isp_link_history tables
-- * does a sanity check with p_previous_status
-------------------------------------------------------------------------------
  PROCEDURE update_isp_link_status2
  (
    p_isp_link_id      mc.isp_link_history.isp_link_id%type,
    p_status           mc.isp_link_status_type.id%type,
    p_previous_status  mc.isp_link_status_type.id%type,
    p_reported_by      mc.isp_link_history.reporting_host_id%type
  ) IS

    v_previous_status mc.isp_link_status_type.id%type;
    v_change_date     mc.isp_link_history.change_date%type;
    v_event_id        mc.isp_link_history.event_id%type;
    v_isp_count       number;

  BEGIN
    plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
    SELECT count(*) INTO v_isp_count
    FROM mss.isp_link
    WHERE id = p_isp_link_id;

    IF ( v_isp_count > 0 ) THEN
      SELECT new_isp_link_status_type_id
      INTO v_previous_status
      FROM mc.isp_link_history
      WHERE isp_link_id = p_isp_link_id
      ORDER BY change_date DESC
      FETCH FIRST 1 ROW ONLY;

      -- if above SELECT statement fails, we continue in the EXCEPTION section.

      v_event_id := NULL;  -- will be set by linkmon-coordinator

      IF ( v_previous_status IS NULL ) THEN
        v_previous_status := 1; --default to "UNKNOWN"
      END IF;

      -- need to insert into history and update status
      -- check that state has changed
      -- ( this function should be idempotent )
      IF ( v_previous_status != p_status ) THEN

        -- check that previous status matches
        IF ( v_previous_status != p_previous_status
          AND p_previous_status != 0
          AND p_previous_status != 1 ) THEN
          -- we always write the old status from the db (v_previous_status)
          -- to keep the db history consistent.
          -- p_previous_status can be unknown or off if OSAGtlapps is updated on a Gumaserver
          plog.warning('UNEXPECTED ISP status reported as previous status: ' ||p_previous_status
            ||'. The stored status for ISP '||p_isp_link_id||' in the db is: '||v_previous_status
            ||'. Will write change from status '||v_previous_status
            ||' to '||p_status||'.');
        END IF;

        -- insert history entry
        INSERT INTO mc.isp_link_history (
          id,
          isp_link_id,
          reporting_host_id,
          old_isp_link_status_type_id,
          new_isp_link_status_type_id,
          change_date,
          event_id)
        VALUES (isp_link_history_seq.nextval,
                p_isp_link_id,
                p_reported_by,
                v_previous_status,
                p_status,
                SYSDATE,
                v_event_id);

      END IF;

      -- update status unconditionally
      UPDATE mss.isp_link
      SET mss.isp_link.isp_link_status_type_id = p_status
      WHERE mss.isp_link.id                      = p_isp_link_id;

    END IF;

  EXCEPTION
    WHEN no_data_found THEN
      -- first entry: nothing to compare, just update

      -- insert history entry
      INSERT INTO mc.isp_link_history (
        id,
        isp_link_id,
        reporting_host_id,
        old_isp_link_status_type_id,
        new_isp_link_status_type_id,
        change_date,
        event_id)
      VALUES (isp_link_history_seq.nextval,
              p_isp_link_id,
              p_reported_by,
              v_previous_status,
              p_status,
              SYSDATE,
              v_event_id);

      -- update status
      UPDATE mss.isp_link
      SET isp_link_status_type_id = p_status
      WHERE id                      = p_isp_link_id;

  END update_isp_link_status2;

-------------------------------------------------------------------------------
-- update_capacity_measurements
-- * updates the mss.isp_link table with the newest link capacity measurements
-------------------------------------------------------------------------------
  PROCEDURE update_capacity_measurements
  (
    p_isp_link_id      mss.isp_link.id%type,
    p_download         mss.isp_link.measured_download%type,
    p_upload           mss.isp_link.measured_upload%type,
    p_interface_id     mss.isp_link.usage_interface_id%type
  ) IS
    v_interface_count  number;

  BEGIN
    plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
    SELECT count(*) INTO v_interface_count
    FROM mss.interface
    WHERE id = p_interface_id;

    IF ( v_interface_count > 0 ) THEN

      UPDATE mss.isp_link
      SET measured_download  = p_download,
          measured_upload    = p_upload,
          usage_interface_id = p_interface_id
      WHERE id                 = p_isp_link_id;

    END IF;

  EXCEPTION WHEN OTHERS THEN

    plog.err('mc.osag_isp_monitoring.update_capacity_measurements: Failed to update link ' || p_isp_link_id || ' using interface ' ||
             p_interface_id || '. Error: ' || sqlerrm);

  END update_capacity_measurements;

END osag_isp_monitoring;
/

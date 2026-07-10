--liquibase formatted sql logicalFilePath:pkgb/mc_connectivity_coordinator.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY MC.CONNECTIVITY_COORDINATOR AS



-------------------------------------------------------------------------------
-- end_interrupt_prod: read data from connection_interrupt_open,
-- insert a new entry in table connection_interrupt_closed,
-- delete the read entry from table connection_interrupt_open.
--
-- parameter:  p_host_id
--             p_up_date
-- returns:    event_id of generated event (if any) or NULL
-------------------------------------------------------------------------------
    PROCEDURE end_interrupt_prod(
        p_host_id    mss.host.id%TYPE,
        p_up_date    mc.connection_interrupt_closed.up_date%TYPE
    ) IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'end_interrupt(): ';
        row_interrupt  mc.connection_interrupt_open%ROWTYPE;

    BEGIN

        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);

        SELECT * INTO row_interrupt
        FROM connection_interrupt_open 
        WHERE host_id = p_host_id
            FOR UPDATE;

        -- insert the record into the connection_interrupt_closed table
        INSERT INTO connection_interrupt_closed (id, down_date, up_date,
                                                 type_id, minutes, details, event_id, host_id, active,
                                                 interrupt_review_status_id)
        VALUES (row_interrupt.id, row_interrupt.down_date, p_up_date, row_interrupt.type_id,
                round((p_up_date - row_interrupt.down_date) * 24*60), row_interrupt.details,
                row_interrupt.event_id, p_host_id, row_interrupt.active, row_interrupt.interrupt_review_status_id);

      
        -- delete the record from the connection_interrupt_open table
        DELETE FROM connection_interrupt_open
        WHERE id = row_interrupt.id;
        RETURN;

    --EXCEPTION
        --plog.err(S_PREFIX||'caught exception:'||sqlerrm);


    END end_interrupt_prod;


    
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- sync_interrupt: insert a new entry in table connection_interrupt_open
--
-- parameter:  p_host_id
--             p_interrupt_type 
--             p_details
--             p_date
-------------------------------------------------------------------------------
    PROCEDURE sync_interrupt_prod(
        p_host_id             mss.host.id%TYPE,
        p_interrupt_type      mc.connection_interrupt_open.type_id%TYPE,
        p_details             mc.connection_interrupt_open.details%TYPE,
        p_timestamp                mc.HOST_CONNECTION_STATUS.con_timestamp%TYPE
    ) IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'sync_interrupt(): ';
        v_closed_count NUMBER;
        v_open_count NUMBER;
        v_interrupt_type_old mc.connection_interrupt_open.type_id%TYPE;
        v_interrupt_type_hostconnectionstatus mc.connection_interrupt_open.type_id%TYPE;
        v_interrupt_type_new mc.connection_interrupt_open.type_id%TYPE;
        v_active         mc.connection_interrupt_open.active%TYPE  := 1;

        p_date mc.connection_interrupt_open.down_date%TYPE;
        row_interrupt  mc.connection_interrupt_open%ROWTYPE;


    BEGIN
      plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);

		 SELECT CAST( from_tz( timestamp  '1970-01-01 00:00:00' + numtodsinterval( p_timestamp,'second' ), 'UTC' ) AT time ZONE 'Europe/Zurich' AS DATE )  INTO p_date from dual;

      -- SRE-528: Interrupt 4 is maintenance window and UP. In that case, host connection status should be up (NULL)
      IF ( p_interrupt_type = 4 ) THEN
        v_interrupt_type_hostconnectionstatus := NULL;
      ELSE
        v_interrupt_type_hostconnectionstatus := p_interrupt_type;
      END IF;

      MERGE INTO MC.HOST_CONNECTION_STATUS HCS USING dual ON ( HOST_ID = p_host_id )
        WHEN MATCHED THEN UPDATE SET 
            HCS.CON_TIMESTAMP=p_timestamp,  
            HCS.DETAILS= p_details , 
            HCS.CON_INT_TYPE_ID= v_interrupt_type_hostconnectionstatus 
        WHEN NOT MATCHED THEN INSERT (HOST_ID, CON_TIMESTAMP, DETAILS, CON_INT_TYPE_ID) 
        VALUES ( p_host_id, p_timestamp, p_details, v_interrupt_type_hostconnectionstatus );

       -- Check if there is already an open interrupt
        SELECT COUNT(*), MAX(type_id)
        INTO v_open_count, v_interrupt_type_old
        FROM connection_interrupt_open
        WHERE host_id = p_host_id;

        -- Check if there is already a closed interrupt
        SELECT COUNT(*)
        INTO v_closed_count
        FROM connection_interrupt_closed
        WHERE host_id = p_host_id;

        SELECT active INTO v_active FROM mss.HOST h WHERE id = p_host_id;

        IF ( v_active = 0 ) THEN
            v_interrupt_type_new := 0; -- If the host is inactive, the interrupt is always of type "Unknown". Otherwise it will appear in the SLA reports
        ELSE
       		v_interrupt_type_new := p_interrupt_type;
        END IF;

        IF ( v_closed_count < 1 ) THEN
            -- First interrupt. Insert a dummy entry in connection_interrupt_closed
            INSERT INTO connection_interrupt_closed (id, up_date, details, host_id, active)
                        VALUES (connection_interrupt_sequence.nextval, p_date, 'service activation', p_host_id, v_active);
        END IF;


        -- Select from open interrupt
        -- If there is already an open interrupt and the interrupt_type is different, start by closing it
        -- If the interrupt_type is the same, idempotency => returns
        -- If there is currently no open interrupt, just proceed

        -- If p_interrupt_type is null (no interrupt) then we must attempt to close the interrupt if there's one open
        IF ( v_interrupt_type_new IS NULL ) THEN 

            IF ( v_open_count > 0 ) THEN

                end_interrupt_prod( p_host_id, p_date );
               
            END IF;
            
            -- We want to close the interrupt, but there's no open interrupt. => Do nothing
        ELSE

            -- Opened interrupt has not changed type
            IF ( v_interrupt_type_old = v_interrupt_type_new ) THEN
                RETURN;
            END IF;
            
            IF ( v_open_count > 0 ) THEN -- If an interrupt is already opened, close it
                end_interrupt_prod( p_host_id, p_date );
            END IF;

            INSERT INTO connection_interrupt_open (
                id, 
                down_date,
                type_id, 
                details, 
                host_id, 
                event_id, 
                active
            ) VALUES (connection_interrupt_sequence.nextval, p_date, v_interrupt_type_new, p_details, p_host_id, NULL, v_active);

        END IF;
    END sync_interrupt_prod;







-------------------------------------------------------------------------------
-- get_state: returns STATE_ value for given SANG_ and MODE_ values
--
-- parameter: p_mode, a MODE_ value
--            p_sang, a SANG_ value
--
-- returns: STATE_ value
--          ( there are only states for ACTIVE and SW modes )
-------------------------------------------------------------------------------
    FUNCTION get_state(
        p_mode     NUMBER,
        p_sang     NUMBER
    ) RETURN NUMBER IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'get_state(): ';
        v_result NUMBER;

    BEGIN
        IF ( p_mode = mc.monitoring_state.MODE_ACTIVE ) THEN
            RETURN p_sang;
        ELSE
            IF ( p_sang = 1 ) THEN
                RETURN mc.monitoring_state.STATE_ISP_SW;
            ELSE
                RETURN mc.monitoring_state.STATE_DOWN_SW;
            END IF;
        END IF;

    END get_state;
  

-------------------------------------------------------------------------------
-- update_isp_link_status_w_date:
-- * updates the isp_link and isp_link_history tables
-- * does a sanity check with p_previous_status
-------------------------------------------------------------------------------
  PROCEDURE update_isp_link_status_w_date
  (
    p_isp_link_id      mc.isp_link_history.isp_link_id%type,
    p_status           mc.isp_link_status_type.id%type,
    p_previous_status  mc.isp_link_status_type.id%type,
    p_reported_by      mc.isp_link_history.reporting_host_id%type,
    on_date            mc.isp_link_history.change_date%type
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
      ORDER BY id DESC
      FETCH FIRST 1 ROW ONLY;

      -- if above SELECT statement fails, we continue in the EXCEPTION section.

      v_event_id := NULL;  

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
          plog.warning('[TLDR; ESCALATE TO #sre-team] UNEXPECTED ISP status reported as previous status: ' ||p_previous_status
            ||'. The stored status for ISP '||p_isp_link_id||' in the db is: '||v_previous_status
            ||'. Will write change from status '||v_previous_status
            ||' to '||p_status||'. Please kindly escalate this to #sre-team for investigation');
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
                on_date,
                v_event_id);

      
      END IF;

      -- update status unconditionally
      UPDATE mss.isp_link
      SET mss.isp_link.ISP_LINK_STATUS_TYPE_ID     = p_status
      WHERE mss.isp_link.id                        = p_isp_link_id;
    END IF;

  EXCEPTION
    WHEN no_data_found THEN
      -- first entry: nothing to compare, just update
      v_previous_status := 1; -- default to "UNKNOWN" when there is no prior history row

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
              on_date,
              v_event_id);

      -- update status
      UPDATE mss.isp_link
      SET ISP_LINK_STATUS_TYPE_ID   = p_status
      WHERE id                      = p_isp_link_id;

  END update_isp_link_status_w_date;




-------------------------------------------------------------------------------
-- update_isp_link_status:
-- * calls update_isp_link_status_w_date with SYSDATE
-------------------------------------------------------------------------------
  PROCEDURE update_isp_link_status
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

    update_isp_link_status_w_date(
      p_isp_link_id,
      p_status,
      p_previous_status,
      p_reported_by,
      SYSDATE
    );
  END update_isp_link_status;



-------------------------------------------------------------------------------
-- sync_isp_link_status:
-- * updates the isp_link and isp_link_history tables
-- * does a sanity check with p_previous_status
-- * TEMPORARY PROCEDURE BY #sre-team to evaluate SANG Linkmonc replacement
-------------------------------------------------------------------------------
  PROCEDURE sync_isp_link_status
  (
    p_isp_link_id      mc.isp_link_history.isp_link_id%type,
    p_status           mc.isp_link_status_type.id%type
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
      SELECT ISP_LINK_STATUS_TYPE_ID
      INTO v_previous_status
      FROM mss.isp_link
      WHERE id = p_isp_link_id;

      -- if above SELECT statement fails, we continue in the EXCEPTION section.

      v_event_id := NULL;  -- will be set by linkmon-coordinator

      IF ( v_previous_status IS NULL ) THEN
        v_previous_status := 1; --default to "UNKNOWN"
      END IF;

      -- need to insert into history and update status
      -- check that state has changed
      -- ( this function should be idempotent )
      IF ( v_previous_status != p_status ) THEN

        -- insert history entry
        INSERT INTO mc.isp_link_history (
          id,
          isp_link_id,
          old_isp_link_status_type_id,
          new_isp_link_status_type_id,
          change_date,
          event_id)
        VALUES (isp_link_history_seq.nextval,
                p_isp_link_id,
                v_previous_status,
                p_status,
                SYSDATE,
                v_event_id);

      END IF;


    -- update status
    UPDATE mss.isp_link
    SET mss.isp_link.ISP_LINK_STATUS_TYPE_ID     = p_status
    WHERE mss.isp_link.id                        = p_isp_link_id;

    END IF;

  EXCEPTION
    WHEN no_data_found THEN
      -- first entry: nothing to compare, just update
      v_previous_status := 1; -- default to "UNKNOWN" when the link row cannot provide a current status

      -- insert history entry
      INSERT INTO mc.isp_link_history (
        id,
        isp_link_id,
        old_isp_link_status_type_id,
        new_isp_link_status_type_id,
        change_date,
        event_id)
      VALUES (isp_link_history_seq.nextval,
              p_isp_link_id,
              v_previous_status,
              p_status,
              SYSDATE,
              v_event_id);

      -- update status
      UPDATE MSS.ISP_LINK
      SET ISP_LINK_STATUS_TYPE_ID   = p_status
      WHERE id                      = p_isp_link_id;

  END sync_isp_link_status;

END CONNECTIVITY_COORDINATOR;
    --
/

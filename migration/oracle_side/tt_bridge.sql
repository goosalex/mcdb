--liquibase formatted sql logicalFilePath:oracle_side/tt_bridge.sql
--changeset phoenix:tt_bridge_config runOnChange:true endDelimiter:/ splitStatements:true
-- =====================================================================================
-- TT.BRIDGE -- Oracle-side half of the synchronous HTTPS bridge to the PostgreSQL
-- ticketing database. See migration/oracle_side/README.md ("Bridge contract").
--
-- UNTESTED DRAFT: no Oracle instance is available to this project. Written to Oracle
-- 19c syntax (JSON_OBJECT / JSON_VALUE are 12.2+, UTL_HTTP with a wallet for TLS).
--
-- Prerequisites on the Oracle side (DBA, once):
--   * network ACL:  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE for the bridge host/port
--   * wallet:       UTL_HTTP.SET_WALLET('file:/opt/oracle/.../wallet', NULL) if HTTPS
--   * one row in TT.BRIDGE_CONFIG (base_url, bearer token, timeout)
-- =====================================================================================
CREATE TABLE tt.bridge_config (
    id           NUMBER        DEFAULT 1 NOT NULL,
    base_url     VARCHAR2(512) NOT NULL,   -- e.g. https://tt-bridge.mc.open.ch
    bearer_token VARCHAR2(512) NOT NULL,
    timeout_sec  NUMBER        DEFAULT 10 NOT NULL,
    wallet_path  VARCHAR2(512),            -- 'file:/...' or NULL for plain http (dev only)
    CONSTRAINT bridge_config_pk PRIMARY KEY (id),
    CONSTRAINT bridge_config_single CHECK (id = 1)
)
/

--changeset phoenix:tt_bridge_pkg runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE tt.bridge AS
    /* Calls PostgreSQL routine p_routine (already in package_in_name form, e.g.
     * 'tt.event_interface_newevent_new') with the named arguments in p_args_json
     * (a JSON object). Returns the JSON object of OUT parameters ('{}' when none).
     * Raises the mapped Oracle error when PostgreSQL raised one (see raise_mapped). */
    FUNCTION call_remote(p_routine VARCHAR2, p_args_json CLOB) RETURN CLOB;

    /* Maps a PostgreSQL SQLSTATE + message back to the Oracle error the caller expects:
     *   P0002 -> NO_DATA_FOUND         P0003 -> TOO_MANY_ROWS
     *   OS980 -> -20980 (ticket_closed, TT.EVENT_INTERFACE_STATE)
     *   OSnnn -> -20nnn                 anything else -> -20999 with the message.
     * The OS-class convention is documented in migration/mapping/sqlstate-map.md. */
    PROCEDURE raise_mapped(p_sqlstate VARCHAR2, p_message VARCHAR2);

    /* Helpers used by the stub packages to build argument objects. */
    FUNCTION j_bool(p BOOLEAN) RETURN VARCHAR2;                  -- 'true' / 'false' / NULL
    FUNCTION j_date(p DATE) RETURN VARCHAR2;                     -- ISO-8601, Europe/Zurich
END bridge;
/

CREATE OR REPLACE PACKAGE BODY tt.bridge AS

    FUNCTION j_bool(p BOOLEAN) RETURN VARCHAR2 IS
    BEGIN
        RETURN CASE WHEN p IS NULL THEN NULL WHEN p THEN 'true' ELSE 'false' END;
    END;

    FUNCTION j_date(p DATE) RETURN VARCHAR2 IS
    BEGIN
        RETURN CASE WHEN p IS NULL THEN NULL
               ELSE TO_CHAR(FROM_TZ(CAST(p AS TIMESTAMP), 'Europe/Zurich'), 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM') END;
    END;

    PROCEDURE raise_mapped(p_sqlstate VARCHAR2, p_message VARCHAR2) IS
        v_code NUMBER;
    BEGIN
        IF p_sqlstate = 'P0002' THEN
            RAISE NO_DATA_FOUND;
        ELSIF p_sqlstate = 'P0003' THEN
            RAISE TOO_MANY_ROWS;
        ELSIF REGEXP_LIKE(p_sqlstate, '^OS[0-9]{3}$') THEN
            v_code := -20000 - TO_NUMBER(SUBSTR(p_sqlstate, 3));   -- OS980 -> -20980
            RAISE_APPLICATION_ERROR(v_code, p_message);
        ELSE
            RAISE_APPLICATION_ERROR(-20999, 'tt.bridge: PostgreSQL error ' || p_sqlstate || ': ' || p_message);
        END IF;
    END;

    FUNCTION call_remote(p_routine VARCHAR2, p_args_json CLOB) RETURN CLOB IS
        c_prefix  CONSTANT VARCHAR2(64) := 'TT.BRIDGE.call_remote(): ';
        v_cfg     tt.bridge_config%ROWTYPE;
        v_req     UTL_HTTP.req;
        v_resp    UTL_HTTP.resp;
        v_body    CLOB := '{"args":' || NVL(p_args_json, '{}') || '}';
        v_out     CLOB := EMPTY_CLOB();
        v_chunk   VARCHAR2(32767);
        v_status  PLS_INTEGER;
    BEGIN
        SELECT * INTO v_cfg FROM tt.bridge_config WHERE id = 1;
        IF v_cfg.wallet_path IS NOT NULL THEN
            UTL_HTTP.SET_WALLET(v_cfg.wallet_path, NULL);
        END IF;
        UTL_HTTP.SET_TRANSFER_TIMEOUT(v_cfg.timeout_sec);
        UTL_HTTP.SET_BODY_CHARSET('UTF-8');

        plog.debug(c_prefix || p_routine || ' ' || SUBSTR(p_args_json, 1, 200));

        v_req := UTL_HTTP.BEGIN_REQUEST(v_cfg.base_url || '/call/' || p_routine, 'POST', 'HTTP/1.1');
        UTL_HTTP.SET_HEADER(v_req, 'Authorization', 'Bearer ' || v_cfg.bearer_token);
        UTL_HTTP.SET_HEADER(v_req, 'Content-Type', 'application/json; charset=utf-8');
        UTL_HTTP.SET_HEADER(v_req, 'Content-Length', LENGTHB(v_body));
        UTL_HTTP.WRITE_TEXT(v_req, v_body);

        v_resp := UTL_HTTP.GET_RESPONSE(v_req);
        v_status := v_resp.status_code;
        DBMS_LOB.CREATETEMPORARY(v_out, TRUE);
        BEGIN
            LOOP
                UTL_HTTP.READ_TEXT(v_resp, v_chunk, 32767);
                DBMS_LOB.WRITEAPPEND(v_out, LENGTH(v_chunk), v_chunk);
            END LOOP;
        EXCEPTION
            WHEN UTL_HTTP.END_OF_BODY THEN NULL;
        END;
        UTL_HTTP.END_RESPONSE(v_resp);

        IF v_status = 200 THEN
            RETURN NVL(JSON_QUERY(v_out, '$.out' RETURNING CLOB), '{}');
        END IF;

        plog.err(c_prefix || p_routine || ' failed: HTTP ' || v_status || ' ' || SUBSTR(v_out, 1, 500));
        raise_mapped(JSON_VALUE(v_out, '$.sqlstate'), JSON_VALUE(v_out, '$.message' RETURNING VARCHAR2(4000)));
        RETURN NULL; -- not reached
    EXCEPTION
        WHEN UTL_HTTP.TRANSFER_TIMEOUT OR UTL_HTTP.REQUEST_FAILED THEN
            plog.err(c_prefix || p_routine || ' transport failure: ' || SQLERRM);
            RAISE_APPLICATION_ERROR(-20998, 'tt.bridge: PostgreSQL ticketing unreachable: ' || SQLERRM);
    END;
END bridge;
/

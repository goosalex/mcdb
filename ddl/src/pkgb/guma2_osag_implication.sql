--liquibase formatted sql logicalFilePath:pkgb/guma2_osag_implication.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY GUMA2.OSAG_IMPLICATION IS

-- ----------------------------------------------------------------------------------------
-- package constants
-- ----------------------------------------------------------------------------------------
    C_GUMA_UNKNOWN_ID      CONSTANT NUMBER := 5333;
    E_ABORT                EXCEPTION;

-- ----------------------------------------------------------------------------------------
-- PROCEDURE get_next_token: Extracts the next token up to the delimiter (i_delim) or the
--           end of the string if none remain. Returns the token and the remaining substr
--           after the token.
-- ----------------------------------------------------------------------------------------
    PROCEDURE get_next_token(
        i_delim      IN VARCHAR2,
        i_string     IN VARCHAR2,
        o_token      OUT VARCHAR2,
        o_rest       OUT VARCHAR2
    ) IS
        C_PREFIX      CONSTANT VARCHAR2(64) := 'OSAG_IMPLICATION.get_next_token(): ';
        l_pos         NUMBER;

    BEGIN
        o_token := NULL;
        o_rest := NULL;

        -- Empty string handling
        IF (LENGTH(i_string) = 0) THEN
            RETURN;
        END IF;

        l_pos := INSTR(i_string, i_delim, 1, 1);

        -- Last token in string
        IF (l_pos = 0) THEN
            o_token := i_string;
            RETURN;
        END IF;

        IF (l_pos != 1) THEN
            o_token := substr(i_string, 0, l_pos - 1);
        END IF;

        IF ((l_pos + LENGTH(i_delim)) <= LENGTH(i_string)) THEN
            o_rest := substr(i_string, l_pos + length(i_delim));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(C_PREFIX||'unexpected error 99: '||sqlerrm);
            RAISE;

    END get_next_token;

-- ----------------------------------------------------------------------------------------
-- PROCEDURE auth_update: Processes AUTH:UPDATE messages
-- ----------------------------------------------------------------------------------------
    PROCEDURE auth_update(
        i_logdate       IN syslog_message.log_date%TYPE,
        i_data          IN syslog_message.message%TYPE
    ) IS
        C_PREFIX                CONSTANT VARCHAR2(64) := 'OSAG_IMPLICATION.auth_update(): ';
        E_ABORT                 EXCEPTION;                 -- abort this procedure

        l_msg_type              VARCHAR(128);
        l_update_string         VARCHAR2(512);
        l_id                    NUMBER;
        l_result                VARCHAR(64);
        l_token_id              NUMBER;
        l_replacementtoken_id   NUMBER;
        l_locked                NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);

        -- Cut the tag
        get_next_token('AUTH:UPDATE2 ', i_data, l_msg_type, l_update_string);

        -- Determine the type of update message
        get_next_token(' ', l_update_string, l_msg_type, l_update_string);

        plog.debug(C_PREFIX||'authentication update message type '''||l_msg_type||'''');

        get_next_token(':', l_update_string, l_id, l_update_string);

        IF (l_id IS NULL) THEN
            plog.err(C_PREFIX||'malformed authentication update message: no object ID present: '''||i_data||'''');
            RAISE E_ABORT;
        END IF;

        IF (l_msg_type = 'LOGIN') THEN
            plog.debug(C_PREFIX||'Authentication update LOGIN ID '||l_id||': '''||l_update_string||'''');

            -- Authentication result
            get_next_token(':', l_update_string, l_result, l_update_string);

            plog.debug(C_PREFIX||'Authentication result: '||l_result||'''');

            -- token the remaining parameters
            get_next_token(':', l_update_string, l_locked, l_update_string);
            get_next_token(':', l_update_string, l_token_id, l_update_string);
            get_next_token(':', l_update_string, l_replacementtoken_id, l_update_string);

            IF (l_result = 'ACCEPT') THEN
                osag_auth_passport.update_login_details2(l_id, i_logdate, NULL, NULL, l_token_id, l_replacementtoken_id);
            ELSIF (l_result = 'REJECT') THEN
                osag_auth_passport.update_login_details2(l_id, NULL, i_logdate, l_locked, l_token_id, l_replacementtoken_id);
            ELSE
                plog.err(C_PREFIX||'unknown authentication result: '''||l_result||'''');
                RAISE E_ABORT;
            END IF;
        ELSIF (l_msg_type = 'TOKEN') THEN
            plog.debug(C_PREFIX||'Authentication update TOKEN ID '||l_id||': '''||l_update_string||'''');

            osag_auth_passport.update_token_details2(l_id, l_update_string);
        END IF;

    EXCEPTION
        WHEN E_ABORT THEN
            NULL;
        WHEN OTHERS THEN
            plog.err(C_PREFIX||'unexpected error 99: '||sqlerrm||', GUMA msg: '''||i_data||'''');
            RAISE;
    END auth_update;

END OSAG_IMPLICATION;
/

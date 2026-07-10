--liquibase formatted sql logicalFilePath:pkgb/esp_osag_duty.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY ESP.OSAG_DUTY IS

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

    FUNCTION get_next_swiss_business_day(p_date TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP) RETURN TIMESTAMP WITH TIME ZONE AS

        c_prefix CONSTANT VARCHAR2(64)  := 'OSAG_DUTY.get_next_swiss_business_day(): ';

        v_business_day TIMESTAMP WITH TIME ZONE;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        IF (TO_CHAR(p_date AT TIME ZONE 'Europe/Zurich','HH24') < 8) THEN
            v_business_day := FROM_TZ(to_timestamp(trunc(p_date)), TZ_OFFSET('Europe/Zurich')) + INTERVAL '8' HOUR + INTERVAL '30' MINUTE;
        ELSE
            v_business_day := FROM_TZ(to_timestamp(trunc(p_date)), TZ_OFFSET('Europe/Zurich')) + INTERVAL '1' DAY + INTERVAL '8' HOUR + INTERVAL '30' MINUTE;
        END IF;

        -- business hours are not on Sunday, Saturday, or a Holiday
        WHILE (TO_CHAR(v_business_day AT TIME ZONE 'Europe/Zurich','D') IN (1,7) OR is_legal_holiday(v_business_day) = 1) LOOP
                v_business_day := v_business_day + INTERVAL '1' DAY;
            END LOOP;

        RETURN v_business_day;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix || 'caught exception: '||sqlerrm);
            RETURN p_date AT TIME ZONE 'Europe/Zurich';
    END get_next_swiss_business_day;

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

    FUNCTION is_legal_holiday(p_date TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP) RETURN NUMBER AS

        c_prefix  CONSTANT VARCHAR2(64) := 'OSAG_DUTY.is_legal_holiday(): ';

        v_legal_holiday ESP.SPECIAL_DAY.LEGAL_HOLIDAY%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- check whether we are on a legal holiday
        SELECT COUNT(*) INTO v_legal_holiday
        FROM esp.special_day sd
        WHERE p_date - sd.day_date < NUMTODSINTERVAL(1, 'day')
          AND p_date - sd.day_date >= NUMTODSINTERVAL(0, 'day')
          AND sd.legal_holiday = 1;

        IF (v_legal_holiday > 0) THEN
            RETURN 1;
        ELSE
            RETURN 0;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix || 'caught exception: '||sqlerrm);
            RETURN 0;

    END is_legal_holiday;

END OSAG_DUTY;
/

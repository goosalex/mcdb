--liquibase formatted sql logicalFilePath:pkgb/getnodes_osag_getnodes.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY GETNODES.OSAG_GETNODES IS
--------------------------------------------------------------------------------
-- FUNCTION get_tams_by_company_id
--
-- REMARK: using a CURSOR and a LOOP is slightly faster than using WM_CONCAT
--------------------------------------------------------------------------------
    FUNCTION get_tams_by_company_id(p_company_id NUMBER)
        RETURN VARCHAR2 IS
        c_prefix    CONSTANT VARCHAR2(64)  := 'OSAG_GETNODES.get_tams_by_company_id(): ';

        v_res       VARCHAR2(4000) := NULL;

        CURSOR tams IS
            SELECT stop.contact.short
            FROM stop.contact
                     JOIN stop.company_tam ON (stop.contact.id=stop.company_tam.contact_id)
                     JOIN stop.company     ON (stop.company_tam.company_id = stop.company.id)
            WHERE stop.company.id = p_company_id
            ORDER BY stop.company_tam.priority ASC;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        FOR tam IN tams LOOP
                IF ( v_res IS NULL ) THEN
                    v_res := tam.short;
                ELSE
                    v_res := v_res||','||tam.short;
                END IF;

            END LOOP;

        RETURN v_res;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix||'unexpected exception: '||sqlerrm);
            RETURN v_res;
    END get_tams_by_company_id;

--------------------------------------------------------------------------------
-- FUNCTION get_ams_by_company_id:
--------------------------------------------------------------------------------
    FUNCTION get_ams_by_company_id(p_company_id NUMBER)
        RETURN VARCHAR2 IS
        c_prefix    CONSTANT VARCHAR2(64)  := 'OSAG_GETNODES.get_ams_by_company_id(): ';

        v_res       VARCHAR2(4000) := NULL;

        CURSOR ams IS
            SELECT stop.contact.short
            FROM stop.contact
                     JOIN stop.company_am  ON (stop.contact.id=stop.company_am.contact_id)
                     JOIN stop.company     ON (stop.company_am.company_id = stop.company.id)
            WHERE stop.company.id = p_company_id
            ORDER BY stop.company_am.priority ASC;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        FOR am IN ams LOOP
                IF ( v_res IS NULL ) THEN
                    v_res := am.short;
                ELSE
                    v_res := v_res||','||am.short;
                END IF;

            END LOOP;

        RETURN v_res;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix||'unexpected exception: '||sqlerrm);
            RETURN v_res;
    END get_ams_by_company_id;

END OSAG_GETNODES;
/

--liquibase formatted sql logicalFilePath:pkgb/mss_osag_dbprop.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY MSS.OSAG_DBPROP IS
-------------------------------------------------------------------------------------------
-- FUNCTION get_number_by_host
-- [rv] This implementation is odd since it always returns 0 or 1 (not the converted
--      number). It is only used here: create_pkg_OSAG_IMPLICATION.sql
--      Probably it should be called "get_boolean_by_host" and RETURN BOOLEAN
-------------------------------------------------------------------------------------------

    FUNCTION get_number_by_host(i_host_id NUMBER, i_property_name VARCHAR2)
        RETURN NUMBER
        IS
        l_string	mss.value.string_value%TYPE	:= NULL;
        c_prefix 	CONSTANT VARCHAR2(64)		:= 'OSAG_DBPROP.get_number_by_host(): ';
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT get_string_by_host(i_host_id,i_property_name) INTO l_string FROM DUAL;
        IF(l_string = '1') THEN
            RETURN(1);
        ELSE
            RETURN(0);
        END IF;
    END get_number_by_host;

-------------------------------------------------------------------------------------------
-- FUNCTION get_string_by_host_key_id
-------------------------------------------------------------------------------------------


    FUNCTION get_string_by_host_key_id(i_host_id NUMBER, i_property_key_id NUMBER)
        RETURN VARCHAR2
        IS
        l_string	mss.value.string_value%TYPE	:= NULL;
        c_prefix 	CONSTANT VARCHAR2(64)		:= 'OSAG_DBPROP.get_string_by_host_key_id(): ';
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);

        l_string := NULL;
        for r in (
            select *
            from mss.V_HOST_KEY_VALUE hkv, mss.KEY k
            where hkv.HOST_ID = i_host_id
              and k.id = i_property_key_id
              and hkv.KEY_NAME = k.name) loop
                if (l_string IS NULL)  then
                    l_string := r.string_value;
                elsif (l_string = r.string_value) then
                    plog.warning(c_prefix||' dbprop '|| r.key_name ||' for host_id='|| i_host_id
                        ||', scope='|| r.scope ||' has multiple but consistent values: '|| l_string);
                else
                    plog.err(c_prefix||' dbprop '|| r.key_name ||' for host_id='|| i_host_id
                        ||', scope='|| r.scope ||' has multiple inconsistently values: '|| l_string ||' vs. '|| r.string_value);
                end if;
            end loop;

        RETURN l_string;
    END get_string_by_host_key_id;



-------------------------------------------------------------------------------------------
-- FUNCTION get_string_by_host
-- a wrapper to the function get_string_by_host_key_id defined above
-------------------------------------------------------------------------------------------

    FUNCTION get_string_by_host(i_host_id NUMBER, i_property_name VARCHAR2)
        RETURN VARCHAR2
        IS
        v_key_id NUMBER;
        c_prefix 	CONSTANT VARCHAR2(64)		:= 'OSAG_DBPROP.get_string_by_host(): ';
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        BEGIN
            SELECT id INTO v_key_id FROM mss.key WHERE name = i_property_name;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                plog.err(c_prefix||'unknown db property '||i_property_name);
                RAISE_APPLICATION_ERROR(OSAG_DBPROP_STATE.S_ERRNO_UNKNOWN_DBPROP, 'unknown db property '''||i_property_name||'''');
            WHEN OTHERS THEN
                plog.err(c_prefix||'unexpected error while fetching key id for db property '||i_property_name||': '||sqlerrm);
                RAISE OSAG_DBPROP_STATE.e_abort;
        END;

        RETURN get_string_by_host_key_id(i_host_id, v_key_id);

    END get_string_by_host;

END OSAG_DBPROP;
/

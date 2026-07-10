--liquibase formatted sql logicalFilePath:pkg/esp_osag_duty.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE ESP.OSAG_DUTY IS
    -- ----------------------------------------------------------------------------
    --
    -- This package provides functions/procedures all round
    -- shift planning stuff, including office hours, pikett sms
    --
    -- Copyright (c) 2009 Open Systems AG, Switzerland
    -- All Rights Reserved.
    -------------------------------------------------------------------------------

    /*
     * Returns the date of the next Swiss business day, at 7:30h in the morning
     * Saturday/Sunday as well as legal holidays are respected and
     * do not count for business days.
     * default value for p_date is SYSTIMESTAMP
     */
    FUNCTION get_next_swiss_business_day(p_date TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP) RETURN TIMESTAMP WITH TIME ZONE;

    /*
     * Returns 1 in case the given datetime is during a legal holiday
     * otherwise 0 is returned
     */
    FUNCTION is_legal_holiday(p_date TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP) RETURN NUMBER;
END OSAG_DUTY;
/

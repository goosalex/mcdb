--liquibase formatted sql logicalFilePath:pkg/osag_osag_digest.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE OSAG.OSAG_DIGEST AS
    /*
     * Provide Digest Implementation with an easy interface.
     * Relies on the DBMS_CRYPTO
     */

/*
 * md5
 *
 * Returns the strings MD5 hash.
 *
 *
 * Parameters
 *
 * p_string string to convert
 *
 * Returns a varchar2 with a length of 32 characters
 *
 */
    FUNCTION md5(p_string IN varchar2)
        return varchar2;

/*
 * sha256
 *
 * Returns the string's SHA256 hash in hex representation (upper case letters).
 *
 *
 * Parameters
 *
 * p_string string to convert
 *
 * Returns a varchar2 with a length of 64 characters
 *
 */
    FUNCTION sha256(p_string IN varchar2)
        return varchar2;

END OSAG_DIGEST;
/

CREATE OR REPLACE PUBLIC SYNONYM OSAG_DIGEST FOR OSAG.OSAG_DIGEST
/


--
-- creating role MSS_LOGIN_USER
--
--
-- $Id: create_role_mss_monitor.sql 1653 2012-01-31 15:25:35Z cl $
--
--

CREATE ROLE "MSS_LOGIN_USER";
 GRANT
    CREATE SESSION,
    ALTER SESSION,
    CREATE VIEW   
  TO "MSS_LOGIN_USER";
 

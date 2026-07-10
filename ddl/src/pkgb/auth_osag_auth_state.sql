--liquibase formatted sql logicalFilePath:pkgb/auth_osag_auth_state.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY AUTH.OSAG_AUTH_STATE IS

  FUNCTION GET_JUMP_SSH_CALL RETURN VARCHAR2 AS
    C_OSAG_AUTHSYNC_SSH_CALL CONSTANT VARCHAR2(64) := '/usr/bin/ssh -q -t -t -x radiator@XXXXXX "stty hup; ';
    v_jump varchar2(64);
  BEGIN
    begin
      select j.jump_host into v_jump
      from auth.jumphost j, v$instance i
      where j.db_host = i.host_name;
    exception
      when no_data_found then
        RETURN 'echo "';
    end;
    RETURN REPLACE(C_OSAG_AUTHSYNC_SSH_CALL, 'XXXXXX', v_jump);
  END;
END OSAG_AUTH_STATE;
/

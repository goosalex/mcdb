--liquibase formatted sql logicalFilePath:pkgb/osag_osag_aserto.sql
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY OSAG.OSAG_ASERTO IS
  FUNCTION createEventTemplate RETURN VARCHAR2
  IS
    v_src VARCHAR2(64);
    v_json VARCHAR2(1000);
  BEGIN
    select host_name||'/'||instance_name into v_src from v$instance;
    v_json := '{
"specversion": "1.0.2",
"type": "ch.open.syncify",
"source": "'|| v_src ||'",
"id": "'|| DBMS_RANDOM.STRING('a', 32) ||'",
"time": "'|| TO_CHAR(CURRENT_TIMESTAMP AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') ||'Z",
"datacontenttype": "application/json",
"data": DATA
}';
    return v_json;
  END;


  PROCEDURE PublishAsertoAction(
    p_action VARCHAR2,
    p_subj_type VARCHAR2,
    p_subj_id VARCHAR2,
    p_relation VARCHAR2,
    p_obj_type VARCHAR2,
    p_obj_id VARCHAR2
  ) IS
    v_json VARCHAR2(1000);
  BEGIN
    v_json := createEventTemplate();
    v_json := REPLACE(v_json, 'DATA',
    '[
{
"event_type": "'|| p_action ||'",
"subject_type": "'|| p_subj_type ||'",
"subject_id": "'|| p_subj_id ||'",
"relation": "'|| p_relation ||'",
"object_type": "'|| p_obj_type ||'",
"object_id":"'|| p_obj_id ||'"
}
]');
    OSAG_PLOG.LogRaw(1, replace(v_json, chr(10), ' '));
  END;


  PROCEDURE PublishAsertoUpdate(
    p_subj_type VARCHAR2,
    p_subj_prev_id VARCHAR2,
    p_subj_id VARCHAR2,
    p_relation VARCHAR2,
    p_obj_type VARCHAR2,
    p_obj_prev_id VARCHAR2,
    p_obj_id VARCHAR2
  ) IS
    v_data VARCHAR2(600);
    v_json VARCHAR2(1000);
  BEGIN
    if p_subj_prev_id = p_subj_id and p_obj_prev_id = p_obj_id then
      -- update but it's a noop
      return;
    end if;

    v_data := '';
    if p_subj_prev_id is not null and p_obj_prev_id is not null then
      v_data := '{
"event_type": "delete",
"subject_type": "'|| p_subj_type ||'",
"subject_id": "'|| p_subj_prev_id ||'",
"relation": "'|| p_relation ||'",
"object_type": "'|| p_obj_type ||'",
"object_id":"'|| p_obj_prev_id ||'"
}';
    end if;

    if p_subj_id is not null and p_obj_id is not null then
      if v_data is not null then
        v_data := v_data || ', ';
      end if;
      v_data := v_data || '{
"event_type": "create",
"subject_type": "'|| p_subj_type ||'",
"subject_id": "'|| p_subj_id ||'",
"relation": "'|| p_relation ||'",
"object_type":  "'|| p_obj_type ||'",
"object_id":"'|| p_obj_id ||'"
}';
    end if;

    if v_data is null then
      return;
    end if;

    v_json := createEventTemplate();
    v_json := REPLACE(v_json, 'DATA', '[ '|| v_data ||' ]');

    OSAG_PLOG.LogRaw(1, replace(v_json, chr(10), ' '));
  END;
END OSAG_ASERTO;
/

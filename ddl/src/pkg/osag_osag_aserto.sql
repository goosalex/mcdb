--liquibase formatted sql logicalFilePath:pkg/osag_osag_aserto.sql
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE OSAG.OSAG_ASERTO IS
  -- Publishes to Aserto the creation of an edge.
  PROCEDURE PublishAsertoAction(
    -- create, delete
    p_action VARCHAR2,
    p_subj_type VARCHAR2,
    p_subj_id VARCHAR2,
    p_relation VARCHAR2,
    p_obj_type VARCHAR2,
    p_obj_id VARCHAR2
  );

  -- Publishes to Aserto the update of an edge as one or two events
  -- create, delete, delete+create depending on which pairs of IDs are NOT NULL
  PROCEDURE PublishAsertoUpdate(
    p_subj_type VARCHAR2,
    -- previous ID
    p_subj_prev_id VARCHAR2,
    p_subj_id VARCHAR2,
    p_relation VARCHAR2,
    p_obj_type VARCHAR2,
    -- previous ID
    p_obj_prev_id VARCHAR2,
    p_obj_id VARCHAR2
  );
END OSAG_ASERTO;
/
--
CREATE OR REPLACE PUBLIC SYNONYM aserto FOR OSAG.OSAG_ASERTO
/
GRANT EXECUTE ON OSAG.OSAG_ASERTO TO PUBLIC
/

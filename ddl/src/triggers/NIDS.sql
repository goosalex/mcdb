--liquibase formatted sql logicalFilePath:triggers/NIDS.sql
--changeset sys:1 runOnChange:true endDelimiter:/
--comment: CLOUD-1038: add delete triggers to cleanup automatic FW.IP_GROUP and dependent members
GRANT EXECUTE ON FW.DELETE_AUTO_IP_GROUPS TO NIDS
/

CREATE OR REPLACE TRIGGER NIDS.TRG_POLICY_RULE_DEL_IP_GROUPS
AFTER DELETE ON NIDS.POLICY_RULE
FOR EACH ROW
BEGIN
    FW.DELETE_AUTO_IP_GROUPS(:OLD.SRC_AUTOMATIC_IP_GROUP_ID, :OLD.DST_AUTOMATIC_IP_GROUP_ID);
END;
/

--liquibase formatted sql logicalFilePath:triggers/FW.sql
--changeset sys:1 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.TRG_DST_NAT_DEL_IP_GROUPS
AFTER DELETE ON FW.DESTINATION_NAT_RULE
FOR EACH ROW
BEGIN
    FW.DELETE_AUTO_IP_GROUPS(:OLD.ORIG_SRC_GROUP_ID, :OLD.ORIG_DST_GROUP_ID, :OLD.TRANS_DST_GROUP_ID);
END;
/

--changeset sys:2 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.TRG_RULE_DEL_IP_GROUPS
AFTER DELETE ON FW.RULE
FOR EACH ROW
BEGIN
    FW.DELETE_AUTO_IP_GROUPS(:OLD.SRC_IP_GROUP_ID, :OLD.DST_IP_GROUP_ID);
END;
/

--changeset sys:3 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.TRG_SCIPGSCOPE_DEL_IP_GROUPS
AFTER DELETE ON FW.SCOPED_IP_GROUP_SCOPE
FOR EACH ROW
BEGIN
    FW.DELETE_AUTO_IP_GROUPS(:OLD.IP_GROUP_ID);
END;
/

--changeset sys:4 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.TRG_SRC_NAT_DEL_IP_GROUPS
AFTER DELETE ON FW.SOURCE_NAT_RULE
FOR EACH ROW
BEGIN
    FW.DELETE_AUTO_IP_GROUPS(:OLD.ORIG_SRC_GROUP_ID, :OLD.ORIG_DST_GROUP_ID, :OLD.TRANS_SRC_GROUP_ID);
END;
/

--changeset sys:5 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.TRG_VERSION_APP_GROUP
    BEFORE INSERT OR UPDATE ON FW.APP_GROUP
    FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
ELSE
    :new.version := :old.version + 1;
END IF;
END;
/

--changeset sys:6 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.TRG_VERSION_DESTINATION_NAT_RULE
    BEFORE INSERT OR UPDATE ON FW.DESTINATION_NAT_RULE
    FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
ELSE
    :new.version := :old.version + 1;
END IF;
END;
/

--changeset sys:7 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.TRG_VERSION_DNS_OBJECT
    BEFORE INSERT OR UPDATE ON FW.DNS_OBJECT
    FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
ELSE
    :new.version := :old.version + 1;
END IF;
END;
/

--changeset sys:8 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.trg_version_ip
  BEFORE INSERT OR UPDATE ON FW.IP_ADDRESS
  FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
  ELSE
    :new.version := :old.version + 1;
  END IF;
END;
/

--changeset sys:9 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.trg_version_ipg
  BEFORE INSERT OR UPDATE ON FW.IP_GROUP
  FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
  ELSE
    :new.version := :old.version + 1;
  END IF;
END;
/

--changeset sys:10 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.trg_version_ipsrv
  BEFORE INSERT OR UPDATE ON FW.IP_SERVICE
  FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
  ELSE
    :new.version := :old.version + 1;
  END IF;
END;
/

--changeset sys:11 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.TRG_VERSION_NAT_SECTION
    BEFORE INSERT OR UPDATE ON FW.NAT_SECTION
    FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
ELSE
    :new.version := :old.version + 1;
END IF;
END;
/

--changeset sys:12 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.TRG_VERSION_POLICY
    BEFORE INSERT OR UPDATE ON FW.POLICY
    FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
ELSE
    :new.version := :old.version + 1;
END IF;
END;
/

--changeset sys:13 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.TRG_VERSION_RULE
    BEFORE INSERT OR UPDATE ON FW.RULE
    FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
ELSE
    :new.version := :old.version + 1;
END IF;
END;
/

--changeset sys:14 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.TRG_VERSION_SCOPED_IP_GROUP
    BEFORE INSERT OR UPDATE ON FW.SCOPED_IP_GROUP
    FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
ELSE
    :new.version := :old.version + 1;
END IF;
END;
/

--changeset sys:15 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.TRG_VERSION_SCOPED_IP_GROUP_MEMBER
    BEFORE INSERT OR UPDATE ON FW.SCOPED_IP_GROUP_MEMBER
    FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
ELSE
    :new.version := :old.version + 1;
END IF;
END;
/

--changeset sys:16 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.TRG_VERSION_SECTION
    BEFORE INSERT OR UPDATE ON FW.SECTION
    FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
ELSE
    :new.version := :old.version + 1;
END IF;
END;
/

--changeset sys:17 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.trg_version_sg
  BEFORE INSERT OR UPDATE ON FW.SERVICE_GROUP
  FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
  ELSE
    :new.version := :old.version + 1;
  END IF;
END;
/

--changeset sys:18 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER FW.TRG_VERSION_SOURCE_NAT_RULE
    BEFORE INSERT OR UPDATE ON FW.SOURCE_NAT_RULE
    FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
ELSE
    :new.version := :old.version + 1;
END IF;
END;
/


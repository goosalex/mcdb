--liquibase formatted sql logicalFilePath:triggers/MSS.sql
--changeset sys:1 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER MSS.trg_version_iface
  BEFORE INSERT OR UPDATE ON MSS.INTERFACE
  FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
  ELSE
    :new.version := :old.version + 1;
  END IF;
END;
/

--changeset sys:2 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER MSS.trg_version_ipv6
  BEFORE INSERT OR UPDATE ON MSS.IPV6_ADDRESS
  FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
  ELSE
    :new.version := :old.version + 1;
  END IF;
END;
/

--changeset sys:3 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER MSS.trg_version_net
  BEFORE INSERT OR UPDATE ON MSS.NETWORK
  FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
  ELSE
    :new.version := :old.version + 1;
  END IF;
END;
/

--changeset sys:4 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER MSS.trg_version_netv6
  BEFORE INSERT OR UPDATE ON MSS.IPV6_PREFIX
  FOR EACH ROW
BEGIN
  IF :old.version IS NULL THEN
    :new.version := 0;
  ELSE
    :new.version := :old.version + 1;
  END IF;
END;
/

--changeset sys:5 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER MSS.t_hardware_disposal
  AFTER INSERT OR UPDATE ON MSS.hardware
  FOR each row

DECLARE

  S_PREFIX CONSTANT VARCHAR2(64) := 'mss.t_hardware_disposal(): ';
  l_type_name    mss.hardware_type.name%TYPE := NULL;

BEGIN

  IF (:new.disposal_date IS NOT NULL ) THEN
    BEGIN
      SELECT name INTO l_type_name FROM mss.hardware_type
        WHERE id = :new.hardware_type_id;
    EXCEPTION
      WHEN OTHERS THEN
        l_type_name := NULL;
    END;
    plog.notice('hardware disposal: '
      ||'hardware_id='       ||:new.id
      ||',hardware_type='    ||NVL(l_type_name,'NULL')
      ||',barcode='          ||NVL(:new.barcode,'NULL')
      ||',serial_number='    ||NVL(:new.serial_number,'NULL')
      ||',mac_address='      ||NVL(:new.mac_address,'NULL')
      ||',purchase_date='    ||NVL(TO_CHAR(:new.purchase_date,'dd.mm.yyyy'),'NULL')
      ||',disposal_date='    ||NVL(TO_CHAR(:new.disposal_date,'dd.mm.yyyy'),'NULL')
    );
  END IF;

EXCEPTION

  WHEN OTHERS THEN
    plog.err(S_PREFIX||'caught exception: '||sqlerrm);

END t_hardware_disposal;
/

--changeset sys:6 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER MSS.t_host2service_aserto
  AFTER INSERT OR UPDATE OR DELETE ON mss.HOST2SERVICE
  FOR each row
BEGIN
  aserto.PublishAsertoUpdate(
  'service',
  :OLD.service_id,
  :NEW.service_id,
  'parent_service',
  'host',
  :OLD.host_id,
  :NEW.host_id
  );
END;
/

--changeset sys:7 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER "MSS"."T_SERVICE_ASERTO" AFTER UPDATE OR INSERT OR DELETE ON "MSS"."SERVICE" 
REFERENCING OLD AS OLD NEW AS NEW FOR EACH ROW 
DECLARE
  v_cu_old number;
  v_cu_new number;
BEGIN
  aserto.PublishAsertoUpdate(
  'company',
  :OLD.company_id,
  :NEW.company_id,
  'parent_company',
  'service',
  :OLD.id,
  :NEW.id
  );

  v_cu_old := :OLD.company_unit_id;
  if v_cu_old is null then
    begin
      select c.DEFAULT_COMPANY_UNIT_ID into v_cu_old
      from stop.COMPANY c
      where c.id = :OLD.company_id;
    exception
      when no_data_found then
        v_cu_old := null;
    end;
  end if;
  v_cu_new := :NEW.company_unit_id;
  if v_cu_new is null then
    begin
      select c.DEFAULT_COMPANY_UNIT_ID into v_cu_new
      from stop.COMPANY c
      where c.id = :NEW.company_id;
    exception
      when no_data_found then
        v_cu_new := null;
    end;
  end if;

  aserto.PublishAsertoUpdate(
  'company_unit',
  v_cu_old,
  v_cu_new,
  'parent_company_unit',
  'service',
  :OLD.id,
  :NEW.id
  );

  aserto.PublishAsertoUpdate(
  'service',
  :OLD.id,
  :NEW.id,
  'child_service',
  'company',
  :OLD.company_id,
  :NEW.company_id
  );
END;
/


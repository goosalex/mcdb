--liquibase formatted sql logicalFilePath:triggers/STOP.sql
--changeset sys:1 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER STOP.t_companytype_aserto
  AFTER INSERT OR DELETE ON stop.COMP_COMPTYPE_REF
  FOR each row
DECLARE
  v_cust_group NUMBER;
  v_company_group_old NUMBER;
  v_company_group_new NUMBER;
BEGIN
  if NVL(:NEW.COMPTYPE_ID, :OLD.COMPTYPE_ID) = 1 then
    
    select DECODE(c.SWISS_ONLY_OPS,
                  0, 1,
                  1, 3) into v_cust_group
    from stop.company c where c.id = NVL(:NEW.company_id, :OLD.company_id);
    v_company_group_old := v_cust_group;
    if :OLD.company_id  = 6 then
      v_company_group_old := 2;
    end if;
    v_company_group_new := v_cust_group;
    if :NEW.company_id  = 6 then
      v_company_group_new := 2;
    end if;

    aserto.PublishAsertoUpdate(
    'company_group',
    v_company_group_old,
    v_company_group_new,
    'parent_company_group',
    'company',
    :OLD.company_id,
    :NEW.company_id
    );

    aserto.PublishAsertoUpdate(
    'company',
    :OLD.company_id,
    :NEW.company_id,
    'reference_company',
    'company_object_relation_management',
    :OLD.company_id,
    :NEW.company_id
    );

    aserto.PublishAsertoUpdate(
    'company_group_object_relation_management',
    v_company_group_old,
    v_company_group_new,
    'parent_company_group_object_relation_management',
    'company_object_relation_management',
    :OLD.company_id,
    :NEW.company_id
    );

  end if;
END;
/

--changeset sys:2 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER STOP.t_companyunit_aserto
  AFTER INSERT OR UPDATE OR DELETE ON stop.COMPANY_UNIT
  FOR each row
BEGIN
  aserto.PublishAsertoUpdate(
  'company',
  :OLD.company_id,
  :NEW.company_id,
  'parent_company',
  'company_unit',
  :OLD.id,
  :NEW.id
  );
  aserto.PublishAsertoUpdate(
  'company_unit',
  :OLD.id,
  :NEW.id,
  'child_company_unit',
  'company',
  :OLD.company_id,
  :NEW.company_id
  );
END;
/

--changeset sys:3 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER STOP.t_company_aserto
  AFTER UPDATE OF SWISS_ONLY_OPS, DEFAULT_COMPANY_UNIT_ID ON stop.COMPANY
  FOR each row
DECLARE
  v_is_cust NUMBER;
  v_group_old NUMBER;
  v_group_new NUMBER;
  v_cu_old NUMBER;
  v_cu_new NUMBER;
BEGIN
  
  begin
    v_is_cust := 0;
    select DECODE(company_id,
                  6, 0,
                  1) into v_is_cust
      from stop.COMP_COMPTYPE_REF
     where company_id = NVL(:NEW.id, :OLD.id)
       and COMPTYPE_ID = 1;
  exception
    when no_data_found then
      return;
  end;

  if v_is_cust = 1 then
    
    select DECODE(:OLD.swiss_only_ops, 0, 1, 1, 3) into v_group_old from dual;
    select DECODE(:NEW.swiss_only_ops, 0, 1, 1, 3) into v_group_new from dual;

    
    aserto.PublishAsertoUpdate(
    'company_group',
    v_group_old,
    v_group_new,
    'parent_company_group',
    'company',
    :OLD.id,
    :NEW.id
    );
  end if;

  for s in (
    select s.id, s.company_unit_id
    from mss.service s
    where s.COMPANY_ID = NVL(:NEW.id, :OLD.id)
    ) loop

      v_cu_old := s.company_unit_id;
      if v_cu_old is null then
        v_cu_old := :OLD.DEFAULT_COMPANY_UNIT_ID;
      end if;
      v_cu_new := s.company_unit_id;
      if v_cu_new is null then
        v_cu_new := :NEW.DEFAULT_COMPANY_UNIT_ID;
      end if;

      aserto.PublishAsertoUpdate(
      'company_unit',
      v_cu_old,
      v_cu_new,
      'parent_company_unit',
      'service',
      s.id,
      s.id
      );
  end loop;

END;
/

--changeset sys:4 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER STOP.T_PASSPORT_CONTACT_DN_SET_DIRTYAUTHHOST
    after insert or update of DISTINGUISHEDNAME or delete
    on STOP.PASSPORT_CONTACT_SYNC
    for each row
DECLARE

    S_PREFIX CONSTANT VARCHAR2(64) := 'stop.t_passport_contact_dn_set_dirtyauthhost(): ';

    CURSOR c_contact_sync_ids2authhost (p_old_contact_sync stop.PASSPORT_CONTACT_SYNC.contact_id%TYPE, p_new_contact_sync stop.PASSPORT_CONTACT_SYNC.contact_id%TYPE) IS
        SELECT homeauthhost_id
        FROM auth.passport_login
        WHERE auth.passport_login.contact_id IN (p_old_contact_sync, p_new_contact_sync);

BEGIN
    FOR res IN c_contact_sync_ids2authhost(:OLD.contact_id, :NEW.contact_id) LOOP
            IF (res.homeauthhost_id IS NOT NULL) THEN
                UPDATE auth.dirtyauthhost
                SET login = 1
                WHERE authhost_id = res.homeauthhost_id;

                IF (SQL%FOUND) THEN
                    plog.debug(S_PREFIX||'updated dirtyauthhost.login entry for old authhost id "'||res.homeauthhost_id||'"');
                ELSE
                    INSERT INTO auth.dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
                    VALUES (res.homeauthhost_id, 1, 0, 0, 0, 0, 0, 0);
                    plog.debug(S_PREFIX||'inserted dirtyauthhost.login entry for old authhost id "'||res.homeauthhost_id||'"');
                END IF;
            END IF;
        END LOOP;

END t_passport_contact_dn_set_dirtyauthhost;
/


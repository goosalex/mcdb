--liquibase formatted sql logicalFilePath:triggers/AUTH.sql
--changeset sys:1 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER AUTH.t_authhost_set_dirtyauthhost
  AFTER INSERT OR UPDATE OF host_id, backupstatus ON auth.authhost
  FOR each row

DECLARE

  S_PREFIX CONSTANT VARCHAR2(64) := 'auth.t_authhost_set_dirtyauthhost(): ';

BEGIN
  
  
  
  IF ((:OLD.backupstatus IS NOT NULL) AND (:OLD.backupstatus != NVL(:NEW.backupstatus, -1))) THEN
    UPDATE dirtyauthhost
      SET login = 1, token = 1, groups = 1, login2groups = 1, tunnelgroup = 1, login2tunnelgroup = 1
      WHERE authhost_id = :NEW.backupauthhost_id;

    IF (SQL%FOUND) THEN
      plog.debug(S_PREFIX||'updated dirtyauthhost entry for backup authhost id "'||:NEW.backupauthhost_id||'"');
    ELSE
      INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
        VALUES (:NEW.backupauthhost_id, 1, 1, 1, 1, 1, 1, 1);

      plog.debug(S_PREFIX||'inserted dirtyauthhost entry for backup authhost id "'||:NEW.backupauthhost_id||'"');
    END IF;
  END IF;

  
  UPDATE dirtyauthhost
    SET login = 1, token = 1, groups = 1, login2groups = 1, tunnelgroup = 1, login2tunnelgroup = 1
    WHERE authhost_id = :NEW.id;

  IF (SQL%FOUND) THEN
    plog.debug(S_PREFIX||'updated dirtyauthhost entry for master authhost id "'||:NEW.id||'"');
  ELSE
    INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
      VALUES (:NEW.id, 1, 1, 1, 1, 1, 1, 1);

    plog.debug(S_PREFIX||'inserted dirtyauthhost entry for master authhost id "'||:NEW.id||'"');
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    plog.err(S_PREFIX||'caught exception: '||sqlerrm);
    RAISE;

END t_authhost_set_dirtyauthhost;
/

--changeset sys:2 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER AUTH.t_groups_set_dirtyauthhost
  AFTER INSERT OR DELETE OR UPDATE OF id, name, authsys_id ON auth.groups
  FOR each row

DECLARE

  S_PREFIX CONSTANT VARCHAR2(64) := 'auth.t_groups_set_dirtyauthhost(): ';

  CURSOR c_authhost2authsys (p_authsys_id groups.authsys_id%TYPE) IS
    SELECT authhost_id
      FROM authhost2authsys
      WHERE authsys_id = p_authsys_id;

BEGIN
  
  IF (:OLD.authsys_id IS NOT NULL) THEN
    FOR r_authhost2authsys IN c_authhost2authsys(:OLD.authsys_id) LOOP
      UPDATE dirtyauthhost
	SET groups = 1
	WHERE authhost_id = r_authhost2authsys.authhost_id;

      IF (SQL%FOUND) THEN
	plog.debug(S_PREFIX||'updated dirtyauthhost.groups entry for old authhost id "'||r_authhost2authsys.authhost_id||'"');
      ELSE
        INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
          VALUES (r_authhost2authsys.authhost_id, 0, 0, 1, 0, 0, 0, 0);

        plog.debug(S_PREFIX||'inserted dirtyauthhost.groups entry for old authhost id "'||r_authhost2authsys.authhost_id||'"');
      END IF;
    END LOOP;
  END IF;

  IF ((:NEW.authsys_id IS NOT NULL) AND (NVL(:OLD.authsys_id, -1) != :NEW.authsys_id)) THEN
    FOR r_authhost2authsys IN c_authhost2authsys(:NEW.authsys_id) LOOP
      UPDATE dirtyauthhost
	SET groups = 1
	WHERE authhost_id = r_authhost2authsys.authhost_id;

      IF (SQL%FOUND) THEN
	plog.debug(S_PREFIX||'updated dirtyauthhost.groups entry for new authhost id "'||r_authhost2authsys.authhost_id||'"');
      ELSE
        INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
          VALUES (r_authhost2authsys.authhost_id, 0, 0, 1, 0, 0, 0, 0);

        plog.debug(S_PREFIX||'inserted dirtyauthho.groups entry for new authhost id "'||r_authhost2authsys.authhost_id||'"');
      END IF;
    END LOOP;
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    plog.err(S_PREFIX||'caught exception: '||sqlerrm);
    RAISE;

END t_groups_set_dirtyauthhost;
/

--changeset sys:3 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER AUTH.t_login_set_company
  BEFORE INSERT OR UPDATE ON auth.login

  FOR EACH ROW

DECLARE
  v_company_id STOP.COMPANY.ID%TYPE := 0;
BEGIN

  BEGIN
    SELECT company_id INTO v_company_id FROM stop.contact c WHERE c.id = :NEW.contact_id;

    :NEW.company_id := v_company_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      :NEW.company_id := NULL;
    WHEN OTHERS THEN
      plog.err('t_login_set_company: caught exception: '||sqlerrm);
  END;

  IF (INSERTING and :NEW.OIDC_ZITADEL_ID is not null) or
     (UPDATING and :NEW.OIDC_ZITADEL_ID is not null and :OLD.OIDC_ZITADEL_ID is null) THEN
     
     
     for r in (select DECODE(ur.NAME,
                             'mc-osag-monitor', 'mc_engineer_viewer',
                             'mc-osag-admin', 'mc_engineer_with_users_editor') rel1,
                      DECODE(ur.NAME,
                             'mc-osag-monitor', 'mc_engineer_viewer',
                             'mc-osag-admin', 'mc_engineer_editor') rel2,
                     NVL(:NEW.OIDC_ZITADEL_ID, :OLD.OIDC_ZITADEL_ID) user_id
              from auth.USER_PERMISSION up, auth.USER_ROLE ur, auth.LOGIN2PROFILE l2p
              where ur.NAME in ('mc-osag-monitor', 'mc-osag-admin')
                and l2p.PROFILE_ID = up.PROFILE_ID
                and l2p.LOGIN_ID = NVL(:OLD.id, :NEW.id)
                and ur.id = up.USER_ROLE_ID) loop
       aserto.PublishAsertoAction(
        'create',
        'user',
        r.user_id,
        r.rel1,
        'company_group',
        '1'
       );
       aserto.PublishAsertoAction(
       'create',
       'user',
       r.user_id,
       r.rel2,
       'company_group',
       '2'
       );
     end loop;

     for r in (select DECODE(ur.NAME,
                             'mc-prx-admin', 'proxy_administrator',
                             'mc-threat-protection-admin', 'tp_administrator',
                             'mca-conf-fw-admin', 'firewall_administrator',
                             'mca-access', 'mca_viewer',
                             'mca-conf-mgmt', 'mca_editor',
                             'mca-permission-admin', 'mca_user_editor',
                             'mca-conf-app-admin', 'app_editor',
                             'mca-exec', 'mca_executor',
                             'mca-host-decommission', 'host_deleter',
                             'mca-hw-admin', 'hw_editor',
                             'mca-news-publisher', 'news_editor',
                             'mca-tt-admin', 'tt_editor',
                             'esp-admin', 'ops_editor'
                      ) rel,
                      NVL(:NEW.OIDC_ZITADEL_ID, :OLD.OIDC_ZITADEL_ID) user_id
               from auth.USER_PERMISSION up, auth.USER_ROLE ur, auth.LOGIN2PROFILE l2p
               where ur.NAME in ('mc-prx-admin', 'mc-threat-protection-admin', 'mca-conf-fw-admin',
                                 'mca-access', 'mca-conf-mgmt', 'mca-permission-admin', 'mca-conf-app-admin',
                                 'mca-exec', 'mca-host-decommission', 'mca-hw-admin', 'mca-news-publisher',
                                 'mca-tt-admin', 'esp-admin')
                 and l2p.PROFILE_ID = up.PROFILE_ID
                 and l2p.LOGIN_ID = NVL(:OLD.id, :NEW.id)
                 and ur.id = up.USER_ROLE_ID) loop
         aserto.PublishAsertoAction(
         'create',
         'user',
         r.user_id,
         r.rel,
         'internal_permissions',
         '1'
         );
     end loop;

     for r in (select DECODE(ur.NAME,
                             'mc-cust-access', 'basic_accessor',
                             'mc-cust-monitor', 'viewer',
                             'mc-cust-auditor', 'auditor',
                             'mc-cust-admin',   'editor',
                             'mc-cust-tp-mgmt', 'tp_self_service_editor',
                             'mc-cust-prx-config-mgmt', 'proxy_self_service_editor',
                             'mc-cust-fw-config-mgmt', 'firewall_self_service_editor',
                             'mc-cust-casb-policy-mgmt', 'casb_self_service_editor',
                             'mc-cust-mail-config-mgmt', 'mail_self_service_editor',
                             'mc-cust-api', 'api_access_user',
                             'mc-cust-api-users-mgmt', 'api_users_self_service_editor',
                             'mc-cust-incident-resp-mgmt', 'ndr_service_handler',
                             'mc-cust-cert-mgmt', 'cert_self_service_manager',
                             'mc-cust-network-admin', 'network_editor',
                             'mc-cust-network-req', 'network_requester',
                             'mc-cust-sign-off', 'approver',
                             'mc-cust-users-monitor', 'mep_user_viewer',
                             'mc-cust-users-auditor', 'mep_user_auditor',
                             'mc-cust-users-admin', 'mep_user_editor',
                             'mc-cust-open-systems-identity-users-admin', 'open_systems_identity_user_editor',
                             'mc-cust-open-systems-identity-users-auditor', 'open_systems_identity_user_auditor',
                             'mc-cust-open-systems-identity-users-monitor', 'open_systems_identity_user_viewer'
                      ) rel,
                      NVL(:NEW.OIDC_ZITADEL_ID, :OLD.OIDC_ZITADEL_ID) user_id,
                      ucs.company_id
               from auth.USER_COMPANY_SCOPE ucs, auth.USER_PERMISSION up, auth.USER_ROLE ur, auth.LOGIN2PROFILE l2p
               where up.USER_ROLE_ID = ur.id
                 and ur.NAME in ('mc-cust-access', 'mc-cust-monitor', 'mc-cust-auditor', 'mc-cust-admin',
                                 'mc-cust-tp-mgmt', 'mc-cust-prx-config-mgmt', 'mc-cust-fw-config-mgmt',
                                 'mc-cust-casb-policy-mgmt', 'mc-cust-mail-config-mgmt', 'mc-cust-api',
                                 'mc-cust-api-users-mgmt', 'mc-cust-incident-resp-mgmt', 'mc-cust-cert-mgmt', 'mc-cust-network-admin', 'mc-cust-network-req',
                                 'mc-cust-sign-off', 'mc-cust-users-monitor', 'mc-cust-users-auditor', 'mc-cust-users-admin',
                                 'mc-cust-open-systems-identity-users-admin', 'mc-cust-open-systems-identity-users-auditor', 'mc-cust-open-systems-identity-users-monitor')
                 and l2p.PROFILE_ID = up.PROFILE_ID
                 and l2p.LOGIN_ID = NVL(:NEW.id, :OLD.id)
                 and up.id = ucs.PERMISSION_ID) loop
       aserto.PublishAsertoAction(
         'create',
         'user',
         r.user_id,
         r.rel,
         'company',
         r.company_id
       );
     end loop;

     
     for r in (select DECODE(ur.NAME,
                             'mc-cust-monitor', 'viewer',
                             'mc-cust-auditor', 'auditor',
                             'mc-cust-admin',   'editor',
                             'mc-cust-incident-resp-mgmt', 'ndr_service_handler',
                             'mc-cust-cert-mgmt', 'cert_self_service_manager',
                             'mc-cust-network-admin', 'network_editor',
                             'mc-cust-network-req', 'network_requester',
                             'mc-cust-sign-off', 'approver',
                             'mc-cust-users-monitor', 'mep_user_viewer',
                             'mc-cust-users-auditor', 'mep_user_auditor',
                             'mc-cust-users-admin', 'mep_user_editor'
                      ) rel,
                      NVL(:NEW.OIDC_ZITADEL_ID, :OLD.OIDC_ZITADEL_ID) user_id,
                      uus.company_unit_id
               from auth.USER_COMPANY_UNIT_SCOPE uus, auth.USER_PERMISSION up, auth.USER_ROLE ur, auth.LOGIN2PROFILE l2p
               where up.USER_ROLE_ID = ur.id
                 and ur.NAME in ('mc-cust-monitor', 'mc-cust-auditor', 'mc-cust-admin',
                                 'mc-cust-incident-resp-mgmt', 'mc-cust-cert-mgmt', 'mc-cust-network-admin', 'mc-cust-network-req', 'mc-cust-sign-off',
                                 'mc-cust-users-monitor', 'mc-cust-users-auditor', 'mc-cust-users-admin')
                 and l2p.PROFILE_ID = up.PROFILE_ID
                 and l2p.LOGIN_ID = NVL(:NEW.id, :OLD.id)
                 and up.id = uus.PERMISSION_ID) loop
       aserto.PublishAsertoAction(
         'create',
         'user',
         r.user_id,
         r.rel,
         'company_unit',
         r.company_unit_id
       );
     end loop;

     
     for r in (select DECODE(ur.NAME,
                             'mc-cust-monitor', 'viewer',
                             'mc-cust-auditor', 'auditor',
                             'mc-cust-admin',   'editor',
                             'mc-cust-incident-resp-mgmt', 'ndr_service_handler',
                             'mc-cust-cert-mgmt', 'cert_self_service_manager',
                             'mc-cust-network-admin', 'network_editor',
                             'mc-cust-network-req', 'network_requester'
                      ) rel,
                      NVL(:NEW.OIDC_ZITADEL_ID, :OLD.OIDC_ZITADEL_ID) user_id,
                      uss.service_id
               from auth.USER_SERVICE_SCOPE uss, auth.USER_PERMISSION up, auth.USER_ROLE ur, auth.LOGIN2PROFILE l2p
               where up.USER_ROLE_ID = ur.id
                 and ur.NAME in ('mc-cust-monitor', 'mc-cust-auditor', 'mc-cust-admin',
                                 'mc-cust-incident-resp-mgmt', 'mc-cust-cert-mgmt', 'mc-cust-network-admin', 'mc-cust-network-req')
                 and l2p.PROFILE_ID = up.PROFILE_ID
                 and l2p.LOGIN_ID = NVL(:NEW.id, :OLD.id)
                 and up.id = uss.PERMISSION_ID) loop
       aserto.PublishAsertoAction(
         'create',
         'user',
         r.user_id,
         r.rel,
         'service',
         r.service_id
       );
     end loop;
  END IF;

END t_login_set_company;
/

--changeset sys:4 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER AUTH.T_PASSPORT_ALIAS_SET_DIRTYAUTHHOST
    after insert or update of LOGIN_ID,ALIAS or delete
    on AUTH.PASSPORT_ALIAS
    for each row
DECLARE

    S_PREFIX CONSTANT VARCHAR2(64) := 'auth.t_passport_alias_set_dirtyauthhost(): ';

    v_authhost_id PASSPORT_LOGIN.homeauthhost_id%TYPE := NULL;

BEGIN

    IF (:OLD.login_id IS NOT NULL) THEN
        SELECT homeauthhost_id INTO v_authhost_id
        FROM passport_login WHERE id = :OLD.login_id;

        IF v_authhost_id IS NOT NULL THEN
            UPDATE dirtyauthhost
            SET alias = 1
            WHERE authhost_id = v_authhost_id;

            IF (SQL%FOUND) THEN
                plog.debug(S_PREFIX || 'updated dirtyauthhost.alias entry for old authhost "' || v_authhost_id || '"');
            ELSE
                INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
                VALUES (v_authhost_id, 0, 0, 0, 0, 0, 0, 1);

                plog.debug(S_PREFIX || 'inserted dirtyauthhost.alias entry for old authhost id "' || v_authhost_id || '"');
            END IF;
        END IF;
    END IF;

    IF ((:NEW.login_id IS NOT NULL) AND (NVL(:OLD.login_id, -1) != :NEW.login_id)) THEN
        SELECT homeauthhost_id INTO v_authhost_id
        FROM passport_login WHERE id = :NEW.login_id;

        IF v_authhost_id IS NOT NULL THEN
            UPDATE dirtyauthhost
            SET alias = 1
            WHERE authhost_id = v_authhost_id;

            IF (SQL%FOUND) THEN
                plog.debug(S_PREFIX || 'updated dirtyauthhost.alias entry for new authhost id "' || v_authhost_id || '"');
            ELSE
                INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
                VALUES (v_authhost_id, 0, 0, 0, 0, 0, 0, 1);

                plog.debug(S_PREFIX || 'inserted dirtyauthhost.alias entry for new authhost id "' || v_authhost_id || '"');
            END IF;
        END IF;
    END IF;


EXCEPTION
    WHEN OTHERS THEN
        plog.err(S_PREFIX||'caught exception: '||sqlerrm);
        RAISE;

END t_passport_alias_set_dirtyauthhost;
/

--changeset sys:5 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER AUTH.T_PASSPORT_LOGIN_SET_AUTHTYPE
    before insert or update of TWOFACTORENABLED
    on AUTH.PASSPORT_LOGIN
    for each row
DECLARE

    S_PREFIX CONSTANT VARCHAR2(64) := 'auth.t_passport_login_set_authtype(): ';

BEGIN
    
    IF (:NEW.twofactorenabled = 0 AND :NEW.authtype_id IS NULL) THEN
        
        :NEW.authtype_id := 0;
    ELSIF (:NEW.twofactorenabled = 1 AND :NEW.authtype_id IS NULL) THEN
        
        :NEW.authtype_id := 1;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        plog.err(S_PREFIX||'caught exception: '||sqlerrm);
        RAISE;

END t_passport_login_set_authtype;
/

--changeset sys:6 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER AUTH.T_PASSPORT_LOGIN_SET_COMPANY
    before insert or update
    on AUTH.PASSPORT_LOGIN
    for each row
DECLARE
  v_company_id STOP.COMPANY.ID%TYPE := 0;
BEGIN

    BEGIN

        SELECT company_id INTO v_company_id FROM stop.passport_contact c WHERE c.id = :NEW.contact_id;

        :NEW.company_id := v_company_id;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            :NEW.company_id := NULL;
        WHEN OTHERS THEN
            plog.err('t_passport_login_set_company: caught exception: '||sqlerrm);

    END;

END t_passport_login_set_company;
/

--changeset sys:7 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER AUTH.T_PASSPORT_LOGIN_SET_DEFAULT_UNIT
    before insert
    on AUTH.PASSPORT_LOGIN
    for each row
DECLARE
    v_company_id STOP.COMPANY.ID%TYPE := 0;
    v_user_unit_id AUTH.USER_UNIT.ID%TYPE := 0;

BEGIN

    BEGIN

        IF (:NEW.user_unit_id IS NULL) THEN
            SELECT company_id INTO v_company_id FROM stop.passport_contact c WHERE c.id = :NEW.contact_id;
            SELECT id INTO v_user_unit_id FROM auth.user_unit u WHERE u.company_id = v_company_id AND u.default_unit = 1;
            :NEW.user_unit_id := v_user_unit_id;
        END IF;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            :NEW.user_unit_id := NULL;
        WHEN OTHERS THEN
            plog.err('t_passport_login_set_default_unit: caught exception: '||sqlerrm);

    END;

END t_passport_login_set_default_unit;
/

--changeset sys:8 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER AUTH.T_PASSPORT_LOGIN_SET_DIRTYAUTHHOST
    after insert or update of ID,LOGIN,CONTACT_ID,TOKEN_ID,REPLACEMENTTOKEN_ID,SMSAUTHNUMBER,HOMEAUTHHOST_ID,ENABLED,LOCKED,MAXRETRIES,ANYTUNNELGROUP,PASSWORDEXPIRY,PASSWORDTYPE_ID,TWOFACTORENABLED,AUTHTYPE_ID,PWHASH,SALT,TMPPWDONLYEXPIRY or delete
    on AUTH.PASSPORT_LOGIN
    for each row
DECLARE

    S_PREFIX CONSTANT VARCHAR2(64) := 'auth.t_PASSPORT_login_set_dirtyauthhost(): ';

BEGIN
    
    
    IF (:OLD.homeauthhost_id IS NOT NULL) THEN
        UPDATE dirtyauthhost
        SET login = 1
        WHERE authhost_id = :OLD.homeauthhost_id;

        IF (SQL%FOUND) THEN
            plog.debug(S_PREFIX||'updated dirtyauthhost.login entry for old authhost id "'||:OLD.homeauthhost_id||'"');
        ELSE
            INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
            VALUES (:OLD.homeauthhost_id, 1, 0, 0, 0, 0, 0, 0);

            plog.debug(S_PREFIX||'inserted dirtyauthhost.login entry for old authhost id "'||:OLD.homeauthhost_id||'"');
        END IF;

        
        
        
        IF ((:OLD.token_id IS NOT NULL) AND
            ((:OLD.token_id != NVL(:NEW.token_id, -1)) OR
             (:OLD.homeauthhost_id != NVL(:NEW.homeauthhost_id, -1)))) THEN
            UPDATE dirtyauthhost
            SET token = 1
            WHERE authhost_id = :OLD.homeauthhost_id;

            plog.debug(S_PREFIX||'updated dirtyauthhost.token entry for old authhost id "'||:OLD.homeauthhost_id||'"');
        END IF;

        IF ((:OLD.replacementtoken_id IS NOT NULL) AND
            ((:OLD.replacementtoken_id != NVL(:NEW.replacementtoken_id, -1)) OR
             (:OLD.homeauthhost_id != NVL(:NEW.homeauthhost_id, -1)))) THEN
            UPDATE dirtyauthhost
            SET token = 1
            WHERE authhost_id = :OLD.homeauthhost_id;

            plog.debug(S_PREFIX||'updated dirtyauthhost.token entry for old authhost id "'||:OLD.homeauthhost_id||'"');
        END IF;

        
        IF (:OLD.homeauthhost_id != NVL(:NEW.homeauthhost_id, -1)) THEN
            UPDATE dirtyauthhost
            SET login2groups = 1, login2tunnelgroup = 1
            WHERE authhost_id = :OLD.homeauthhost_id;

            plog.debug(S_PREFIX||'updated dirtyauthhost.login2groups entries for old authhost id "'||:OLD.homeauthhost_id||'"');
        END IF;
    END IF;

    
    IF (:NEW.homeauthhost_id IS NOT NULL) THEN
        IF (NVL(:OLD.homeauthhost_id, -1) != :NEW.homeauthhost_id) THEN
            UPDATE dirtyauthhost
            SET login = 1
            WHERE authhost_id = :NEW.homeauthhost_id;

            IF (SQL%FOUND) THEN
                plog.debug(S_PREFIX||'updated dirtyauthhost.login entry for new authhost id "'||:NEW.homeauthhost_id||'"');
            ELSE
                INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
                VALUES (:NEW.homeauthhost_id, 1, 0, 0, 0, 0, 0, 0);

                plog.debug(S_PREFIX||'inserted dirtyauthhost.login entry for new authhost id "'||:NEW.homeauthhost_id||'"');
            END IF;
        END IF;

        
        
        
        IF ((:NEW.token_id IS NOT NULL) AND
            ((:NEW.token_id != NVL(:OLD.token_id, -1)) OR
             (:NEW.homeauthhost_id != NVL(:OLD.homeauthhost_id, -1)))) THEN
            UPDATE dirtyauthhost
            SET token = 1
            WHERE authhost_id = :NEW.homeauthhost_id;

            IF (SQL%FOUND) THEN
                plog.debug(S_PREFIX||'updated dirtyauthhost.token entry for new authhost id "'||:NEW.homeauthhost_id||'"');
            ELSE
                INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
                VALUES (:NEW.homeauthhost_id, 0, 1, 0, 0, 0, 0, 0);

                plog.debug(S_PREFIX||'inserted dirtyauthhost.token entry for new authhost id "'||:NEW.homeauthhost_id||'"');
            END IF;
        END IF;

        IF ((:NEW.replacementtoken_id IS NOT NULL) AND
            ((:NEW.replacementtoken_id != NVL(:OLD.replacementtoken_id, -1)) OR
             (:NEW.homeauthhost_id != NVL(:OLD.homeauthhost_id, -1)))) THEN
            UPDATE dirtyauthhost
            SET token = 1
            WHERE authhost_id = :NEW.homeauthhost_id;

            IF (SQL%FOUND) THEN
                plog.debug(S_PREFIX||'updated dirtyauthhost.token entry for new authhost id "'||:NEW.homeauthhost_id||'"');
            ELSE
                INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
                VALUES (:NEW.homeauthhost_id, 0, 1, 0, 0, 0, 0, 0);

                plog.debug(S_PREFIX||'inserted dirtyauthhost.token entry for new authhost id "'||:NEW.homeauthhost_id||'"');
            END IF;
        END IF;

        
        IF (:OLD.homeauthhost_id != NVL(:NEW.homeauthhost_id, -1)) THEN
            UPDATE dirtyauthhost
            SET login2groups = 1, login2tunnelgroup = 1
            WHERE authhost_id = :NEW.homeauthhost_id;

            IF (SQL%FOUND) THEN
                plog.debug(S_PREFIX||'updated dirtyauthhost.login2groups entries for new authhost id "'||:NEW.homeauthhost_id||'"');
            ELSE
                INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
                VALUES (:NEW.homeauthhost_id, 0, 0, 0, 1, 0, 1, 0);

                plog.debug(S_PREFIX||'inserted dirtyauthhost.login2groups entries for new authhost id "'||:NEW.homeauthhost_id||'"');
            END IF;
        END IF;

    END IF;

EXCEPTION
    WHEN OTHERS THEN
        plog.err(S_PREFIX||'caught exception: '||sqlerrm);
        RAISE;

END t_passport_login_set_dirtyauthhost;
/

--changeset sys:9 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER AUTH.T_PL2G_SET_DIRTYAUTHHOST
    after insert or update or delete
    on AUTH.PASSPORT_LOGIN2GROUPS
    for each row
DECLARE

    S_PREFIX CONSTANT VARCHAR2(64) := 'auth.t_pl2g_set_dirtyauthhost(): ';

    v_authhost_id dirtyauthhost.authhost_id%type;

BEGIN

    IF (:OLD.login_id IS NOT NULL) THEN
        SELECT homeauthhost_id INTO v_authhost_id FROM passport_login
        WHERE id = :OLD.login_id;

        IF v_authhost_id IS NOT NULL THEN
            UPDATE dirtyauthhost
            SET login2groups = 1
            WHERE authhost_id = v_authhost_id;

            IF (SQL%FOUND) THEN
                plog.debug(S_PREFIX || 'updated dirtyauthhost.login2groups entry for old authhost "' || v_authhost_id || '"');
            ELSE
                INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
                VALUES (v_authhost_id, 0, 0, 0, 1, 0, 0, 0);

                plog.debug(S_PREFIX || 'inserted dirtyauthhost.login2groups entry for old authhost id "' || v_authhost_id ||'"');
            END IF;
        END IF;
    END IF;

    IF ((:NEW.login_id IS NOT NULL) AND (NVL(:OLD.login_id, -1) != :NEW.login_id)) THEN
        SELECT homeauthhost_id INTO v_authhost_id FROM passport_login
        WHERE id = :NEW.login_id;

        IF v_authhost_id IS NOT NULL THEN
            UPDATE dirtyauthhost
            SET login2groups = 1
            WHERE authhost_id = v_authhost_id;

            IF (SQL%FOUND) THEN
                plog.debug(S_PREFIX || 'updated dirtyauthhost.login2groups entry for new authhost id "' || v_authhost_id || '"');
            ELSE
                INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
                VALUES (v_authhost_id, 0, 0, 0, 1, 0, 0, 0);

                plog.debug(S_PREFIX || 'inserted dirtyauthhost.login2groups entry for new authhost id "' || v_authhost_id || '"');
            END IF;
        END IF;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        plog.err(S_PREFIX||'caught exception: '||sqlerrm);
        RAISE;

END t_pl2g_set_dirtyauthhost;
/

--changeset sys:10 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER AUTH.T_PL2TG_SET_DIRTYAUTHHOST
    after insert or update or delete
    on AUTH.PASSPORT_LOGIN2TUNNELGROUP
    for each row
DECLARE

    S_PREFIX CONSTANT VARCHAR2(64) := 'auth.t_pl2tg_set_dirtyauthhost(): ';

    v_authhost_id dirtyauthhost.authhost_id%type;

BEGIN

    IF (:OLD.login_id IS NOT NULL) THEN
        SELECT homeauthhost_id INTO v_authhost_id FROM passport_login
        WHERE id = :OLD.login_id;

        IF v_authhost_id IS NOT NULL THEN
            UPDATE dirtyauthhost
            SET login2tunnelgroup = 1
            WHERE authhost_id = v_authhost_id;

            IF (SQL%FOUND) THEN
                plog.debug(S_PREFIX || 'updated dirtyauthhost.login2tunnelgroup entry for old authhost "' || v_authhost_id || '"');
            ELSE
                INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
                VALUES (v_authhost_id, 0, 0, 0, 0, 0, 1, 0);

                plog.debug(S_PREFIX || 'inserted dirtyauthhost.login2tunnelgroup entry for old authhost id "' || v_authhost_id || '"');
            END IF;
        END IF;
    END IF;

    IF ((:NEW.login_id IS NOT NULL) AND (NVL(:OLD.login_id, -1) != :NEW.login_id)) THEN
        SELECT homeauthhost_id INTO v_authhost_id FROM passport_login
        WHERE id = :NEW.login_id;

        IF v_authhost_id IS NOT NULL THEN
            UPDATE dirtyauthhost
            SET login2tunnelgroup = 1
            WHERE authhost_id = v_authhost_id;

            IF (SQL%FOUND) THEN
                plog.debug(S_PREFIX || 'updated dirtyauthhost.login2tunnelgroup entry for new authhost id "' || v_authhost_id || '"');
            ELSE
                INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
                VALUES (v_authhost_id, 0, 0, 0, 0, 0, 1, 0);

                plog.debug(S_PREFIX || 'inserted dirtyauthhost.login2tunnelgroup for entry new authhost id "' || v_authhost_id || '"');
            END IF;
        END IF;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        plog.err(S_PREFIX||'caught exception: '||sqlerrm);
        RAISE;

END t_pl2tg_set_dirtyauthhost;
/

--changeset sys:11 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER AUTH.t_tgroup_set_dirtyauthhost
  AFTER INSERT OR DELETE OR UPDATE OF id, name, authsys_id ON auth.tunnelgroup
  FOR each row

DECLARE

  S_PREFIX CONSTANT VARCHAR2(64) := 'auth.t_tgroup_set_dirtyauthhost(): ';

  CURSOR c_authhost2authsys (p_authsys_id tunnelgroup.authsys_id%TYPE) IS
    SELECT authhost_id
      FROM authhost2authsys
      WHERE authsys_id = p_authsys_id;

BEGIN
  
  IF (:OLD.authsys_id IS NOT NULL) THEN
    FOR r_authhost2authsys IN c_authhost2authsys(:OLD.authsys_id) LOOP
      UPDATE dirtyauthhost
	SET tunnelgroup = 1
	WHERE authhost_id = r_authhost2authsys.authhost_id;

      IF (SQL%FOUND) THEN
	plog.debug(S_PREFIX||'updated dirtyauthhost.tunnelgroup entry for old authhost id "'||r_authhost2authsys.authhost_id||'"');
      ELSE
        INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup)
          VALUES (r_authhost2authsys.authhost_id, 0, 0, 0, 0, 1, 0);

        plog.debug(S_PREFIX||'inserted dirtyauthhost.tunnelgroup entry for old authhost id "'||r_authhost2authsys.authhost_id||'"');
      END IF;
    END LOOP;
  END IF;

  IF ((:NEW.authsys_id IS NOT NULL) AND (NVL(:OLD.authsys_id, -1) != :NEW.authsys_id)) THEN
    FOR r_authhost2authsys IN c_authhost2authsys(:NEW.authsys_id) LOOP
      UPDATE dirtyauthhost
	SET tunnelgroup = 1
	WHERE authhost_id = r_authhost2authsys.authhost_id;

      IF (SQL%FOUND) THEN
	plog.debug(S_PREFIX||'updated dirtyauthhost.tunnelgroup entry for new authhost id "'||r_authhost2authsys.authhost_id||'"');
      ELSE
        INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup)
          VALUES (r_authhost2authsys.authhost_id, 0, 0, 0, 0, 1, 0);

        plog.debug(S_PREFIX||'inserted dirtyauthhost.tunnelgroup entry for new authhost id "'||r_authhost2authsys.authhost_id||'"');
      END IF;
    END LOOP;
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    plog.err(S_PREFIX||'caught exception: '||sqlerrm);
    RAISE;

END t_tgroup_set_dirtyauthhost;
/

--changeset sys:12 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER AUTH.t_token_set_dirtyauthhost
  AFTER UPDATE OF serial, seed, tokentype_id, validfrom, activated ON AUTH.token
  FOR each row

DECLARE

  S_PREFIX CONSTANT VARCHAR2(64) := 'auth.t_token_set_dirtyauthhost(): ';

  v_authhost_id passport_login.homeauthhost_id%TYPE := NULL;

BEGIN
  SELECT homeauthhost_id INTO v_authhost_id FROM passport_login
  WHERE token_id = :NEW.id or replacementtoken_id = :NEW.id;

  IF v_authhost_id IS NOT NULL THEN
    UPDATE dirtyauthhost
    SET token = 1
    WHERE authhost_id = v_authhost_id;

    IF (SQL%FOUND) THEN
      plog.debug(S_PREFIX || 'updated dirtyauthhost.token entry for old authhost id "' || v_authhost_id || '"');
    ELSE
      INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
      VALUES (v_authhost_id, 0, 1, 0, 0, 0, 0, 0);

      plog.debug(S_PREFIX || 'inserted dirtyauthhost.token entry for old authhost id "' || v_authhost_id || '"');
    END IF;
  END IF;

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    NULL;

  WHEN OTHERS THEN
    plog.err(S_PREFIX||'caught exception: '||sqlerrm);
    RAISE;

END t_token_set_dirtyauthhost;
/

--changeset sys:13 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER auth.t_userunit
  AFTER INSERT OR UPDATE OR DELETE ON auth.USER_UNIT
  FOR each row
BEGIN
  aserto.PublishAsertoUpdate(
  'company',
  :OLD.company_id,
  :NEW.company_id,
  'parent_company',
  'user_unit',
  :OLD.id,
  :NEW.id
  );
  aserto.PublishAsertoUpdate(
  'user_unit',
  :OLD.id,
  :NEW.id,
  'child_user_unit',
  'company',
  :OLD.company_id,
  :NEW.company_id
  );
END;
/

--changeset sys:14 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER auth.t_usrcompsc_aserto
  BEFORE INSERT OR DELETE ON auth.USER_COMPANY_SCOPE
  FOR each row
DECLARE
  v_perm_id integer;
  v_company_id integer;
  v_action varchar2(16);
BEGIN
  if INSERTING then
    v_action := 'create';
    v_perm_id := :NEW.permission_id;
    v_company_id := :NEW.company_id;
  elsif DELETING then
    v_action := 'delete';
    v_perm_id := :OLD.permission_id;
    v_company_id := :OLD.company_id;
  end if;

  for r in (select DECODE(ur.NAME,
                          'mc-cust-access', 'basic_accessor',
                          'mc-cust-monitor', 'viewer',
                          'mc-cust-auditor', 'auditor',
                          'mc-cust-admin',   'editor',
                          'mc-cust-tp-mgmt', 'tp_self_service_editor',
                          'mc-cust-incident-resp-mgmt', 'ndr_service_handler',
                          'mc-cust-cert-mgmt', 'cert_self_service_manager',
                          'mc-cust-network-admin', 'network_editor',
                          'mc-cust-network-req', 'network_requester',
                          'mc-cust-prx-config-mgmt', 'proxy_self_service_editor',
                          'mc-cust-fw-config-mgmt', 'firewall_self_service_editor',
                          'mc-cust-casb-policy-mgmt', 'casb_self_service_editor',
                          'mc-cust-mail-config-mgmt', 'mail_self_service_editor',
                          'mc-cust-api', 'api_access_user',
                          'mc-cust-api-users-mgmt', 'api_users_self_service_editor',
                          'mc-cust-sign-off', 'approver',
                          'mc-cust-users-monitor', 'mep_user_viewer',
                          'mc-cust-users-auditor', 'mep_user_auditor',
                          'mc-cust-users-admin', 'mep_user_editor',
                          'mc-cust-open-systems-identity-users-admin', 'open_systems_identity_user_editor',
                          'mc-cust-open-systems-identity-users-auditor', 'open_systems_identity_user_auditor',
                          'mc-cust-open-systems-identity-users-monitor', 'open_systems_identity_user_viewer'
                   ) rel,
                   l.OIDC_ZITADEL_ID user_id
            from auth.USER_PERMISSION up, auth.USER_ROLE ur, auth.LOGIN2PROFILE l2p, auth.LOGIN l
            where up.USER_ROLE_ID = ur.id
              and ur.NAME in ('mc-cust-access', 'mc-cust-monitor', 'mc-cust-auditor', 'mc-cust-admin',
                             'mc-cust-tp-mgmt', 'mc-cust-incident-resp-mgmt', 'mc-cust-cert-mgmt', 'mc-cust-network-admin', 'mc-cust-network-req', 'mc-cust-prx-config-mgmt', 'mc-cust-fw-config-mgmt',
                             'mc-cust-casb-policy-mgmt', 'mc-cust-mail-config-mgmt', 'mc-cust-api',
                             'mc-cust-api-users-mgmt', 'mc-cust-sign-off',
                             'mc-cust-users-monitor', 'mc-cust-users-auditor', 'mc-cust-users-admin',
                             'mc-cust-open-systems-identity-users-admin', 'mc-cust-open-systems-identity-users-auditor', 'mc-cust-open-systems-identity-users-monitor')
              and l2p.PROFILE_ID = up.PROFILE_ID
              and l2p.LOGIN_ID = l.id
              and l.OIDC_ZITADEL_ID is not null
              and up.id = v_perm_id) loop
      aserto.PublishAsertoAction(
      v_action,
      'user',
      r.user_id,
      r.rel,
      'company',
      v_company_id
      );
    end loop;
END;
/

--changeset sys:15 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER auth.t_usrcompusc_aserto
  BEFORE INSERT OR DELETE ON auth.USER_COMPANY_UNIT_SCOPE
  FOR each row
DECLARE
  v_perm_id integer;
  v_companyunit_id integer;
  v_action varchar2(16);
BEGIN
  if INSERTING then
    v_action := 'create';
    v_perm_id := :NEW.permission_id;
    v_companyunit_id := :NEW.company_unit_id;
  elsif DELETING then
    v_action := 'delete';
    v_perm_id := :OLD.permission_id;
    v_companyunit_id := :OLD.company_unit_id;
  end if;

  for r in (select DECODE(ur.NAME,
                          'mc-cust-monitor', 'viewer',
                          'mc-cust-auditor', 'auditor',
                          'mc-cust-admin',   'editor',
                          'mc-cust-sign-off', 'approver',
                          'mc-cust-incident-resp-mgmt', 'ndr_service_handler',
                          'mc-cust-cert-mgmt', 'cert_self_service_manager',
                          'mc-cust-network-admin', 'network_editor',
                          'mc-cust-network-req', 'network_requester'
                   ) rel,
                   l.OIDC_ZITADEL_ID user_id
            from auth.USER_PERMISSION up, auth.USER_ROLE ur, auth.LOGIN2PROFILE l2p, auth.LOGIN l
            where up.USER_ROLE_ID = ur.id
              and ur.NAME in ('mc-cust-monitor', 'mc-cust-auditor', 'mc-cust-admin',
                              'mc-cust-sign-off', 'mc-cust-incident-resp-mgmt', 'mc-cust-cert-mgmt', 'mc-cust-network-admin', 'mc-cust-network-req')
              and l2p.PROFILE_ID = up.PROFILE_ID
              and l2p.LOGIN_ID = l.id
              and l.OIDC_ZITADEL_ID is not null
              and up.id = v_perm_id) loop
      aserto.PublishAsertoAction(
      v_action,
      'user',
      r.user_id,
      r.rel,
      'company_unit',
      v_companyunit_id
      );
    end loop;
END;
/

--changeset sys:16 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER auth.t_usrperm_aserto
  BEFORE INSERT OR DELETE ON auth.USER_PERMISSION
  FOR each row
DECLARE
  v_id integer;
  v_urole_id integer;
  v_profile_id integer;
  v_action varchar2(16);
BEGIN
  if INSERTING then
    v_action := 'create';
    v_id := :NEW.id;
    v_urole_id := :NEW.user_role_id;
    v_profile_id := :NEW.profile_id;
  elsif DELETING then
    v_action := 'delete';
    v_id := :OLD.id;
    v_urole_id := :OLD.user_role_id;
    v_profile_id := :OLD.profile_id;
  end if;

  for r in (select DECODE(ur.NAME,
                          'mc-osag-monitor', 'mc_engineer_viewer',
                          'mc-osag-admin', 'mc_engineer_with_users_editor') rel1,
                   DECODE(ur.NAME,
                          'mc-osag-monitor', 'mc_engineer_viewer',
                          'mc-osag-admin', 'mc_engineer_editor') rel2,
                   l.OIDC_ZITADEL_ID user_id
            from auth.USER_ROLE ur, auth.LOGIN2PROFILE l2p, auth.LOGIN l
            where ur.NAME in ('mc-osag-monitor', 'mc-osag-admin')
              and l2p.PROFILE_ID = v_profile_id
              and l2p.LOGIN_ID = l.id
              and l.OIDC_ZITADEL_ID is not null
              and ur.id = v_urole_id) loop
      aserto.PublishAsertoAction(
      v_action,
      'user',
      r.user_id,
      r.rel1,
      'company_group',
      '1'
      );

      aserto.PublishAsertoAction(
      v_action,
      'user',
      r.user_id,
      r.rel2,
      'company_group',
      '2'
      );
    end loop;

    for r in (select DECODE(ur.NAME,
                          'mc-prx-admin', 'proxy_administrator',
                          'mc-threat-protection-admin', 'tp_administrator',
                          'mca-conf-fw-admin', 'firewall_administrator',
                          'mca-access', 'mca_viewer',
                          'mca-conf-mgmt', 'mca_editor',
                          'mca-permission-admin', 'mca_user_editor',
                          'mca-conf-app-admin', 'app_editor',
                          'mca-exec', 'mca_executor',
                          'mca-host-decommission', 'host_deleter',
                          'mca-hw-admin', 'hw_editor',
                          'mca-news-publisher', 'news_editor',
                          'mca-tt-admin', 'tt_editor',
                          'esp-admin', 'ops_editor'
                   ) rel,
                   l.OIDC_ZITADEL_ID user_id
            from auth.USER_ROLE ur, auth.LOGIN2PROFILE l2p, auth.LOGIN l
            where ur.NAME in ('mc-prx-admin', 'mc-threat-protection-admin', 'mca-conf-fw-admin',
                              'mca-access', 'mca-conf-mgmt', 'mca-permission-admin', 'mca-conf-app-admin',
                              'mca-exec', 'mca-host-decommission', 'mca-hw-admin', 'mca-news-publisher',
                              'mca-tt-admin', 'esp-admin')
              and l2p.PROFILE_ID = v_profile_id
              and l2p.LOGIN_ID = l.id
              and l.OIDC_ZITADEL_ID is not null
              and ur.id = v_urole_id) loop
      aserto.PublishAsertoAction(
      v_action,
      'user',
      r.user_id,
      r.rel,
      'internal_permissions',
      '1'
      );
    end loop;

    for r in (select DECODE(ur.NAME,
                          'mc-cust-access', 'basic_accessor',
                          'mc-cust-monitor', 'viewer',
                          'mc-cust-auditor', 'auditor',
                          'mc-cust-admin',   'editor',
                          'mc-cust-tp-mgmt', 'tp_self_service_editor',
                          'mc-cust-prx-config-mgmt', 'proxy_self_service_editor',
                          'mc-cust-fw-config-mgmt', 'firewall_self_service_editor',
                          'mc-cust-casb-policy-mgmt', 'casb_self_service_editor',
                          'mc-cust-mail-config-mgmt', 'mail_self_service_editor',
                          'mc-cust-api', 'api_access_user',
                          'mc-cust-api-users-mgmt', 'api_users_self_service_editor',
                          'mc-cust-incident-resp-mgmt', 'ndr_service_handler',
                          'mc-cust-cert-mgmt', 'cert_self_service_manager',
                          'mc-cust-network-admin', 'network_editor',
                          'mc-cust-network-req', 'network_requester',
                          'mc-cust-sign-off', 'approver',
                          'mc-cust-users-monitor', 'mep_user_viewer',
                          'mc-cust-users-auditor', 'mep_user_auditor',
                          'mc-cust-users-admin', 'mep_user_editor',
                          'mc-cust-open-systems-identity-users-admin', 'open_systems_identity_user_editor',
                          'mc-cust-open-systems-identity-users-auditor', 'open_systems_identity_user_auditor',
                          'mc-cust-open-systems-identity-users-monitor', 'open_systems_identity_user_viewer'
                   ) rel,
                   l.OIDC_ZITADEL_ID user_id,
                   ucs.company_id
            from auth.USER_COMPANY_SCOPE ucs, auth.USER_ROLE ur, auth.LOGIN2PROFILE l2p, auth.LOGIN l
            where ur.id = v_urole_id
              and ur.NAME in ('mc-cust-access', 'mc-cust-monitor', 'mc-cust-auditor', 'mc-cust-admin',
                              'mc-cust-tp-mgmt', 'mc-cust-prx-config-mgmt', 'mc-cust-fw-config-mgmt',
                              'mc-cust-casb-policy-mgmt', 'mc-cust-mail-config-mgmt', 'mc-cust-api',
                              'mc-cust-api-users-mgmt', 'mc-cust-incident-resp-mgmt', 'mc-cust-cert-mgmt', 'mc-cust-network-admin', 'mc-cust-network-req',
                              'mc-cust-sign-off', 'mc-cust-users-monitor', 'mc-cust-users-auditor', 'mc-cust-users-admin',
                              'mc-cust-open-systems-identity-users-admin', 'mc-cust-open-systems-identity-users-auditor', 'mc-cust-open-systems-identity-users-monitor')
              and l2p.PROFILE_ID = v_profile_id
              and l2p.LOGIN_ID = l.id
              and l.OIDC_ZITADEL_ID is not null
              and ucs.PERMISSION_ID = v_id) loop
      aserto.PublishAsertoAction(
      v_action,
      'user',
      r.user_id,
      r.rel,
      'company',
      r.company_id
      );
    end loop;


    for r in (select DECODE(ur.NAME,
                          'mc-cust-monitor', 'viewer',
                          'mc-cust-auditor', 'auditor',
                          'mc-cust-admin',   'editor',
                          'mc-cust-incident-resp-mgmt', 'ndr_service_handler',
                          'mc-cust-cert-mgmt', 'cert_self_service_manager',
                          'mc-cust-network-admin', 'network_editor',
                          'mc-cust-network-req', 'network_requester',
                          'mc-cust-sign-off', 'approver'
                   ) rel,
                   l.OIDC_ZITADEL_ID user_id,
                   uus.company_unit_id
            from auth.USER_COMPANY_UNIT_SCOPE uus, auth.USER_ROLE ur, auth.LOGIN2PROFILE l2p, auth.LOGIN l
            where ur.id = v_urole_id
              and ur.NAME in ('mc-cust-monitor', 'mc-cust-auditor', 'mc-cust-admin',
                              'mc-cust-incident-resp-mgmt', 'mc-cust-cert-mgmt', 'mc-cust-network-admin', 'mc-cust-network-req', 'mc-cust-sign-off')
              and l2p.PROFILE_ID = v_profile_id
              and l2p.LOGIN_ID = l.id
              and l.OIDC_ZITADEL_ID is not null
              and uus.PERMISSION_ID = v_id) loop
      aserto.PublishAsertoAction(
      v_action,
      'user',
      r.user_id,
      r.rel,
      'company_unit',
      r.company_unit_id
      );
    end loop;


    for r in (select DECODE(ur.NAME,
                          'mc-cust-users-monitor', 'mep_user_viewer',
                          'mc-cust-users-auditor', 'mep_user_auditor',
                          'mc-cust-users-admin', 'mep_user_editor'
                   ) rel,
                   l.OIDC_ZITADEL_ID user_id,
                   uus.user_unit_id
            from auth.USER_UNIT_SCOPE uus, auth.USER_ROLE ur, auth.LOGIN2PROFILE l2p, auth.LOGIN l
            where ur.id = v_urole_id
              and ur.NAME in ('mc-cust-users-monitor', 'mc-cust-users-auditor', 'mc-cust-users-admin')
              and l2p.PROFILE_ID = v_profile_id
              and l2p.LOGIN_ID = l.id
              and l.OIDC_ZITADEL_ID is not null
              and uus.PERMISSION_ID = v_id) loop
      aserto.PublishAsertoAction(
      v_action,
      'user',
      r.user_id,
      r.rel,
      'user_unit',
      r.user_unit_id
      );
    end loop;


    for r in (select DECODE(ur.NAME,
                          'mc-cust-monitor', 'viewer',
                          'mc-cust-auditor', 'auditor',
                          'mc-cust-admin',   'editor',
                          'mc-cust-incident-resp-mgmt', 'ndr_service_handler',
                          'mc-cust-cert-mgmt', 'cert_self_service_manager',
                          'mc-cust-network-admin', 'network_editor',
                          'mc-cust-network-req', 'network_requester'
                   ) rel,
                   l.OIDC_ZITADEL_ID user_id,
                   uss.service_id
            from auth.USER_SERVICE_SCOPE uss, auth.USER_ROLE ur, auth.LOGIN2PROFILE l2p, auth.LOGIN l
            where ur.id = v_urole_id
              and ur.NAME in ('mc-cust-monitor', 'mc-cust-auditor', 'mc-cust-admin',
                              'mc-cust-incident-resp-mgmt', 'mc-cust-cert-mgmt', 'mc-cust-network-admin', 'mc-cust-network-req')
              and l2p.PROFILE_ID = v_profile_id
              and l2p.LOGIN_ID = l.id
              and l.OIDC_ZITADEL_ID is not null
              and uss.PERMISSION_ID = v_id) loop
      aserto.PublishAsertoAction(
      v_action,
      'user',
      r.user_id,
      r.rel,
      'service',
      r.service_id
      );
    end loop;
END;
/

--changeset sys:17 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER auth.t_usrsvcsc_aserto
  BEFORE INSERT OR DELETE ON auth.USER_SERVICE_SCOPE
  FOR each row
DECLARE
  v_perm_id integer;
  v_service_id integer;
  v_action varchar2(16);
BEGIN
  if INSERTING then
    v_action := 'create';
    v_perm_id := :NEW.permission_id;
    v_service_id := :NEW.service_id;
  elsif DELETING then
    v_action := 'delete';
    v_perm_id := :OLD.permission_id;
    v_service_id := :OLD.service_id;
  end if;

  for r in (select DECODE(ur.NAME,
                          'mc-cust-monitor', 'viewer',
                          'mc-cust-auditor', 'auditor',
                          'mc-cust-admin',   'editor',
                          'mc-cust-incident-resp-mgmt', 'ndr_service_handler',
                          'mc-cust-cert-mgmt', 'cert_self_service_manager',
                          'mc-cust-network-admin', 'network_editor',
                          'mc-cust-network-req', 'network_requester') rel,
                   l.OIDC_ZITADEL_ID user_id
            from auth.USER_PERMISSION up, auth.USER_ROLE ur, auth.LOGIN2PROFILE l2p, auth.LOGIN l
            where up.USER_ROLE_ID = ur.id
              and ur.NAME in ('mc-cust-monitor', 'mc-cust-auditor', 'mc-cust-admin',
                              'mc-cust-incident-resp-mgmt', 'mc-cust-cert-mgmt', 'mc-cust-network-admin', 'mc-cust-network-req')
              and l2p.PROFILE_ID = up.PROFILE_ID
              and l2p.LOGIN_ID = l.id
              and l.OIDC_ZITADEL_ID is not null
              and up.id = v_perm_id) loop
      aserto.PublishAsertoAction(
      v_action,
      'user',
      r.user_id,
      r.rel,
      'service',
      v_service_id
      );
    end loop;
END;
/

--changeset sys:18 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER auth.t_usruserusc_aserto
  BEFORE INSERT OR DELETE ON auth.USER_UNIT_SCOPE
  FOR each row
DECLARE
  v_perm_id integer;
  v_userunit_id integer;
  v_action varchar2(16);
BEGIN
  if INSERTING then
    v_action := 'create';
    v_perm_id := :NEW.permission_id;
    v_userunit_id := :NEW.user_unit_id;
  elsif DELETING then
    v_action := 'delete';
    v_perm_id := :OLD.permission_id;
    v_userunit_id := :OLD.user_unit_id;
  end if;

  for r in (select DECODE(ur.NAME,
                          'mc-cust-users-monitor', 'mep_user_viewer',
                          'mc-cust-users-auditor', 'mep_user_auditor',
                          'mc-cust-users-admin', 'mep_user_editor'
                   ) rel,
                   l.OIDC_ZITADEL_ID user_id
            from auth.USER_PERMISSION up, auth.USER_ROLE ur, auth.LOGIN2PROFILE l2p, auth.LOGIN l
            where up.USER_ROLE_ID = ur.id
              and ur.NAME in ('mc-cust-users-monitor', 'mc-cust-users-auditor', 'mc-cust-users-admin')
              and l2p.PROFILE_ID = up.PROFILE_ID
              and l2p.LOGIN_ID = l.id
              and l.OIDC_ZITADEL_ID is not null
              and up.id = v_perm_id) loop
      aserto.PublishAsertoAction(
      v_action,
      'user',
      r.user_id,
      r.rel,
      'user_unit',
      v_userunit_id
      );
    end loop;
END;
/

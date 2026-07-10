--liquibase formatted sql logicalFilePath:pkg/auth_osag_auth_passport.sql
--changeset sys:1 runOnChange:true endDelimiter:/
create or replace package auth.osag_auth_passport is
    -- written by ok@open.ch, January 2002;
    -- copyright 2002-2003 Open Systems AG, Switzerland
    --
    -- Manages the scheme auth - provides function for altering
    -- records - selects are done directly

    -- -------------------------------------------------------------------
    -- NOTE:
    -- Please declare constants, exceptions, and global variables
    -- in the according state package (e.g. OSAG_AUTH_STATE for OSAG_AUTH_PASSPORT
    -- -------------------------------------------------------------------

    -----------------------------------------------------------------------------
    -- add_login2groups: assign a group to a login
    -----------------------------------------------------------------------------
   procedure add_login2groups (
      p_login_id passport_login.id%type,
      p_group_id groups.id%type
   );

    -----------------------------------------------------------------------------
    -- add_alias: add an alias to a login
    -----------------------------------------------------------------------------
   procedure add_alias (
      p_login_id passport_login.id%type,
      p_alias    passport_alias.alias%type,
      p_nocheck  number default 0
   );

    -----------------------------------------------------------------------------
    -- add_softtoken: creates a softtoken
    -----------------------------------------------------------------------------
   procedure add_softtoken (
      p_token_id            out token.id%type,
      p_tokenserial         out token.serial%type,
      p_company_id          token.company_id%type,
      p_softtokenexpiry     token.expirydate%type,
      p_softtokenseed       token.seed%type,
      p_softtoken_validfrom token.validfrom%type
   );

    -----------------------------------------------------------------------------
    -- add_login2tunnelgroup: assign a tunnelgroup to a login
    -----------------------------------------------------------------------------
   procedure add_login2tunnelgroup (
      p_login_id       passport_login.id%type,
      p_tunnelgroup_id tunnelgroup.id%type
   );

    -----------------------------------------------------------------------------
    -- check_login_unique: checks the uniqueness of a login (or alias) across the
    -- same customer
    -----------------------------------------------------------------------------
   function check_login_unique (
      p_login           passport_login.login%type,
      p_homeauthhost_id passport_login.homeauthhost_id%type
   ) return boolean;


    -----------------------------------------------------------------------------
    -- check_email_unique: checks the global uniqueness of an email address (if
    -- it is non-null). Note that this procedure is unused with new Issue AUT-105
    -----------------------------------------------------------------------------
   function check_email_unique (
      p_email stop.passport_contact.email%type
   ) return boolean;


    -----------------------------------------------------------------------------
    -- check_auth_login_email_unique: checks the uniqueness of an email address
    -- in the auth.login.passport table (if it is non-null)
    -----------------------------------------------------------------------------
   function check_auth_login_email_unique (
      p_email auth.passport_login.email%type
   ) return boolean;

    -----------------------------------------------------------------------------
    -- check_auth_email_unique: checks, if the provided email address is unique in table auth.login.passport
    -----------------------------------------------------------------------------
   procedure check_auth_email_unique (
      p_email auth.passport_login.email%type
   );

    -----------------------------------------------------------------------------
    -- check_recent_password: check if the password was recently used by the given
    -- login, but only if the login's authsys has the password_expiry_enabled
    -- attribute set (recently means: the password was already used for one
    -- of the last 5 password changes)
    -----------------------------------------------------------------------------
   procedure check_recent_password (
      p_login_id passport_login.id%type,
      p_password in varchar2
   );

    -----------------------------------------------------------------------------
    -- count_available_authsys: count the available authentication systems for a
    -- login this helps in discovering whether this user can be attached to a
    -- customers auth systems or has to use the default OSAG provided one.
    -----------------------------------------------------------------------------
   function count_available_authsys (
      p_login_id passport_login.id%type
   ) return number;

    -----------------------------------------------------------------------------
    -- count_token_users: count how many logins use a given token
    -----------------------------------------------------------------------------
   function count_token_users (
      p_token_id token.id%type,
      p_login_id passport_login.id%type
   ) return number;

    -----------------------------------------------------------------------------
    -- delete_login: delete a login
    -----------------------------------------------------------------------------
   procedure delete_login (
      p_login_id passport_login.id%type
   );

    -----------------------------------------------------------------------------
    -- delete_login_sync: delete a login synchronized from external source
    -----------------------------------------------------------------------------
   procedure delete_login_sync (
      p_login_id      out passport_login.id%type,
      p_contact_id    out passport_login.contact_id%type,
      p_login         passport_login.login%type,
      p_syncdomain_id syncdomain.id%type
   );

    -----------------------------------------------------------------------------
    -- delete_aliases: delete all aliases for the specified login id.
    -----------------------------------------------------------------------------
   procedure delete_aliases (
      p_login_id passport_login.id%type
   );

    -----------------------------------------------------------------------------
    -- delete_aliases: delete all aliases for the specified login id.
    -----------------------------------------------------------------------------
   procedure delete_alias (
      p_alias passport_alias.alias%type
   );

    -----------------------------------------------------------------------------
    -- delete_login2groups: delete all group assignments from a login
    -----------------------------------------------------------------------------
   procedure delete_login2groups (
      p_login_id passport_login.id%type
   );

    -----------------------------------------------------------------------------
    -- delete_login2tunnelgroup: delete all tunnelgroup assignments from a login
    -----------------------------------------------------------------------------
   procedure delete_login2tunnelgroup (
      p_login_id passport_login.id%type
   );

    -----------------------------------------------------------------------------
    -- encrypt_password: encrypt a plaintext password (MD5 for now)
    -----------------------------------------------------------------------------
   function encrypt_password (
      p_password varchar2
   ) return varchar2;

    -----------------------------------------------------------------------------
    -- hash_password: hashes a password and a given salt using
    -- SHA256(salt + MD5(password))
    -----------------------------------------------------------------------------
   function hash_password (
      p_password varchar2,
      p_salt     varchar2
   ) return passport_login.pwhash%type;

    -----------------------------------------------------------------------------
    -- grant_user_role: grant a role to a login
    -----------------------------------------------------------------------------
   procedure grant_role (
      p_login_id passport_login.id%type,
      p_role_id  role.id%type
   );

    -----------------------------------------------------------------------------
    -- grant_user_role: grant a role to a login
    -----------------------------------------------------------------------------
   procedure grant_user_role (
      p_login_id     passport_login.id%type,
      p_user_role_id user_role.id%type
   );

    -----------------------------------------------------------------------------
    -- insert_login: Inserts a new login (remove after MC 6.5 public release)
    -----------------------------------------------------------------------------
   procedure insert_login (
      p_login_id            out passport_login.id%type,
      p_login               passport_login.login%type,
      p_passwordtype_id     passwordtype.id%type,
      p_password            varchar2,
      p_twofactorenabled    passport_login.twofactorenabled%type,
      p_token_id            token.id%type,
      p_replacementtoken_id token.id%type,
      p_homeauthhost_id     authhost.id%type,
      p_locked              passport_login.locked%type,
      p_maxretries          passport_login.maxretries%type,
      p_firstname           stop.passport_contact.firstname%type,
      p_lastname            stop.passport_contact.lastname%type,
      p_direct              stop.passport_contact.direct%type,
      p_mobile              stop.passport_contact.mobile%type,
      p_home                stop.passport_contact.home%type,
      p_fax                 stop.passport_contact.fax%type,
      p_email               stop.passport_contact.email%type,
      p_authemail           auth.passport_login.email%type,
      p_company_id          stop.company.id%type,
      p_anytunnelgroup      passport_login.anytunnelgroup%type default 0,
      p_passwordexpiry      passport_login.passwordexpiry%type default null,
      p_cost_center_id      mss.cost_center.id%type default null,
      p_function            stop.passport_contact.function%type default null,
      p_comments            stop.passport_contact.comments%type default null,
      p_authtype_id         auth.authtype.id%type,
      p_smsauthnumber       passport_login.smsauthnumber%type
   );

    -----------------------------------------------------------------------------
    -- insert_login_sync: Inserts a new login synchronized from external source
    -----------------------------------------------------------------------------
   procedure insert_login_sync (
      p_contact_id           out stop.passport_contact.id%type,
      p_login_id             out passport_login.id%type,
      p_login                passport_login.login%type,
      p_homeauthhost_id      authhost.id%type,
      p_maxretries           passport_login.maxretries%type,
      p_passwordtype_id      passport_login.passwordtype_id%type,
      p_password             varchar2,
      p_passwordexpiryoffset authsys.passwordexpiryoffset%type,
      p_twofactorenabled     passport_login.twofactorenabled%type,
      p_locked               passport_login.locked%type,
      p_firstname            stop.passport_contact.firstname%type,
      p_lastname             stop.passport_contact.lastname%type,
      p_direct               stop.passport_contact.direct%type,
      p_mobile               stop.passport_contact.mobile%type,
      p_home                 stop.passport_contact.home%type,
      p_fax                  stop.passport_contact.fax%type,
      p_email                stop.passport_contact.email%type,
      p_authemail            auth.passport_login.email%type,
      p_syncdomain_id        auth.syncdomain.id%type,
      p_synctype             auth.synctype.short%type,
      p_sid                  stop.passport_contact_sync.sid%type,
      p_guid                 stop.passport_contact_sync.guid%type,
      p_domain               stop.passport_contact_sync.domain%type,
      p_usnchanged           stop.passport_contact_sync.usnchanged%type,
      p_cost_center_id       mss.cost_center.id%type default null,
      p_function             stop.passport_contact.function%type default null,
      p_merge                number default 0,
      p_comments             stop.passport_contact.comments%type default null,
      p_authtype_id          auth.authtype.id%type,
      p_smsauthnumber        passport_login.smsauthnumber%type,
      p_softtokenseed        token.seed%type default null,
      p_softtokenexpiry      varchar2 default null,
      p_softtoken_validfrom  varchar2 default null
   );

    -----------------------------------------------------------------------------
    -- insert_login_sync2: Inserts a new login synchronized from external source (AUT-927: with distinguishedname)
    -----------------------------------------------------------------------------
   procedure insert_login_sync2 (
      p_contact_id           out stop.passport_contact.id%type,
      p_login_id             out passport_login.id%type,
      p_login                passport_login.login%type,
      p_homeauthhost_id      authhost.id%type,
      p_maxretries           passport_login.maxretries%type,
      p_passwordtype_id      passport_login.passwordtype_id%type,
      p_password             varchar2,
      p_passwordexpiryoffset authsys.passwordexpiryoffset%type,
      p_twofactorenabled     passport_login.twofactorenabled%type,
      p_locked               passport_login.locked%type,
      p_firstname            stop.passport_contact.firstname%type,
      p_lastname             stop.passport_contact.lastname%type,
      p_direct               stop.passport_contact.direct%type,
      p_mobile               stop.passport_contact.mobile%type,
      p_home                 stop.passport_contact.home%type,
      p_fax                  stop.passport_contact.fax%type,
      p_email                stop.passport_contact.email%type,
      p_authemail            auth.passport_login.email%type,
      p_syncdomain_id        auth.syncdomain.id%type,
      p_synctype             auth.synctype.short%type,
      p_sid                  stop.passport_contact_sync.sid%type,
      p_guid                 stop.passport_contact_sync.guid%type,
      p_domain               stop.passport_contact_sync.domain%type,
      p_usnchanged           stop.passport_contact_sync.usnchanged%type,
      p_cost_center_id       mss.cost_center.id%type default null,
      p_function             stop.passport_contact.function%type default null,
      p_merge                number default 0,
      p_comments             stop.passport_contact.comments%type default null,
      p_authtype_id          auth.authtype.id%type,
      p_smsauthnumber        passport_login.smsauthnumber%type,
      p_softtokenseed        token.seed%type default null,
      p_softtokenexpiry      varchar2 default null,
      p_softtoken_validfrom  varchar2 default null,
      p_distinguishedname    stop.passport_contact_sync.distinguishedname%type default null
   );

    -----------------------------------------------------------------------------
    -- is_dirty: Returns dirty status of an authentication system
    -----------------------------------------------------------------------------
   function is_dirty (
      p_authsys_id authsys.id%type
   ) return number;

    -----------------------------------------------------------------------------
    -- lock_login: lock a login
    -----------------------------------------------------------------------------
   procedure lock_login (
      p_login_id passport_login.id%type
   );

    -----------------------------------------------------------------------------
    -- set_authsys_dirty: sets an entire authentication system to dirty status
    -----------------------------------------------------------------------------
   procedure set_authsys_dirty (
      p_authsys_id authsys.id%type
   );

    -----------------------------------------------------------------------------
    -- set_password: set a login's password
    -----------------------------------------------------------------------------
   procedure set_password (
      p_login_id               passport_login.id%type,
      p_password               varchar2,
      p_update_password_expiry boolean default false,
      p_update_recent_password boolean default true,
      p_password_expiry_offset authsys.passwordexpiryoffset%type default null,
      p_check_password         boolean default false
   );

    -----------------------------------------------------------------------------
    -- unlock_login: unlock a login
    -----------------------------------------------------------------------------
   procedure unlock_login (
      p_login_id passport_login.id%type
   );

    -----------------------------------------------------------------------------
    -- update_authsys: update an authentication system
    -----------------------------------------------------------------------------
   procedure update_authsys (
      p_authsys_id authsys.id%type
   );

    -----------------------------------------------------------------------------
    -- update_authsys_for_login: update the authentication system the login
    -- belongs to
    -----------------------------------------------------------------------------
   procedure update_authsys_for_login (
      p_login_id passport_login.id%type
   );

    -----------------------------------------------------------------------------
    -- sync_domain: synchronize a sync domain
    -----------------------------------------------------------------------------
   procedure sync_domain (
      p_syncdomain_id syncdomain.id%type,
      p_scheduled     boolean default false,
      p_force         boolean default false
   );

    -- sync_domain_scheduler: scheduler for domain synchronization
    -----------------------------------------------------------------------------
   procedure sync_domain_scheduler;

    -----------------------------------------------------------------------------
    -- update_login: Updates a login (remove after MC 6.5 public release)
    -----------------------------------------------------------------------------
   procedure update_login (
      p_login_id            passport_login.id%type,
      p_login               passport_login.login%type,
      p_passwordtype_id     passwordtype.id%type,
      p_password            varchar2,
      p_twofactorenabled    passport_login.twofactorenabled%type,
      p_token_id            token.id%type,
      p_replacementtoken_id token.id%type,
      p_homeauthhost_id     authhost.id%type,
      p_locked              passport_login.locked%type,
      p_maxretries          passport_login.maxretries%type,
      p_firstname           stop.passport_contact.firstname%type,
      p_lastname            stop.passport_contact.lastname%type,
      p_direct              stop.passport_contact.direct%type,
      p_mobile              stop.passport_contact.mobile%type,
      p_home                stop.passport_contact.home%type,
      p_fax                 stop.passport_contact.fax%type,
      p_email               stop.passport_contact.email%type,
      p_authemail           auth.passport_login.email%type,
      p_company_id          stop.company.id%type default null,
      p_anytunnelgroup      passport_login.anytunnelgroup%type default 0,
      p_passwordexpiry      passport_login.passwordexpiry%type default null,
      p_cost_center_id      mss.cost_center.id%type default null,
      p_function            stop.passport_contact.function%type default null,
      p_comments            stop.passport_contact.comments%type default null,
      p_smsauthnumber       passport_login.smsauthnumber%type
   );

    -----------------------------------------------------------------------------
    -- update_login_sync: Updates a login synchronized from external source
    -----------------------------------------------------------------------------
   procedure update_login_sync (
      p_contact_id     out stop.passport_contact.id%type,
      p_login_id       passport_login.id%type,
      p_login          passport_login.login%type,
      p_password       varchar2,
      p_locked         passport_login.locked%type,
      p_firstname      stop.passport_contact.firstname%type,
      p_lastname       stop.passport_contact.lastname%type,
      p_direct         stop.passport_contact.direct%type,
      p_mobile         stop.passport_contact.mobile%type,
      p_home           stop.passport_contact.home%type,
      p_fax            stop.passport_contact.fax%type,
      p_email          stop.passport_contact.email%type,
      p_authemail      auth.passport_login.email%type,
      p_syncdomain_id  auth.syncdomain.id%type,
      p_domain         stop.passport_contact_sync.domain%type,
      p_usnchanged     stop.passport_contact_sync.usnchanged%type,
      p_cost_center_id mss.cost_center.id%type default null,
      p_function       stop.passport_contact.function%type default null,
      p_comments       stop.passport_contact.comments%type default null,
      p_smsauthnumber  passport_login.smsauthnumber%type
   );

    -----------------------------------------------------------------------------
    -- update_login_sync2: Updates a login synchronized from external source (AUT-927: with distinguishedname)
    -----------------------------------------------------------------------------
   procedure update_login_sync2 (
      p_contact_id        out stop.passport_contact.id%type,
      p_login_id          passport_login.id%type,
      p_login             passport_login.login%type,
      p_password          varchar2,
      p_locked            passport_login.locked%type,
      p_firstname         stop.passport_contact.firstname%type,
      p_lastname          stop.passport_contact.lastname%type,
      p_direct            stop.passport_contact.direct%type,
      p_mobile            stop.passport_contact.mobile%type,
      p_home              stop.passport_contact.home%type,
      p_fax               stop.passport_contact.fax%type,
      p_email             stop.passport_contact.email%type,
      p_authemail         auth.passport_login.email%type,
      p_syncdomain_id     auth.syncdomain.id%type,
      p_domain            stop.passport_contact_sync.domain%type,
      p_usnchanged        stop.passport_contact_sync.usnchanged%type,
      p_cost_center_id    mss.cost_center.id%type default null,
      p_function          stop.passport_contact.function%type default null,
      p_comments          stop.passport_contact.comments%type default null,
      p_smsauthnumber     passport_login.smsauthnumber%type,
      p_distinguishedname stop.passport_contact_sync.distinguishedname%type default null
   );

    -----------------------------------------------------------------------------
    -- update_login_details: update the login record with details communicated
    --                       from the auth server trough GUMA
    -----------------------------------------------------------------------------
   procedure update_login_details (
      p_login_id   passport_login.id%type,
      p_lastaccept passport_login.lastaccept%type,
      p_lastreject passport_login.lastreject%type,
      p_locked     passport_login.locked%type
   );

    -----------------------------------------------------------------------------
    -- update_login_details2: update the login record with details communicated
    --                        from the auth server trough GUMA
    -----------------------------------------------------------------------------
   procedure update_login_details2 (
      p_login_id            passport_login.id%type,
      p_lastaccept          passport_login.lastaccept%type,
      p_lastreject          passport_login.lastreject%type,
      p_locked              passport_login.locked%type,
      p_token_id            token.id%type default null,
      p_replacementtoken_id token.id%type default null
   );

    -----------------------------------------------------------------------------
    -- update_token_details: update the token record with details communicated
    --                       from the auth server trough GUMA
    -----------------------------------------------------------------------------
   procedure update_token_details (
      p_token_id   token.id%type,
      p_actercount token.actercount%type,
      p_seciddrift token.seciddrift%type,
      p_dpblob     token.dpblob%type
   );

    -----------------------------------------------------------------------------
    -- update_token_details2: update the token record with details communicated
    --                       from the auth server trough GUMA
    -----------------------------------------------------------------------------
   procedure update_token_details2 (
      p_token_id token.id%type,
      p_details  varchar2
   );

    -----------------------------------------------------------------------------
    -- reset_dpblob: reset a Vasco Digipass token blob to enable clock
    --               synchronisation
    -----------------------------------------------------------------------------
   procedure reset_dpblob (
      p_token_id in token.id%type
   );

    -----------------------------------------------------------------------------
    -- reset_totp: reset a time based OATH token to enable clock
    --               synchronisation
    -----------------------------------------------------------------------------
   procedure reset_totp (
      p_token_id in token.id%type
   );

    -----------------------------------------------------------------------------
    -- reset_token: reset a time based token to enable clock
    --              synchronisation
    -----------------------------------------------------------------------------
   procedure reset_token (
      p_token_id in token.id%type
   );

    -----------------------------------------------------------------------------
    -- unlock_dptoken: unlock PIN locked Vasco Digipass token
    -----------------------------------------------------------------------------
   procedure unlock_dptoken (
      p_token_id      in token.id%type,
      p_random_number in varchar2,
      p_unlock_code   out varchar2
   );

    -----------------------------------------------------------------------------
    -- delete_contact: delete a contact given its id
    --                 This procedure does not check any referential constraints
    -----------------------------------------------------------------------------
   procedure delete_contact (
      p_contact_id in stop.passport_contact.id%type
   );

    -----------------------------------------------------------------------------
    -- add_auth_secret: add an auth secret to an auth system. Replaces any existing entries
    -- This procedure exists as we don't want to expose access to auth.authsecret to other users
    -----------------------------------------------------------------------------
   procedure add_auth_secret (
      p_authsys_id authsys.id%type,
      p_secret     varchar2
   );

end osag_auth_passport;
/
--changeset sys:2 runOnChange:true
create or replace public synonym osag_auth_passport for auth.osag_auth_passport;

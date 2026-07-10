-------------------------------------------------------------------------------
--
-- create_mat_views.sql: Create materialized views for the auth schema
--
-- written by cl@open.ch, October 2007;
-- copyright 2007 Open Systems AG, Switzerland
-------------------------------------------------------------------------------

-- materialized view for service access in rls
-- needs the two materialized view logs on
-- - AUTH.PERMISSION
-- - MSS.SERVICE
-- magic numbers: role_id 1001 is mc-cust-admin, 1002 is mc-cust-auditor, 1003 is mc-cust-monitor
-- using noparallel mode as read performance in parallel mode is very poor (tested with v12.1.0.2.0)
CREATE MATERIALIZED VIEW AUTH.MV_SERVICE_ACCESS
            NOPARALLEL
            BUILD IMMEDIATE
    REFRESH FAST ON COMMIT
AS
(
-- company scope
SELECT 'CS' mv_marker, s.rowid s_rowid, p.rowid p_rowid, NULL c_rowid, cs.rowid cs_rowid, NULL cus_rowid, NULL uss_rowid, f.rowid f_rowid, l2f.rowid l2f_rowid,
       l2f.login_id login_id,
       CASE
           WHEN p.user_role_id = 1001 then 2
           WHEN p.user_role_id = 1002 then 15
           WHEN p.user_role_id = 1003 then 1
           ELSE -1
           END role_id, s.id service_id, s.company_id service_company_id
FROM auth.user_permission p, auth.profile f, auth.login2profile l2f, mss.service s,
     auth.user_company_scope cs
WHERE p.user_role_id IN (1001,1002,1003) AND p.profile_id = f.id AND f.id = l2f.profile_id
  AND p.id = cs.permission_id
  AND cs.company_id = s.company_id
UNION ALL
-- company unit scope
SELECT 'CUS' mv_marker, s.rowid s_rowid, p.rowid p_rowid, c.rowid c_rowid, NULL cs_rowid, cus.rowid cus_rowid, NULL uss_rowid, f.rowid f_rowid, l2f.rowid l2f_rowid,
       l2f.login_id login_id,
       CASE
           WHEN p.user_role_id = 1001 then 2
           WHEN p.user_role_id = 1002 then 15
           WHEN p.user_role_id = 1003 then 1
           ELSE -1
           END role_id, s.id service_id, s.company_id service_company_id
FROM auth.user_permission p, auth.profile f, auth.login2profile l2f, mss.service s, stop.company c, auth.user_company_unit_scope cus
WHERE p.user_role_id IN (1001,1002,1003) AND p.profile_id = f.id AND f.id = l2f.profile_id AND c.id = s.company_id
  AND p.id = cus.permission_id
  AND (
        (cus.company_unit_id = s.company_unit_id)
        OR (s.company_unit_id IS NULL AND cus.company_unit_id = c.default_company_unit_id)
    )
UNION ALL
-- service scope
SELECT 'USS' mv_marker, s.rowid s_rowid, p.rowid p_rowid, NULL c_rowid, NULL cs_rowid, NULL cus_rowid, uss.rowid uss_rowid, f.rowid f_rowid, l2f.rowid l2f_rowid,
       l2f.login_id login_id,
       CASE
           WHEN p.user_role_id = 1001 then 2
           WHEN p.user_role_id = 1002 then 15
           WHEN p.user_role_id = 1003 then 1
           ELSE -1
           END role_id, s.id service_id, s.company_id service_company_id
FROM auth.user_permission p, auth.profile f, auth.login2profile l2f, mss.service s,
     auth.user_service_scope uss
WHERE p.user_role_id IN (1001,1002,1003) AND p.profile_id = f.id AND f.id = l2f.profile_id
  AND p.id = uss.permission_id
  AND uss.service_id = s.id
    );


CREATE INDEX AUTH.IDX_MV_SERVICE_R_ROLE_LOGINCMP ON AUTH.MV_SERVICE_ACCESS (SERVICE_ID, LOGIN_ID, ROLE_ID, SERVICE_COMPANY_ID);
CREATE INDEX AUTH.IDX_MV_SERVICE_ACCESS_R_LOGIN ON AUTH.MV_SERVICE_ACCESS (LOGIN_ID);

-- magic numbers: role_id 3002 is mc-cust-users-admin, 3005 is mc-cust-users-monitor
-- using noparallel mode as read performance in parallel mode is very poor (tested with v12.1.0.2.0)
CREATE MATERIALIZED VIEW AUTH.MV_USER_UNIT_ACCESS
            NOPARALLEL
            BUILD IMMEDIATE
    REFRESH FAST ON COMMIT
AS
-- company scope
SELECT 'CS' mv_marker, p.rowid p_rowid, u.rowid u_rowid, cs.rowid cs_rowid, NULL uus_rowid, f.rowid f_rowid, l2f.rowid l2f_rowid,
       l2f.login_id login_id,
       CASE
           WHEN p.user_role_id = 3002 then 11
           WHEN p.user_role_id = 3005 then 12
           ELSE -1
           END
           role_id, u.id user_unit_id, u.company_id company_id
FROM auth.user_permission p, auth.profile f, auth.login2profile l2f, auth.user_unit u, auth.user_company_scope cs
WHERE p.user_role_id IN (3002,3005) AND p.profile_id = f.id AND f.id = l2f.profile_id
  AND p.id = cs.permission_id
  AND cs.company_id = u.company_id
UNION ALL
-- user unit
SELECT 'UUS' mv_marker, p.rowid p_rowid, u.rowid u_rowid, NULL cs_rowid, uus.rowid uus_rowid, f.rowid f_rowid, l2f.rowid l2f_rowid,
       l2f.login_id login_id,
       CASE
           WHEN p.user_role_id = 3002 then 11
           WHEN p.user_role_id = 3005 then 12
           ELSE -1
           END
           role_id, u.id user_unit_id, u.company_id company_id
FROM auth.user_permission p, auth.profile f, auth.login2profile l2f, auth.user_unit u, auth.user_unit_scope uus
WHERE p.user_role_id IN (3002,3005) AND p.profile_id = f.id AND f.id = l2f.profile_id
  AND p.id = uus.permission_id
  AND uus.user_unit_id = u.id;


CREATE INDEX AUTH.IDX_MV_USER_UNIT_R_ROLE_LOGIN ON AUTH.MV_USER_UNIT_ACCESS (USER_UNIT_ID, LOGIN_ID, ROLE_ID);

-- materialized view that maps the new user permissions onto the old permissions table
-- for all new mc-cust-* roles that have an equivalent old role
-- using noparallel mode as read performance in parallel mode is very poor (tested with v12.1.0.2.0)
CREATE MATERIALIZED VIEW AUTH.PERMISSION
            NOPARALLEL
            BUILD IMMEDIATE
    REFRESH FAST ON COMMIT
AS
(
-- Company part
SELECT
    'CS' mv_marker, p.rowid p_rowid, cs.rowid cs_rowid, NULL cus_rowid, NULL uus_rowid, NULL uss_rowid, r.rowid r_rowid, f.rowid f_rowid, l2f.rowid l2f_rowid,
    TO_NUMBER(9 || cs.company_id || p.id) id,
    l2f.login_id login_id,
    CASE
        WHEN r.id = 200 then 6     -- mc-osag-monitor            =>   mc-osag-monitor
        WHEN r.id = 201 then 5     -- mc-osag-admin              =>   mc-osag-admin
        WHEN r.id = 1003 then 1     -- mc-cust-monitor           =>   mc-cust-monitor
        WHEN r.id = 1000 then 3     -- mc-cust-access            =>   mc-cust-radius
        WHEN r.id = 1001 then 2     -- mc-cust-admin             =>   mc-cust-admin
        WHEN r.id = 1002 then 15    -- mc-cust-auditor           =>   mc-cust-auditor
        WHEN r.id = 3005 then 12    -- mc-cust-users-monitor     =>   mc-cust-users-monitor
        WHEN r.id = 3002 then 11    -- mc-cust-users-admin       =>   mc-cust-users-admin
        WHEN r.id = 3003 then 16    -- mc-cust-users-auditor     =>   mc-cust-users-auditor
        WHEN r.id = 5002 then 21    -- mc-cust-open-systems-identity-users-admin     =>   mc-cust-open-systems-identity-users-admin
        WHEN r.id = 5003 then 26    -- mc-cust-open-systems-identity-users-auditor     =>   mc-cust-open-systems-identity-users-auditor
        WHEN r.id = 5005 then 22    -- mc-cust-open-systems-identity-users-monitor     =>   mc-cust-open-systems-identity-users-monitor
        ELSE -1
        END role_id,
    cs.company_id company_id,
    NULL company_unit_id,
    NULL user_unit_id,
    NULL service_id
FROM auth.user_permission p, auth.user_company_scope cs, auth.user_role r, auth.profile f, auth.login2profile l2f
WHERE p.user_role_id = r.id AND p.profile_id = f.id AND l2f.profile_id = f.id
  AND p.id = cs.permission_id
  AND r.id IN (200,201,1000,1001,1002,1003,3005,3002,3003,5002,5003,5005)
UNION ALL
-- Company unit part
SELECT
    'CUS' mv_marker, p.rowid p_rowid, NULL cs_rowid, cus.rowid cus_rowid, NULL uus_rowid, NULL uss_rowid, r.rowid r_rowid, f.rowid f_rowid, l2f.rowid l2f_rowid,
    TO_NUMBER(8 || cus.company_unit_id || p.id) id,
    l2f.login_id login_id,
    CASE
        WHEN r.id = 200 then 6     -- mc-osag-monitor            =>   mc-osag-monitor
        WHEN r.id = 201 then 5     -- mc-osag-admin              =>   mc-osag-admin
        WHEN r.id = 1003 then 1     -- mc-cust-monitor           =>   mc-cust-monitor
        WHEN r.id = 1000 then 3     -- mc-cust-access            =>   mc-cust-radius
        WHEN r.id = 1001 then 2     -- mc-cust-admin             =>   mc-cust-admin
        WHEN r.id = 1002 then 15    -- mc-cust-auditor           =>   mc-cust-auditor
        WHEN r.id = 3005 then 12    -- mc-cust-users-monitor     =>   mc-cust-users-monitor
        WHEN r.id = 3002 then 11    -- mc-cust-users-admin       =>   mc-cust-users-admin
        WHEN r.id = 3003 then 16    -- mc-cust-users-auditor     =>   mc-cust-users-auditor
        WHEN r.id = 5002 then 21    -- mc-cust-open-systems-identity-users-admin     =>   mc-cust-open-systems-identity-users-admin
        WHEN r.id = 5003 then 26    -- mc-cust-open-systems-identity-users-auditor     =>   mc-cust-open-systems-identity-users-auditor
        WHEN r.id = 5005 then 22    -- mc-cust-open-systems-identity-users-monitor     =>   mc-cust-open-systems-identity-users-monitor
        ELSE -1
        END role_id,
    NULL company_id,
    cus.company_unit_id company_unit_id,
    NULL user_unit_id,
    NULL service_id
FROM auth.user_permission p, auth.user_company_unit_scope cus, auth.user_role r, auth.profile f, auth.login2profile l2f
WHERE p.user_role_id = r.id AND p.profile_id = f.id AND l2f.profile_id = f.id
  AND p.id = cus.permission_id
  AND r.id IN (200,201,1000,1001,1002,1003,3005,3002,3003,5002,5003,5005)
UNION ALL
-- User unit part
SELECT
    'UUS' mv_marker, p.rowid p_rowid, NULL cs_rowid, NULL cus_rowid, uus.rowid uus_rowid, NULL uss_rowid, r.rowid r_rowid, f.rowid f_rowid, l2f.rowid l2f_rowid,
    TO_NUMBER(7 || uus.user_unit_id || p.id) id,
    l2f.login_id login_id,
    CASE
        WHEN r.id = 200 then 6     -- mc-osag-monitor            =>   mc-osag-monitor
        WHEN r.id = 201 then 5     -- mc-osag-admin              =>   mc-osag-admin
        WHEN r.id = 1003 then 1     -- mc-cust-monitor           =>   mc-cust-monitor
        WHEN r.id = 1000 then 3     -- mc-cust-access            =>   mc-cust-radius
        WHEN r.id = 1001 then 2     -- mc-cust-admin             =>   mc-cust-admin
        WHEN r.id = 1002 then 15    -- mc-cust-auditor           =>   mc-cust-auditor
        WHEN r.id = 3005 then 12    -- mc-cust-users-monitor     =>   mc-cust-users-monitor
        WHEN r.id = 3002 then 11    -- mc-cust-users-admin       =>   mc-cust-users-admin
        WHEN r.id = 3003 then 16    -- mc-cust-users-auditor     =>   mc-cust-users-auditor
        WHEN r.id = 5002 then 21    -- mc-cust-open-systems-identity-users-admin     =>   mc-cust-open-systems-identity-users-admin
        WHEN r.id = 5003 then 26    -- mc-cust-open-systems-identity-users-auditor     =>   mc-cust-open-systems-identity-users-auditor
        WHEN r.id = 5005 then 22    -- mc-cust-open-systems-identity-users-monitor     =>   mc-cust-open-systems-identity-users-monitor
        ELSE -1
        END role_id,
    NULL company_id,
    NULL company_unit_id,
    uus.user_unit_id user_unit_id,
    NULL service_id
FROM auth.user_permission p, auth.user_unit_scope uus, auth.user_role r, auth.profile f, auth.login2profile l2f
WHERE p.user_role_id = r.id AND p.profile_id = f.id AND l2f.profile_id = f.id
  AND p.id = uus.permission_id
  AND r.id IN (200,201,1000,1001,1002,1003,3005,3002,3003,5002,5003,5005)
UNION ALL
-- Service part
SELECT
    'USS' mv_marker, p.rowid p_rowid, NULL cs_rowid, NULL cus_rowid, NULL uus_rowid, uss.rowid uss_rowid, r.rowid r_rowid, f.rowid f_rowid, l2f.rowid l2f_rowid,
    TO_NUMBER(6 || uss.service_id || p.id) id,
    l2f.login_id login_id,
    CASE
        WHEN r.id = 200 then 6     -- mc-osag-monitor            =>   mc-osag-monitor
        WHEN r.id = 201 then 5     -- mc-osag-admin              =>   mc-osag-admin
        WHEN r.id = 1003 then 1     -- mc-cust-monitor           =>   mc-cust-monitor
        WHEN r.id = 1000 then 3     -- mc-cust-access            =>   mc-cust-radius
        WHEN r.id = 1001 then 2     -- mc-cust-admin             =>   mc-cust-admin
        WHEN r.id = 1002 then 15    -- mc-cust-auditor           =>   mc-cust-auditor
        WHEN r.id = 3005 then 12    -- mc-cust-users-monitor     =>   mc-cust-users-monitor
        WHEN r.id = 3002 then 11    -- mc-cust-users-admin       =>   mc-cust-users-admin
        WHEN r.id = 3003 then 16    -- mc-cust-users-auditor     =>   mc-cust-users-auditor
        WHEN r.id = 5002 then 21    -- mc-cust-open-systems-identity-users-admin     =>   mc-cust-open-systems-identity-users-admin
        WHEN r.id = 5003 then 26    -- mc-cust-open-systems-identity-users-auditor     =>   mc-cust-open-systems-identity-users-auditor
        WHEN r.id = 5005 then 22    -- mc-cust-open-systems-identity-users-monitor     =>   mc-cust-open-systems-identity-users-monitor
        ELSE -1
        END role_id,
    NULL company_id,
    NULL company_unit_id,
    NULL user_unit_id,
    uss.service_id service_id
FROM auth.user_permission p, auth.user_service_scope uss, auth.user_role r, auth.profile f, auth.login2profile l2f
WHERE p.user_role_id = r.id AND p.profile_id = f.id AND l2f.profile_id = f.id
  AND p.id = uss.permission_id
  AND r.id IN (200,201,1000,1001,1002,1003,3005,3002,3003,5002,5003,5005)
    );


CREATE INDEX AUTH.IDX_MV_PERMISSION_ROLE_LOGIN ON AUTH.PERMISSION (LOGIN_ID, ROLE_ID);

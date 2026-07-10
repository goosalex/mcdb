DO
$do$
    DECLARE
        v_user VARCHAR = 'report';
        v_admin VARCHAR ='postgresadmin';
    BEGIN
        IF
            EXISTS (SELECT
                    FROM pg_catalog.pg_roles
                    WHERE rolname = v_user) THEN
            RAISE
                NOTICE 'Role v_user already exists. Skipping.';
        ELSE	EXECUTE format('CREATE ROLE %I', v_user);
END IF;
EXECUTE format('GRANT %I TO %I', v_user, v_admin);
EXECUTE format('CREATE SCHEMA AUTHORIZATION %I', v_user);
EXECUTE format('ALTER ROLE %I SET search_path TO %I, public', v_user, v_user);
END 
$do$;

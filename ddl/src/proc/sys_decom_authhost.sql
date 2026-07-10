--liquibase formatted sql logicalFilePath:proc/sys_decom_authhost.sql
--changeset sys:1 runOnChange:true endDelimiter:/
--comment: see https://open-systems.atlassian.net/wiki/x/PgAwJQ
create or replace procedure sys.decomAuthHost(p_company_short VARCHAR2) is
  v_company_id integer;
  v_mep_users integer;
begin
  select c.id into v_company_id from stop.COMPANY c where c.SHORT = p_company_short;

  -- preconditions
  select count(*) into v_mep_users from auth.PASSPORT_LOGIN l where l.COMPANY_ID = v_company_id;
  if v_mep_users > 0 then
    raise_application_error(-20000, 'PASSPORT_LOGIN still contains local MEP users');
  end if;

  for ah in (select h.name, h.active
             from mss.HOST2SERVICE h2s, mss.HOST h, mss.SERVICE s
             where h2s.HOST_ID = h.id
               and h2s.SERVICE_ID = s.id
               and s.COMPANY_ID = v_company_id
               and s.SERVICE_TYPE_ID = 4 -- auth
    ) loop
      if ah.active = 1 then
        raise_application_error(-20001, 'auth service is still active '|| ah.name);
      end if;
    end loop;

  for ah in (select h.name, h.active
             from mss.HOST2SERVICE h2s, mss.HOST h, mss.SERVICE s, auth.AUTHHOST a
             where h2s.HOST_ID = h.id
               and h2s.SERVICE_ID = s.id
               and s.COMPANY_ID = v_company_id
               and a.HOST_ID = h.id
    ) loop
      if ah.active = 1 then
        raise_application_error(-20002, 'authhost is still active '|| ah.name);
      end if;
    end loop;

  for ah in (select sd.NAME syncdom, h.name, h.active
             from auth.SYNCDOMAIN sd, auth.AUTHHOST ah, auth.AUTHHOST2AUTHSYS a2a, auth.AUTHSYS asys, mss.HOST h
             where sd.DEFAULTHOMEAUTHHOST_ID =  ah.id
               and ah.HOST_ID = h.id
               and a2a.AUTHHOST_ID = ah.id
               and sd.AUTHSYS_ID =  a2a.AUTHSYS_ID
               and asys.id = sd.AUTHSYS_ID
               and asys.COMPANY_ID = v_company_id) loop
      if ah.active = 1 then
        raise_application_error(-20002, 'authhost of sync domain '|| ah.syncdom  ||' is still active '|| ah.name);
      end if;
    end loop;

  -- remove sync domain
  for sd in (select distinct sd.id, sd.NAME
             from auth.SYNCDOMAIN sd, auth.AUTHHOST ah, auth.AUTHHOST2AUTHSYS a2a, auth.AUTHSYS asys
             where sd.DEFAULTHOMEAUTHHOST_ID =  ah.id
               and a2a.AUTHHOST_ID = ah.id
               and sd.AUTHSYS_ID =  a2a.AUTHSYS_ID
               and asys.id = sd.AUTHSYS_ID
               and asys.COMPANY_ID = v_company_id) loop
      delete from stop.PASSPORT_CONTACT_SYNC where SYNCDOMAIN_ID = sd.id;
      delete from auth.SYNCDOMAIN where id = sd.id;
    end loop;

  -- remove authhosts
  for ah in (select a.id, h.id host_id, h.name
             from mss.HOST2SERVICE h2s, mss.HOST h, mss.SERVICE s, auth.AUTHHOST a
             where h2s.HOST_ID = h.id
               and h2s.SERVICE_ID = s.id
               and s.COMPANY_ID = v_company_id
               and a.HOST_ID = h.id
             order by a.BACKUPAUTHHOST_ID nulls last -- fk to authhost

    ) loop
      begin
        delete from auth.AUTHHOST2AUTHSYS a2a where a2a.AUTHHOST_ID = ah.id;
        delete from auth.DIRTYAUTHHOST d where d.AUTHHOST_ID = ah.id;
        delete from auth.SHADOWAUTHHOST2AUTHHOST where AUTHHOST_ID = ah.id;
        delete from auth.SHADOWAUTHHOST where host_id = ah.host_id;
        delete from auth.AUTHHOST where id = ah.id;
      exception
        when others then
          raise_application_error(-20003, 'error deleting '|| ah.name ||': '|| SQLERRM);
      end;
    end loop;

  -- remove authsys
  for s in (select asys.id, asys.NAME
            from auth.authsys asys
            where not exists (select 1 from auth.AUTHHOST2AUTHSYS a2a where a2a.AUTHSYS_ID = asys.id)
              and asys.COMPANY_ID = v_company_id) loop
      -- unlink from CAG
      update mss.CVPN_GROUP cag
      set cag.TUNNELGROUP_ID = NULL
      where cag.TUNNELGROUP_ID is not null
        and exists (select 1 from auth.TUNNELGROUP tg where cag.TUNNELGROUP_ID = tg.id and tg.AUTHSYS_ID = s.id);
      delete from auth.USER_UNIT2TUNNELGROUP uu
      where exists (select 1 from auth.TUNNELGROUP tg where uu.TUNNELGROUP_ID = tg.id and tg.AUTHSYS_ID = s.id);
      delete from auth.TUNNELGROUP tg where tg.AUTHSYS_ID = s.id;
      delete from auth.authsys where id = s.id;
    end loop;

end;
/

-- used by MC user
BEGIN
  DBMS_NETWORK_ACL_ADMIN.CREATE_ACL (
  acl          => 'stop1-network-resolve.xml',
  description  => 'Network access permissions',
  principal    => 'SYSTEM', -- Must be in upper case
  is_grant     => TRUE,
  privilege    => 'resolve');
END;
/

-- allow resolution requests on localhost only
BEGIN
  DBMS_NETWORK_ACL_ADMIN.ASSIGN_ACL (
  acl         => 'stop1-network-resolve.xml',
  host        => 'localhost');
END;
/

-- Connect access for DB users sending out mails

-- used by MSG, OSAG users
BEGIN
  DBMS_NETWORK_ACL_ADMIN.CREATE_ACL (
  acl          => 'stop1-network-connect.xml',
  description  => 'Network access permissions',
  principal    => 'SYS',
  is_grant     => TRUE,
  privilege    => 'connect');
END;
/

-- Local Postfix
BEGIN
  DBMS_NETWORK_ACL_ADMIN.ASSIGN_ACL (
  acl => 'stop1-network-connect.xml',
  host => 'localhost',
  lower_port => 25,
  upper_port => 25);
END;
/

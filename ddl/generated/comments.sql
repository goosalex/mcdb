COMMENT ON COLUMN APPID.APP.SEQ_ID IS 'Optional sequence number (only QuickID applications are ordered)';
COMMENT ON COLUMN APPID.APP.MARK IS 'FWMARK value used to track the application in the netfilter stack';
COMMENT ON COLUMN APPID.APP.PROCERA_COMPATIBLE IS 'Flag to mark QuickID apps that can be run together with Procera apps.';
COMMENT ON COLUMN APPID.APP.AUTOMATIC IS 'Is the application created automatically (e.g. automatic optimized apps).';
COMMENT ON COLUMN APPID.QUICKID_DNS.FQDN IS 'DNS name (incl. wildcards)';
COMMENT ON COLUMN APPID.QUICKID_NET4.MASK IS 'The netmask in CIDR notation.';
COMMENT ON COLUMN APPID.QUICKID_NET6.ADDRESS_1 IS 'The most significant 64bit';
COMMENT ON COLUMN APPID.QUICKID_NET6.ADDRESS_2 IS 'The least signigicant 64bit';
COMMENT ON COLUMN APPID.QUICKID_NET6.MASK IS 'The netmask in CIDR notation.';
COMMENT ON COLUMN APPID.QUICKID_TOS.VALUE IS 'TOS/DSCP value (range 0-255 aka 0x00-0xff)';
COMMENT ON COLUMN APPID.QUICKID_TOS.MASK IS 'TOS/DSCP mask (range 0-255 aka 0x00-0xff)';
COMMENT ON COLUMN AUTH.API_KEY.SALT IS 'Hex representation of the salt. Generate the salt using a cryptographically secure pseudo-random number generator (CSPRNG).';
COMMENT ON COLUMN AUTH.API_KEY.KEY IS 'Hex representation of the API Key. Used to lookup the hashed secret during API authentication. The KEY should be reused when creating a new SECRET_HASH.';
COMMENT ON COLUMN AUTH.API_KEY.SECRET_HASH IS 'Hex representation of the SHA3 hash of salt concatenated with the api secret. The hash is calculated as SHA3(salt + secret) with key length 512. ';
COMMENT ON COLUMN AUTH.API_KEY.CREATIONDATE IS 'The date when the key was generated';
COMMENT ON COLUMN AUTH.AUTHHOST.HOST_ID IS 'the mss.host that corresponds to this auth host';
COMMENT ON COLUMN AUTH.AUTHHOST.BACKUPAUTHHOST_ID IS 'home host that is used if the main host fails';
COMMENT ON COLUMN AUTH.AUTHHOST.BACKUPSTATUS IS '0: backup is off, 1: backup is on (main host failed)';
COMMENT ON COLUMN AUTH.AUTHHOST.UPDATETIMEOUT IS 'Maximum time in seconds that is waited for this host to update its authentication data
when the backup is enabled, this time might be capped at some specific value';
COMMENT ON COLUMN AUTH.AUTHSECRET.SECRET IS 'Shared secret for radius clients which want to authenticate users from this authsys';
COMMENT ON COLUMN AUTH.AUTHSYS.SMSAUTHENABLED IS 'Whether SMS authentication is available on this authsystem.';
COMMENT ON COLUMN AUTH.AUTHSYS.MCDISPLAY IS 'This authsys is visible in mission control users management.';
COMMENT ON COLUMN AUTH.AUTHSYS.ALIASESENABLED IS 'Aliases can be edited in mc users management.';
COMMENT ON COLUMN AUTH.AUTHSYS.PASSWORDEXPIRYENABLED IS 'the password expiry setting can be edited in mc users management';
COMMENT ON COLUMN AUTH.AUTHSYS.PASSWORDEXPIRYOFFSET IS 'Specifies the offset from now, in seconds, that is used to calculate the default
(or next) value for the login.passwordexpiry field (e.g. when creating a new login)
a 0 or negative value means that the password expires immediately
a NULL value means that password expiry is defaulted to off
both (< 0 and NULL) prevent an automatic update of the
expiration end upon password change by the user
';
COMMENT ON COLUMN AUTH.AUTHSYS.PASSWORDONLYALLOWED IS 'it is allowed to have password only authentication type';
COMMENT ON COLUMN AUTH.AUTHSYS.TOKENSMANAGEDEXTERNALLY IS 'token issuing and replacement is not managed via MC UI';
COMMENT ON COLUMN AUTH.AUTHSYS.AUTOEMAILALIASESENABLED IS 'email address are automatically listed as alias if this is switched on. (only applies to synchronized users
(currently...))';
COMMENT ON COLUMN AUTH.AUTHSYS.SYNCUSERUNITSENABLED IS 'Enable/Disable user unit synchronization over AD sync';
COMMENT ON COLUMN AUTH.AUTHSYS.SYNCUSERACCOUNTCONTROLENABLED IS 'Whether synchronizing the "locked" flag is enabled.';
COMMENT ON COLUMN AUTH.AUTHSYS.AUTOMATICPASSWORDRESETENABLED IS 'Whether passwords can be resetted via the automated link-mail process MC-2431';
COMMENT ON COLUMN AUTH.AUTHSYS.ALLOW_WEAK_PASSWORDS IS 'If true, no password strength checks are done.';
COMMENT ON COLUMN AUTH.AUTHSYS.CUSTOM_SOFT_TOKEN_LABEL IS 'If not null this label will be used in the QR code for the soft token activation.';
COMMENT ON COLUMN AUTH.AUTHSYS.TMPPWDONLYEXPIRYOFFSET IS 'value in seconds which is added to the current date to set the users AUTH.LOGIN.TMPPWDONLYEXPIRY field when ticking the checkbox.';
COMMENT ON COLUMN AUTH.AUTHSYS.ALLOWSOFTTOKENREUSE IS 'If true, resending the Software Token activation QR code is allowed.';
COMMENT ON COLUMN AUTH.AUTHSYS.MAXRETRIES IS 'Specifies the max password retry attempts one has before the account becomes locked. This value is transferred to AUTH.LOGIN.MAXRETRIES';
COMMENT ON COLUMN AUTH.AUTHSYS.NOTIFY_CONTACT_CHANGES IS 'Sends out a notification email and SMS on any account change';
COMMENT ON COLUMN AUTH.LOGIN.EMAIL IS 'Email address used for authentication (as login name), if any.';
COMMENT ON COLUMN AUTH.LOGIN.SMSAUTHNUMBER IS 'Mobile phone number for use with SMS authentication, if any.';
COMMENT ON COLUMN AUTH.LOGIN.TOKENREPLACEMENTSTATE_ID IS 'for externally managed tokens; see table TOKENREPLACEMENTSTATE';
COMMENT ON COLUMN AUTH.LOGIN.PASSWORDEXPIRY IS '
if the password expiry date has passed, the user cannot login anymore via the auth server
the password must be changed first in mission control (logging in to mc is still possible)
';
COMMENT ON COLUMN AUTH.LOGIN.LASTTOKENREQUESTDATE IS '
The date when the last token replacement has been requested.
This might happen explicitly in case of externally managed tokens or implicitly in case a token is disabled
and therefore a new one is required.
Note: the date should not be reset once the token is replaced that''s why it is called *last* token request date.
';
COMMENT ON COLUMN AUTH.LOGIN.MANAGING_LOGIN_ID IS 'The login this login is mapped to in the scope of a managing company, i.e.
indicates that this login is managed';
COMMENT ON COLUMN AUTH.LOGIN.AUTHTYPE_ID IS 'The authentication type. Historically points to 1/token and was not used in the portal; it was resurrected for
                 SMS authentication.';
COMMENT ON COLUMN AUTH.LOGIN.PWHASH IS ' Hex representation of the SHA-256 hash of salt concatenated with password. The hash is calculated as sha256(salt + md5(password)).';
COMMENT ON COLUMN AUTH.LOGIN.SALT IS 'Hex representation of the salt. Generate the salt using a cryptographically secure pseudo-random number generator (CSPRNG).';
COMMENT ON COLUMN AUTH.LOGIN.LASTPWCHANGE IS 'The date on which the password has been changed.';
COMMENT ON COLUMN AUTH.LOGIN.TMPPWDONLYEXPIRY IS 'The date when the temporary password expires';
COMMENT ON COLUMN AUTH.LOGIN.CREATIONDATE IS 'The date when a user entry was created, i.e., the first AD sync or the time of user creation in the portal';
COMMENT ON COLUMN AUTH.MEDUSAHOST.HOST_ID IS 'the mss.host that corresponds to this medusa host';
COMMENT ON COLUMN AUTH.MEDUSAHOST.AUTHHOST_ID IS 'the auth.authhost that corresponds to this medusa host';
COMMENT ON COLUMN AUTH.PASSWORDTYPE.ID IS 'Primary key.';
COMMENT ON COLUMN AUTH.PASSWORDTYPE.SHORT IS 'Short identification code which never changes.';
COMMENT ON COLUMN AUTH.PASSWORDTYPE.NAME IS 'Short, descriptive name (for UI display etc)';
COMMENT ON COLUMN AUTH.PASSWORDTYPE.REMOTEVALIDATION IS 'When 1, password authentication is not handled by us and therefore the password may be NULL.';
COMMENT ON COLUMN AUTH.RECENTPASSWORD.SALT IS 'Hex representation of the salt. If a salt is set the password (hash) has been generated using this salt.';
COMMENT ON COLUMN AUTH.SHADOWAUTHHOST.HOST_ID IS 'the mss.host that corresponds to this shadow auth host';
COMMENT ON COLUMN AUTH.SYNCDOMAIN.SYNCPERIOD IS 'synchronization period in seconds.';
COMMENT ON COLUMN AUTH.SYNCDOMAIN.LASTFAILURETRANSACTION_ID IS 'mcaudit record transaction_id of the last failed synchronization run';
COMMENT ON COLUMN AUTH.SYNCDOMAIN.LASTSUCCESSTRANSACTION_ID IS 'mcaudit record transaction_id of the last successful synchronization run';
COMMENT ON COLUMN AUTH.SYNCDOMAIN.MAXDROPRATE IS 'The maximum rate of number_of_deleted_users/number_of_current_users which will be accepted during a sync process
(if exceeded, an exception is thrown). If left empty, the default values apply';
COMMENT ON COLUMN AUTH.TOKEN.COMPANY_ID IS '
The company to which this token has been sold.
If NULL, the token is available for Token Shop sales.
If the company is Open Systems, the token is either for internal
use or is not in use yet and can be transferred to a specific company
when the token is sold.
';
COMMENT ON COLUMN BGP.PEER.ASN IS 'AS Number';
COMMENT ON COLUMN BGP.PEER_GROUP.ASN IS 'AS Number';
COMMENT ON COLUMN BGP.PREFIX.IPV6_ADDRESS_1 IS 'The most significant 64 bits of the address.';
COMMENT ON COLUMN BGP.PREFIX.IPV6_ADDRESS_2 IS 'The least significant 64 bits of the address.';
COMMENT ON COLUMN BGP.ROUTER_CONFIGURATION.ASN IS 'AS Number';
COMMENT ON TABLE CERTS.CERTIFICATE IS 'Stores information about certificates';
COMMENT ON TABLE CERTS.CERTIFICATE_SCOPE_TYPE IS 'Defines certificate scope types';
COMMENT ON TABLE CERTS.CERTIFICATE_USAGE IS 'Describes where the certificate is used';
COMMENT ON TABLE CERTS.CSR IS 'Stores information about certificate signing requests';
COMMENT ON TABLE CERTS.PRIVATE_KEY IS 'Stores private keys for certificates';
COMMENT ON TABLE CERTS.SAN IS 'Stores subject alternative names used by certificates';
COMMENT ON COLUMN CERTS.CERTIFICATE.COMPANY_ID IS 'ID of company associated with the certificate.';
COMMENT ON COLUMN CERTS.CERTIFICATE.TICKET_ID IS 'ID of ticket which tracks creation of the certificate.';
COMMENT ON COLUMN CERTS.CERTIFICATE.SHA256_FINGERPRINT IS 'SHA256 fingerprint of the certificate.';
COMMENT ON COLUMN CERTS.CERTIFICATE.COMMON_NAME IS 'Host name associated with the certificate.';
COMMENT ON COLUMN CERTS.CERTIFICATE.ISSUER IS 'The subject which issued the certificate.';
COMMENT ON COLUMN CERTS.CERTIFICATE.VALID_FROM IS 'The certificate is valid from this time.';
COMMENT ON COLUMN CERTS.CERTIFICATE.VALID_UNTIL IS 'The certificate is valid until this time.';
COMMENT ON COLUMN CERTS.CERTIFICATE.CERTIFICATE IS 'The certificate in PEM format.';
COMMENT ON COLUMN CERTS.CERTIFICATE.KEY_ID IS 'ID of the private key associated with certificate.';
COMMENT ON COLUMN CERTS.CERTIFICATE.INTERMEDIATES IS 'The intermediate certificates in PEM format.';
COMMENT ON COLUMN CERTS.CERTIFICATE.ROOT IS 'The root certificate in PEM format.';
COMMENT ON COLUMN CERTS.CERTIFICATE_SCOPE_TYPE.NAME IS 'Name of the certificate scope type.';
COMMENT ON COLUMN CERTS.CERTIFICATE_SCOPE_TYPE.DESCRIPTION IS 'Description for the certificate scope type.';
COMMENT ON COLUMN CERTS.CERTIFICATE_USAGE.GROUP_ID IS 'ID of the group if the certificate is used on a group scope.';
COMMENT ON COLUMN CERTS.CERTIFICATE_USAGE.CERTIFICATE_ID IS 'The certificate ID.';
COMMENT ON COLUMN CERTS.CERTIFICATE_USAGE.TICKET_ID IS 'ID of ticket which tracks deployment of the certificate.';
COMMENT ON COLUMN CERTS.CERTIFICATE_USAGE.COMPANY_ID IS 'ID of the company if the certificate is used on a company scope.';
COMMENT ON COLUMN CERTS.CERTIFICATE_USAGE.SERVICE_ID IS 'ID of the service if the certificate is used on a service scope.';
COMMENT ON COLUMN CERTS.CERTIFICATE_USAGE.HOST_ID IS 'ID of the host if the certificate is used on a host scope.';
COMMENT ON COLUMN CERTS.CERTIFICATE_USAGE.CERTIFICATE_SCOPE_TYPE_ID IS 'ID of the scope type which the certificate is applied on.';
COMMENT ON COLUMN CERTS.CERTIFICATE_USAGE.CERTIFICATE_SCOPE_NAME IS 'Name of the scope which the certificate is used on.';
COMMENT ON COLUMN CERTS.CSR.COMPANY_ID IS 'ID of company associated with the CSR.';
COMMENT ON COLUMN CERTS.CSR.TICKET_ID IS 'ID of ticket which tracks creation of the CSR.';
COMMENT ON COLUMN CERTS.CSR.TEMPLATE_CERTIFICATE_ID IS 'ID of certificate which was used as a template for CSR.';
COMMENT ON COLUMN CERTS.CSR.MODULUS IS 'RSA key modulus associated with the certificate.';
COMMENT ON COLUMN CERTS.CSR.COMMON_NAME IS 'Host name associated with the certificate.';
COMMENT ON COLUMN CERTS.CSR.CSR IS 'The CSR in PEM format.';
COMMENT ON COLUMN CERTS.CSR.KEY_ID IS 'ID of private key associated with the certificate.';
COMMENT ON COLUMN CERTS.PRIVATE_KEY.KEY IS 'The private key in PEM format.';
COMMENT ON COLUMN CERTS.PRIVATE_KEY.GENERATED IS 'Time when the private key was generated.';
COMMENT ON COLUMN CERTS.SAN.NAME IS 'Alternative name associated with the certificate.';
COMMENT ON COLUMN CERTS.SAN.CERTIFICATE_ID IS 'ID of the certificate associated with SAN.';
COMMENT ON COLUMN CERTS.SAN.CSR_ID IS 'ID of the CSR associated with SAN.';
COMMENT ON COLUMN CHECKLIST.CHECKLIST_ILOS.PRODUCT_NAME IS 'how the ISP entitles this product';
COMMENT ON COLUMN CHECKLIST.CHECKLIST_ILOS.ROUTER_NUMBER IS 'Non-OSAG ID of the router used for this ISP link';
COMMENT ON COLUMN CHECKLIST.CHECKLIST_ILOS.SUPPORT_CONTACT_LASTNAME IS 'The last name of the (24h) support helpdesk of the ISP';
COMMENT ON COLUMN CHECKLIST.CHECKLIST_ILOS.SUPPORT_CONTACT_FIRSTNAME IS 'The first name of the (24h) support helpdesk of the ISP';
COMMENT ON COLUMN CHECKLIST.CHECKLIST_ILOS.SUPPORT_CONTACT_PHONE IS 'The phone number of the (24h) support helpdesk of the ISP';
COMMENT ON COLUMN CHECKLIST.CHECKLIST_ILOS.SUPPORT_CONTACT_EMAIL IS 'The email address of the (24h) support helpdesk of the ISP';
COMMENT ON COLUMN CHECKLIST.CHECKLIST_ILOS.ACCOUNT_MANAGER_LASTNAME IS 'The last name of the person responsible for this account/line';
COMMENT ON COLUMN CHECKLIST.CHECKLIST_ILOS.ACCOUNT_MANAGER_FIRSTNAME IS 'The first name of the person responsible for this account/line';
COMMENT ON COLUMN CHECKLIST.CHECKLIST_ILOS.ACCOUNT_MANAGER_PHONE IS 'The phone number of the person responsible for this account/line';
COMMENT ON COLUMN CHECKLIST.CHECKLIST_ILOS.ACCOUNT_MANAGER_EMAIL IS 'The email address of the person responsible for this account/line';
COMMENT ON COLUMN CHECKLIST.CHECKLIST_ILOS.SLA_AVAILABILITY IS 'Service Level Agreement availability of this link [%](0-100)';
COMMENT ON COLUMN CHECKLIST.CHECKLIST_ILOS.INSTALLATION_FEE IS 'cost for this line';
COMMENT ON COLUMN CHECKLIST.CHECKLIST_ISP_LINK.BANDWIDTH_DOWN IS 'Provided upstream bandwidth [kbit/s] of this link';
COMMENT ON COLUMN CHECKLIST.CHECKLIST_ISP_LINK.BANDWIDTH_UP IS 'Provided downstream bandwidth [kbit/s] of this link';
COMMENT ON TABLE ESP.MC_CENTER IS 'Defines an MC Center, i.e. a center with its own schedule and shift types etc.';
COMMENT ON TABLE ESP.MC_CENTER_CONTACT IS 'Tells which engineers are present/available for which MC Center.';
COMMENT ON TABLE ESP.SPECIAL_DAY IS 'Defines days where a certain day template should be used instead of the default day template of that day.
        A common example are legal holidays or rollout days with additional engineers in MC.';
COMMENT ON COLUMN ESP.MC_CENTER.NAME IS 'Descriptive name.';
COMMENT ON COLUMN ESP.MC_CENTER.ADDRESS_ID IS 'Location of the MC Center.';
COMMENT ON COLUMN ESP.MC_CENTER.PLANNED IS 'Currently not used';
COMMENT ON COLUMN ESP.MC_CENTER.RESET_LEAVING_ENGINEER IS 'If set to true, the workload of all contacts which are currently not assigned to this center should be 0 -> ensured by a nightly cron job.';
COMMENT ON COLUMN ESP.MC_CENTER.CONSIDER_SHIFT_PREFERENCES IS 'If set to true if the shift preferences should be considered when creating generations for this center.';
COMMENT ON COLUMN ESP.MC_CENTER_CONTACT.MC_CENTER_ID IS 'The MC center';
COMMENT ON COLUMN ESP.MC_CENTER_CONTACT.CONTACT_ID IS 'The engineer';
COMMENT ON COLUMN ESP.MC_CENTER_CONTACT.START_DATE IS 'The date from which the engineer is available for this MC center';
COMMENT ON COLUMN ESP.MC_CENTER_CONTACT.END_DATE IS 'The date until which the engineer is available for this MC center. Null means indefinite.';
COMMENT ON COLUMN ESP.SPECIAL_DAY.NAME IS 'Name of the special day - this is displayed in the schedule.';
COMMENT ON COLUMN ESP.SPECIAL_DAY.LEGAL_HOLIDAY IS 'Whether this is a legal holiday (influences off-hour surcharge calculation).';
COMMENT ON COLUMN ESP.SPECIAL_DAY.DAY_DATE IS 'The date of this special day (only the date part matters).';
COMMENT ON TABLE FW.ACTION IS 'Value table for firewall rule target actions';
COMMENT ON TABLE FW.CHE_DNAT_SRC_ZONE IS 'MING destination NAT rule to source zone mapping table';
COMMENT ON TABLE FW.CHE_SNAT_DST_ZONE IS 'MING source NAT rule to destination zone mapping table';
COMMENT ON TABLE FW.CHE_SNAT_SRC_ZONE IS 'MING source NAT rule to source zone mapping table';
COMMENT ON TABLE FW.DESTINATION_NAT_RULE IS 'MING dst NAT rule';
COMMENT ON TABLE FW.DESTINATION_NAT_RULE2TICKET IS 'MING';
COMMENT ON TABLE FW.DNS_OBJECT IS '#MING Holds the definition of a full qualified domain name';
COMMENT ON TABLE FW.EXTERNAL_IP_LIST IS 'Ming external ip list';
COMMENT ON TABLE FW.ICMPV6_TYPE IS 'value table for ICMPv6 type codes and names';
COMMENT ON TABLE FW.ICMP_TYPE IS 'value table for ICMP type codes and names';
COMMENT ON TABLE FW.IP_ADDRESS IS 'Simple IP addresses';
COMMENT ON TABLE FW.IP_GROUP IS 'group of ip-address-defining objects';
COMMENT ON TABLE FW.IP_PROTOCOL IS 'Value table for IP protocol numbers and names';
COMMENT ON TABLE FW.IP_SERVICE2TCP_FLAG IS 'link from ip_service to tcp_flag; multiple connections mean ''AND''';
COMMENT ON TABLE FW.NAT_ACTION IS 'Value table for NAT rule actions';
COMMENT ON TABLE FW.NAT_SECTION IS 'MING NAT section';
COMMENT ON TABLE FW.NAT_SECTION_TYPE IS 'Value table for NAT section types';
COMMENT ON TABLE FW.POLICY IS 'A MING Policy';
COMMENT ON TABLE FW.RECENT_POLICY IS 'Contains all recently openened MING policies';
COMMENT ON TABLE FW.RULE IS '#MING Represents a rule that is part of a subsection';
COMMENT ON TABLE FW.RULE2TICKET IS '#MING';
COMMENT ON TABLE FW.SCOPED_IP_GROUP IS '#MING';
COMMENT ON TABLE FW.SCOPED_IP_GROUP_MEMBER IS '#MING';
COMMENT ON TABLE FW.SCOPED_IP_GROUP_MEMBER_TYPE IS '#MING';
COMMENT ON TABLE FW.SCOPED_IP_GROUP_SCOPE IS '#MING';
COMMENT ON TABLE FW.SECTION IS '
	    #MING  Major part of a policy.Defines a flow by its src and dst zone and holds subsections of rules.
        Defines a policy action and a policy log target (consequently there are no explicit policy rules any longer)
      ';
COMMENT ON TABLE FW.SOURCE_NAT_RULE IS 'MING src NAT rule';
COMMENT ON TABLE FW.SOURCE_NAT_RULE2TICKET IS 'MING';
COMMENT ON TABLE FW.SUB_SECTION IS '
	    #MING Holds the actual rules of a policy. Their ordering is derived from the semantics of the type,
	    cf. above, and within a type on the natural ordering of the involved host/service names.
	  ';
COMMENT ON TABLE FW.SUB_SECTION_TYPE IS '#MING Defines the various types of subsections.';
COMMENT ON TABLE FW.TCP_FLAG IS 'Value table for TCP flags';
COMMENT ON TABLE FW.ZONE IS '
	    Holds the definition of a zone for MING. As these zones are globally defined or at company level,
      they are managed in MCA2 and not in MING itself. A zone figures as source or destination of a section.
	  ';
COMMENT ON TABLE FW.ZONE_MEMBER IS '
        #MING Defines the members, i.e. the interfaces that are in a zone (managed in MCA2).
      ';
COMMENT ON COLUMN FW.CHE_DNAT_SRC_ZONE.DESTINATION_NAT_RULE_ID IS 'FK to destination nat rule';
COMMENT ON COLUMN FW.CHE_DNAT_SRC_ZONE.ZONE_ID IS 'FK to zone to be used as source zone';
COMMENT ON COLUMN FW.CHE_SNAT_DST_ZONE.SOURCE_NAT_RULE_ID IS 'FK to source nat rule';
COMMENT ON COLUMN FW.CHE_SNAT_DST_ZONE.ZONE_ID IS 'FK to zone to be used as destination zone';
COMMENT ON COLUMN FW.CHE_SNAT_SRC_ZONE.SOURCE_NAT_RULE_ID IS 'FK to source nat rule';
COMMENT ON COLUMN FW.CHE_SNAT_SRC_ZONE.ZONE_ID IS 'FK to zone to be used as source zone';
COMMENT ON COLUMN FW.DESTINATION_NAT_RULE.NAT_SECTION_ID IS 'FK to parent section';
COMMENT ON COLUMN FW.DESTINATION_NAT_RULE.TRANS_DST_GROUP_ID IS 'only defined if action == NAT';
COMMENT ON COLUMN FW.DESTINATION_NAT_RULE.TRANS_SERVICE_GROUP_ID IS 'NULL means ORIG (can only be defined if action == NAT)';
COMMENT ON COLUMN FW.DESTINATION_NAT_RULE2TICKET.DESTINATION_NAT_RULE_ID IS 'FK to DESTINATION_NAT_RULE';
COMMENT ON COLUMN FW.DESTINATION_NAT_RULE2TICKET.TICKET_ID IS 'FK to TICKET';
COMMENT ON COLUMN FW.DNS_OBJECT.VERSION IS 'versioning used for local database in the GUI';
COMMENT ON COLUMN FW.DNS_OBJECT.FQDN IS 'DNS name';
COMMENT ON COLUMN FW.DNS_OBJECT.COMPANY_ID IS 'FK to the company, the group belongs to. Shared object if NULL.';
COMMENT ON COLUMN FW.IP_GROUP.AUTOMATIC IS 'The boolean property "automatic" marks ip groups which are created automatically to serve
as source- or destination-groups for firewall rules.';
COMMENT ON COLUMN FW.IP_GROUP_MEMBER.SCOPED_IP_GROUP_MEMBER_ID IS 'FK to a scoped IP group member (if IP group should contain a scoped IP group)';
COMMENT ON COLUMN FW.IP_GROUP_MEMBER.INTERFACE_ADDRESS_ID IS 'FK to a IPv6 Interface Address ';
COMMENT ON COLUMN FW.IP_GROUP_MEMBER.DNS_OBJECT_ID IS 'FK to a DNS Object';
COMMENT ON COLUMN FW.NAT_SECTION.NAT_SECTION_TYPE_ID IS 'NAT Section Type Reference';
COMMENT ON COLUMN FW.NAT_SECTION.SERVICE_ID IS 'FK to mss.service (if type is local overrides or local exceptions, otherwise NULL)';
COMMENT ON COLUMN FW.NAT_SECTION.POLICY_ID IS 'FK to policy this NAT section belongs to';
COMMENT ON COLUMN FW.POLICY.NAME IS 'name of the firewall policy';
COMMENT ON COLUMN FW.POLICY.DESCRIPTION IS 'description of the policy';
COMMENT ON COLUMN FW.POLICY.COMPANY_ID IS 'FK to company the policy belongs to';
COMMENT ON COLUMN FW.RECENT_POLICY.POLICY_ID IS 'The policy that was opened';
COMMENT ON COLUMN FW.RECENT_POLICY.SERVICE_ID IS 'The service that this policy was opened for. May be null';
COMMENT ON COLUMN FW.RECENT_POLICY.CONTACT_ID IS 'The contact that opened the policy';
COMMENT ON COLUMN FW.RECENT_POLICY.TIME IS 'timestamp of the event';
COMMENT ON COLUMN FW.RULE.NAME IS 'optional name';
COMMENT ON COLUMN FW.RULE.SEQ_NO IS 'sequence number of the rule';
COMMENT ON COLUMN FW.RULE.SUB_SECTION_ID IS 'FK to the parent subsection';
COMMENT ON COLUMN FW.RULE.DISABLED IS 'disabled flag';
COMMENT ON COLUMN FW.RULE.SRC_IP_GROUP_ID IS 'FK to source IP group, NULL is any';
COMMENT ON COLUMN FW.RULE.DST_IP_GROUP_ID IS 'FK to dst IP group, NULL is any';
COMMENT ON COLUMN FW.RULE.SERVICE_GROUP_ID IS 'FK to srv group, NULL is any';
COMMENT ON COLUMN FW.RULE.ACTION_ID IS 'FK to action';
COMMENT ON COLUMN FW.RULE.LOG_TARGET_ID IS 'FK to log target';
COMMENT ON COLUMN FW.RULE.LAST_UPDATED IS 'timestamp of last update';
COMMENT ON COLUMN FW.RULE.LAST_UPDATER_ID IS 'FK to contact of last update action';
COMMENT ON COLUMN FW.RULE.COMMENTS IS 'optional comments';
COMMENT ON COLUMN FW.RULE.APP_GROUP_ID IS 'FK to automatic application group, NULL is any.';
COMMENT ON COLUMN FW.RULE2TICKET.RULE_ID IS 'FK to rule';
COMMENT ON COLUMN FW.RULE2TICKET.TICKET_ID IS 'FK ticket';
COMMENT ON COLUMN FW.SCOPED_IP_GROUP.VERSION IS 'version information for local db sync';
COMMENT ON COLUMN FW.SCOPED_IP_GROUP.NAME IS 'name of the scoped IP group';
COMMENT ON COLUMN FW.SCOPED_IP_GROUP.COMPANY_ID IS 'FK to the company, the group belongs to. Note that there are no shared scoped groups';
COMMENT ON COLUMN FW.SCOPED_IP_GROUP.COMMENTS IS 'Optional comment';
COMMENT ON COLUMN FW.SCOPED_IP_GROUP_MEMBER.VERSION IS 'version for the local database of the GUI';
COMMENT ON COLUMN FW.SCOPED_IP_GROUP_MEMBER.SCOPED_IP_GROUP_ID IS 'FK to the scoped IP group';
COMMENT ON COLUMN FW.SCOPED_IP_GROUP_MEMBER.SCOPED_IP_GROUP_MEMBER_TYPE_ID IS 'FK to the type of scope used';
COMMENT ON COLUMN FW.SCOPED_IP_GROUP_MEMBER.SPECIFIC_SCOPE_SERVICE_ID IS 'FK to a specific service (scope type "specific")';
COMMENT ON COLUMN FW.SCOPED_IP_GROUP_MEMBER_TYPE.NAME IS 'name of the scope type';
COMMENT ON COLUMN FW.SCOPED_IP_GROUP_MEMBER_TYPE.DESCRIPTION IS 'description for this scope type';
COMMENT ON COLUMN FW.SCOPED_IP_GROUP_SCOPE.SCOPED_IP_GROUP_ID IS 'FK to the parent scoped ip group';
COMMENT ON COLUMN FW.SCOPED_IP_GROUP_SCOPE.SERVICE_ID IS 'FK to the service that defines the scope';
COMMENT ON COLUMN FW.SCOPED_IP_GROUP_SCOPE.IP_GROUP_ID IS 'FK to the actual IP group defined for this scope (IP group has automatic set to 1 in such a case)';
COMMENT ON COLUMN FW.SECTION.NAME IS 'optional name';
COMMENT ON COLUMN FW.SECTION.POLICY_ID IS 'FK to parent policy';
COMMENT ON COLUMN FW.SECTION.SRC_ZONE_ID IS 'FK to source zone';
COMMENT ON COLUMN FW.SECTION.DST_ZONE_ID IS 'FK to dst zone';
COMMENT ON COLUMN FW.SECTION.SEQ_NO IS 'Sequence number (GUI functionality only)';
COMMENT ON COLUMN FW.SECTION.POLICY_ACTION_ID IS 'FK to the policy action of this section';
COMMENT ON COLUMN FW.SECTION.POLICY_LOG_TARGET_ID IS 'FK to the log target for the policy action of this section';
COMMENT ON COLUMN FW.SERVICE_GROUP.AUTOMATIC IS 'the boolean property ''automatic'' marks service groups which are created automatically to serve
as service definitions for firewall rules.';
COMMENT ON COLUMN FW.SOURCE_NAT_RULE.NAT_SECTION_ID IS 'FK to parent section';
COMMENT ON COLUMN FW.SOURCE_NAT_RULE.TRANS_SRC_GROUP_ID IS 'only defined if action == NAT';
COMMENT ON COLUMN FW.SOURCE_NAT_RULE2TICKET.SOURCE_NAT_RULE_ID IS 'FK to SOURCE_NAT_RULE';
COMMENT ON COLUMN FW.SOURCE_NAT_RULE2TICKET.TICKET_ID IS 'FK to TICKET';
COMMENT ON COLUMN FW.SUB_SECTION.SECTION_ID IS 'FK to the parent section, null for section of type host_* and external';
COMMENT ON COLUMN FW.SUB_SECTION.SOURCE_SERVICE_ID IS 'installation target, NULL if global';
COMMENT ON COLUMN FW.SUB_SECTION.SUB_SECTION_TYPE_ID IS 'FK to subsection type';
COMMENT ON COLUMN FW.SUB_SECTION_TYPE.NAME IS 'Name of the host section type';
COMMENT ON COLUMN FW.SUB_SECTION_TYPE.DESCRIPTION IS 'Description';
COMMENT ON COLUMN FW.ZONE.NAME IS 'name of the zone';
COMMENT ON COLUMN FW.ZONE.DESCRIPTION IS 'description of the zone';
COMMENT ON COLUMN FW.ZONE.COMPANY_ID IS 'FK to company or NULL if global, predefined zone';
COMMENT ON COLUMN FW.ZONE_MEMBER.ZONE_ID IS 'FK to FW.ZONE';
COMMENT ON COLUMN FW.ZONE_MEMBER.INTERFACE_ID IS 'FK to MSS.INTERFACE';
COMMENT ON TABLE GUMA2.SUPPRESSED_SIGNATURE IS 'Events matching this signature, host and date, will be suppressed by gumaserver';
COMMENT ON TABLE GUMA2.SYSLOG_MESSAGE_TYPE IS 'The type of a syslog message to determine why it has been stored in the table. This is a value table';
COMMENT ON COLUMN GUMA2.EXTERNAL_SENSOR.MONITOREDHOST_INTERFACE_ID IS 'Interface of host to be monitored by the sensor host';
COMMENT ON COLUMN GUMA2.EXTERNAL_SENSOR.SENSORHOST_INTERFACE_ID IS 'Interface of the sensor host from where the monitored host is monitored';
COMMENT ON COLUMN GUMA2.EXTERNAL_SENSOR.SENSOR_TYPE_ID IS 'Type of monitoring by the sensor host (e.g. syslog, snmp)';
COMMENT ON COLUMN GUMA2.SENSOR_TYPE.NAME IS 'Name of the sensor type, explaining the monitoring protocol/technology';
COMMENT ON COLUMN GUMA2.SENSOR_TYPE.DESCRIPTION IS 'More descriptive explanation of the sensor type';
COMMENT ON COLUMN GUMA2.SIGNATURE.UNSTABLE IS 'Flag that indicates whether these events are normal for hosts with mss.host.unstable=1 (e.g. ''SYSTEM:BOOT:UNEXPECTED'')';
COMMENT ON COLUMN GUMA2.SIGNATURE.NOQUARANTINE IS 'Flag that indicates whether these events are excluded from our GUMA event quarantine. (e.g. "1" => never quarantine that signature)';
COMMENT ON COLUMN GUMA2.SYSLOG_MESSAGE.SYSLOG_MESSAGE_TYPE_ID IS 'Type of the syslog message';
COMMENT ON COLUMN GUMA2.SYSLOG_MESSAGE_TYPE.ID IS 'The primary key ID';
COMMENT ON COLUMN GUMA2.SYSLOG_MESSAGE_TYPE.NAME IS 'The name of the type';
COMMENT ON TABLE MAIL.BATV_KEY IS 'Key storage for Backscatter Protection (using Bounce Address Tag Validation)';
COMMENT ON COLUMN MAIL.CUSTOM_POLICY_LIST_VALUE.LAST_MODIFIED_TIME IS 'The time when the entry was updated the last time';
COMMENT ON COLUMN MAIL.CUSTOM_POLICY_LIST_VALUE.LAST_MODIFIED_CONTACT_ID IS 'The contact that updated the entry the last time';
COMMENT ON COLUMN MAIL.CUSTOM_POLICY_LIST_VALUE.CUSTOMER_REFERENCE IS 'A reference to the customer''s incident/ticketing system';
COMMENT ON COLUMN MAIL.DMARC_REPORT.DMARC_REPORT_ORG_ID IS 'The organization ID this report belongs to.';
COMMENT ON COLUMN MAIL.DMARC_REPORT_RECORD.IP_ADDRESS_HIGH IS '64 highest bits of IP address (is NULL for IPv4)';
COMMENT ON COLUMN MAIL.DMARC_REPORT_RECORD.IP_ADDRESS_LOW IS '64 lowest bits of IP address';
COMMENT ON COLUMN MAIL.POLICY_LIST_VALUE.LAST_MODIFIED_TIME IS 'The time when the entry was updated the last time';
COMMENT ON COLUMN MAIL.POLICY_LIST_VALUE.LAST_MODIFIED_CONTACT_ID IS 'The contact that updated the entry the last time';
COMMENT ON COLUMN MAIL.POLICY_LIST_VALUE.CUSTOMER_REFERENCE IS 'A reference to the customer''s incident/ticketing system';
COMMENT ON TABLE MC.CONNECTION_INTERRUPT_OPEN IS 'If there is some outage, ISP outage or connection down, there will be an entry in this table.
The entry is removed when the outage is over, and replaced when the type of the outage changes.
I.e. this table reflects the current connection status of a host.
';
COMMENT ON TABLE MC.MAINTENANCE_STATUS IS 'Describes the maintenance status of an entity (host, isp_link)';
COMMENT ON COLUMN MC.AVAILABILITY_REPORT.DELETED_SERVICE_ID IS 'Service ID of the previously assigned service, not a foreign key';
COMMENT ON COLUMN MC.AVAILABILITY_REPORT.CONN_SLA_CLASS_ID IS 'No SLA class (NULL) if the company has SLA reporting disabled';
COMMENT ON COLUMN MC.AVAILABILITY_REPORT.CONN_SLA_TARGET_ID IS 'No SLA target (NULL) stands for best effort';
COMMENT ON COLUMN MC.AVAILABILITY_REPORT.CONNECTIVITY_INCLUDED IS 'Value of MC.SERVICE_CONN_SLA_CONFIG.INCLUDE_CONNECTIVITY of the corresponding service at the time of report creation';
COMMENT ON COLUMN MC.AVAILABILITY_REPORT.REPORT_DATA_REFERENCE IS 'Where to find the cache for this report';
COMMENT ON COLUMN MC.CONN_SLA_CLASS.SEQ_NO IS 'Sequence number to model a consistent sorting of the SLA classes';
COMMENT ON COLUMN MC.CONN_SLA_CLASS.CONN_SLA_TARGET_ID IS 'No SLA target (NULL) stands for best effort';
COMMENT ON COLUMN MC.CONN_SLA_TARGET.TARGET IS 'SLA target in % multiplied by 1000 (only integers allowed between 1000 and 99999)';
COMMENT ON COLUMN MC.HOST_MAINTENANCE_HISTORY.TICKET_ID IS 'Ticket of the service window, in case new status is maintenance';
COMMENT ON COLUMN MC.ISP_LINK_MAINTENANCE_HISTORY.TICKET_ID IS 'Ticket of the service window, in case new status is maintenance';
COMMENT ON COLUMN MC.MC_FILE_RELEASE.RELEASED IS 'Flag that indicates whether the download is in released or in pre-released state';
COMMENT ON COLUMN MC.MC_FILE_TYPE.SHARED IS 'Flag that indicates whether the files of this type are for multiple companies or just a single one';
COMMENT ON COLUMN MC.MC_FILE_TYPE.RELEASABLE IS 'Flag that indicates whether the files of this type can be in a pre-release state or not';
COMMENT ON COLUMN MC.MON_SERVER_CONNECTION.IPV6_ADDRESS_1 IS 'The most significant 64 bits of the IPv6 address.';
COMMENT ON COLUMN MC.MON_SERVER_CONNECTION.IPV6_ADDRESS_2 IS 'The least significant 64 bits of the IPv6 address.';
COMMENT ON COLUMN MC.SERVICE_CONN_SLA_CONFIG.INCLUDE_CONNECTIVITY IS 'Whether to include ISP related downtime into SLA calculations or not';
COMMENT ON TABLE MCAUDIT.SEVERITY IS 'log level';
COMMENT ON COLUMN MCAUDIT.RECORD.COMPANY_ID IS '
the company where the object referenced by object_id / object_type_id belongs to. this is
also the company whose users/admins may view this record.
';
COMMENT ON COLUMN MCAUDIT.RECORD.CONTACT_ID IS 'who did this (may be NULL for system scripts, synchronization etc.)';
COMMENT ON COLUMN MCAUDIT.RECORD.DETAILS IS 'detailed record message (XML)';
COMMENT ON COLUMN MCAUDIT.RECORD.MESSAGE IS 'short, descriptive message of what was done';
COMMENT ON COLUMN MCAUDIT.RECORD.OBJECT_ID IS 'id of the referenced object of type (object_type_id)';
COMMENT ON COLUMN MCAUDIT.RECORD.OBJECT_TYPE_ID IS 'object type of the referenced object (see mss.object_type)';
COMMENT ON COLUMN MCAUDIT.RECORD.TRANSACTION_ID IS 'a transaction id which is equal for records which belong together';
COMMENT ON COLUMN MSG.OUTGOING_MAIL.MAIL_FROM IS 'SMTP MAIL FROM string identifying the sender mailbox';
COMMENT ON COLUMN MSG.OUTGOING_MAIL.MAIL_DATA IS 'Email data i.e. header and body. The body is MIME encoded and consists of ASCII characters only.';
COMMENT ON COLUMN MSG.OUTGOING_MAIL_RCPT.RCPT_ADDRESS IS 'SMTP recipient address';
COMMENT ON TABLE MSS.ADDRESS IS 'Addresses (for coordinates see also http://www.tbs-sct.gc.ca/rpm-gbi/guides/Latlong_e.asp)';
COMMENT ON TABLE MSS.DNSSEC_ALGORITHM IS 'Describes Domain Name System Security (DNSSEC) Algorithm Numbers.
        See also:
        http://www.iana.org/assignments/dns-sec-alg-numbers/dns-sec-alg-numbers.xhtml
      ';
COMMENT ON TABLE MSS.DNSSEC_KEY_DIGEST_TYPE IS 'Describes Delegation Signer (DS) Resource Record (RR) Type
        Digest Algorithms used for DNSSEC. See also:
        http://www.iana.org/assignments/ds-rr-types/ds-rr-types.xhtml
      ';
COMMENT ON TABLE MSS.FIELD_MAPPING IS 'stores java/sql field mapping information (filled by the mapping2table script. IDs are NOT guaranteed to stay the same for a given field name.
these objects/rows are not to be referenced by others.)';
COMMENT ON TABLE MSS.FIELD_MAPPING_TYPE IS 'value table for field mapping types.';
COMMENT ON TABLE MSS.HARDWARE_LC_LOCATION IS 'Hardware Lifecyle location';
COMMENT ON TABLE MSS.HARDWARE_LC_STATE IS 'Hardware Lifecyle state';
COMMENT ON TABLE MSS.HARDWARE_LC_TRANSIT_INFO IS 'Hardware Lifecyle transit info';
COMMENT ON TABLE MSS.HARDWARE_LC_TRANSIT_STATE IS 'Hardware Lifecyle transit state';
COMMENT ON TABLE MSS.INTERFACE_DYNAMIC_IP_STATE IS 'Host side configuration of dynamic IPv4 interfaces';
COMMENT ON TABLE MSS.KEY_TYPE IS 'this is a value table for gui reasons, values are: bool/integer/float/string/file';
COMMENT ON TABLE MSS.LOCAL_CONTACT IS 'A local contact is a contact standing in any relation with a address. The relation
is defined in mss.local_contact_type. Local contacts do have a priority. ';
COMMENT ON TABLE MSS.NAT_IIFACE_2_OIFACE IS 'A mapping for hiding NAT on specific source interfaces';
COMMENT ON TABLE MSS.OBJECT_TYPE IS 'stores the relation of table names and java class names (filled/maintained by the mapping2table script. IDs are guaranteed to stay the same
for existing object types.)';
COMMENT ON TABLE MSS.OPENVPN_INTERFACE IS 'Interfaces of the OpenVPN management environment';
COMMENT ON COLUMN MSS.ADDRESS.ADDRESS_LINES IS 'The address itself, typically street and number. Postal code,
city and country are stored in seperate fields.';
COMMENT ON COLUMN MSS.ADDRESS.ADDRESS_SHIPPING_LINES IS 'Used if a location wants to get sent its equipment to another location. E.g. a central
IT management location. Postal code, city and country need to be stored in this field too.';
COMMENT ON COLUMN MSS.ADDRESS.LATITUDE_DEGREES IS 'Range: 0 to 90';
COMMENT ON COLUMN MSS.ADDRESS.LATITUDE_MINUTES IS 'Range: 0 to 59';
COMMENT ON COLUMN MSS.ADDRESS.LATITUDE_SECONDS IS 'Range: 0 to 59 with optional decimals separated with a "."';
COMMENT ON COLUMN MSS.ADDRESS.LATITUDE_DIRECTION IS 'Available values are: N (North) and S (South)';
COMMENT ON COLUMN MSS.ADDRESS.LONGITUDE_DEGREES IS 'Range: 0 to 180';
COMMENT ON COLUMN MSS.ADDRESS.LONGITUDE_MINUTES IS 'Range 0 to 59';
COMMENT ON COLUMN MSS.ADDRESS.LONGITUDE_SECONDS IS 'Range: 0 to 59 with optional decimals separated with a "."';
COMMENT ON COLUMN MSS.ADDRESS.LONGITUDE_DIRECTION IS 'Available values are: E (East) or W (West) (O in some notations but we map it to W) ';
COMMENT ON COLUMN MSS.ADDRESS.LOCAL_COMPANY_NAME IS 'This needs to be set if the subcompany at this addres has a different name than the belonging mother
company, e.g. a holding.';
COMMENT ON COLUMN MSS.ADDRESS.PHYSICAL_ACCESS_COMMENTS IS 'Optional field to describe procedures for gaining physical access to the devices located at this address';
COMMENT ON COLUMN MSS.APPLICATION_TEAM.ID IS 'ID of the application team.';
COMMENT ON COLUMN MSS.APPLICATION_TEAM.NAME IS 'Name of the application team.';
COMMENT ON COLUMN MSS.APPLICATION_TEAM.DESCRIPTION IS 'Description of the application team. ';
COMMENT ON COLUMN MSS.APPLICATION_TEAM_CONTACT.ID IS 'ID of the application team contact.';
COMMENT ON COLUMN MSS.APPLICATION_TEAM_CONTACT.APPLICATION_TEAM_ID IS 'ID of the application team.';
COMMENT ON COLUMN MSS.APPLICATION_TEAM_CONTACT.CONTACT_ID IS 'ID of the contact.';
COMMENT ON COLUMN MSS.BLUEPRINT.COMPANY_ID IS 'Reference to the customer company for this project.';
COMMENT ON COLUMN MSS.BLUEPRINT_ENTRY.IS_NEW IS 'Denotes whether this entry is a new installation.';
COMMENT ON COLUMN MSS.BLUEPRINT_ENTRY.ADDITIONAL IS 'Denotes whether this entry is to be added to an existing installation.';
COMMENT ON COLUMN MSS.BLUEPRINT_ENTRY.SCOPE IS 'A number which denotes the scope (i.e. logical unit) for this blueprint entry.';
COMMENT ON COLUMN MSS.CAS_PORT.HOST_ID IS 'The host that is attached to this port';
COMMENT ON COLUMN MSS.CAS_PORT.CAS_HOST_ID IS 'The CAS server this port belongs to';
COMMENT ON COLUMN MSS.CAS_PORT.PORT IS 'The actual number of the port';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT.ID IS 'The primary key';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT.DEPLOYMENT_GROUP_ID IS 'The id of the deployment group. Several config deployments can be logically grouped together.';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT.LAST_UPDATE IS 'The last time this deployment was modified.';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT.HOST_ID IS 'The host to which the deployment applies to.';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT.CONFIG_DEPLOYMENT_USE_CASE_ID IS 'The use case of this deployment.';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT.JOB_ID IS 'The job with which the deployment is rolled out.';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT.CONFIG_DEPLOYMENT_STATUS_ID IS 'The status of this deployment.';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT.CONFIG_ROLLOUT_ID IS 'The id of the Config Rollout this deployment is part of.';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT.TIME_ERROR IS 'Timestamp when there was an error when trying to deploy.';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT.TIME_APPLIED IS 'Timestamp when deployment was applied.';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT.CONFIG_DEPLOYMENT_ERROR_ID IS 'Lookup of the actual deplyoment error.';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT_ERROR.ID IS 'The primary key';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT_ERROR.ERROR IS 'The error which made the deployment fail.';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT_STATUS.ID IS 'The primary key';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT_STATUS.NAME IS 'The name of the config deployment status.';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT_USE_CASE.ID IS 'The primary key';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT_USE_CASE.NAME IS 'The name of the config deployment use case.';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT_USE_CASE.DESCRIPTION IS 'The description of the config deployment use case.';
COMMENT ON COLUMN MSS.CONFIG_DEPLOYMENT_USE_CASE.SERVICE_NAME IS 'The service name of the config deployment use case.';
COMMENT ON COLUMN MSS.CONFIG_LIST.ID IS 'The primary key';
COMMENT ON COLUMN MSS.CONFIG_LIST.CONFIG_LIST_TYPE_ID IS 'The type of this list.';
COMMENT ON COLUMN MSS.CONFIG_LIST.SERVICE_ID IS 'The service scope of this list.';
COMMENT ON COLUMN MSS.CONFIG_LIST.IS_SELF_PROVISIONED IS 'Indicates whether the entries in this list can be edited by the customer.';
COMMENT ON COLUMN MSS.CONFIG_LIST.IS_DIRTY IS 'A config list is dirty if entries of the list have been added, deleted or modified. The list becomes clean after a deployment has been scheduled for it.';
COMMENT ON COLUMN MSS.CONFIG_LIST_TYPE.ID IS 'The primary key';
COMMENT ON COLUMN MSS.CONFIG_LIST_TYPE.CONFIG_LIST_VALUE_TYPE_ID IS 'Reference to the value type for this list type.';
COMMENT ON COLUMN MSS.CONFIG_LIST_TYPE.COMPANY_ID IS 'Reference to the company this list type belongs to.';
COMMENT ON COLUMN MSS.CONFIG_LIST_TYPE.NAME IS 'The name of this list type.';
COMMENT ON COLUMN MSS.CONFIG_LIST_TYPE.DISPLAY_NAME IS 'The display name of this list type.';
COMMENT ON COLUMN MSS.CONFIG_LIST_TYPE.DESCRIPTION IS 'The description of this list type.';
COMMENT ON COLUMN MSS.CONFIG_LIST_VALUE.ID IS 'The primary key';
COMMENT ON COLUMN MSS.CONFIG_LIST_VALUE.CONFIG_LIST_ID IS 'The config list this value belongs to.';
COMMENT ON COLUMN MSS.CONFIG_LIST_VALUE.VALUE IS 'The value.';
COMMENT ON COLUMN MSS.CONFIG_LIST_VALUE.DESCRIPTION IS 'Comment/description of this value.';
COMMENT ON COLUMN MSS.CONFIG_LIST_VALUE.LAST_MODIFIED_TIME IS 'The last time this value was modified.';
COMMENT ON COLUMN MSS.CONFIG_LIST_VALUE.LAST_MODIFIED_CONTACT_ID IS 'The last login who modified this value.';
COMMENT ON COLUMN MSS.CONFIG_LIST_VALUE_TYPE.ID IS 'The primary key';
COMMENT ON COLUMN MSS.CONFIG_LIST_VALUE_TYPE.NAME IS 'The name of this list type.';
COMMENT ON COLUMN MSS.CONFIG_LIST_VALUE_TYPE.REGEX IS 'The Java regular expression that must match all values of CONFIG_LIST_VALUE of CONFIG_LIST of CONFIG_LIST_VALUE_TYPE that reference this CONFIG_LIST_VALUE_TYPE.';
COMMENT ON COLUMN MSS.CONFIG_ROLLOUT.ID IS 'The primary key';
COMMENT ON COLUMN MSS.CONFIG_ROLLOUT.TIME_STARTED IS 'The rollout started at this time.';
COMMENT ON COLUMN MSS.CONFIG_ROLLOUT.CONTACT_ID IS 'User which triggered the rollout.';
COMMENT ON COLUMN MSS.CONFIG_ROLLOUT.COMPANY_ID IS 'Rollout for specific company. Null for shared (=all companies) rollouts';
COMMENT ON COLUMN MSS.CONFIG_ROLLOUT.JOB_GROUP_ID IS 'The job group doing the rollout.';
COMMENT ON COLUMN MSS.CONFIG_ROLLOUT.CONFIG_DEPLOYMENT_USE_CASE_ID IS 'The use case of this deployment.';
COMMENT ON COLUMN MSS.CONFIG_ROLLOUT.FINALIZED IS 'If this config rollout (self-service only) has completed >1h ago (*), used to reduce the query load when selecting ongoing rollouts. Written/updated by job mss.osag_config_rollout_mark_as_final.

        (*) The portal shows recently (15m) completed rollouts as well, that''s why this flag is set well outside this time frame only';
COMMENT ON COLUMN MSS.COST_CENTER.INTERNAL IS 'Historic fact: this was the last column which was successfully declared boolint and had its size attribute removed.';
COMMENT ON COLUMN MSS.COUNTRY.CODE IS 'ISO 3166-1';
COMMENT ON COLUMN MSS.DECOMM_HOST.ID IS 'The primary key';
COMMENT ON COLUMN MSS.DECOMM_HOST.CREATION_DATE IS 'The time stamp when the request was created ';
COMMENT ON COLUMN MSS.DECOMM_HOST.CREATION_CONTACT_ID IS 'The login id that was used to create the request ';
COMMENT ON COLUMN MSS.DECOMM_HOST.HOST_ID IS 'The host to decommission. Null when the request is COMPLETED|FAILED|REJECTED';
COMMENT ON COLUMN MSS.DECOMM_HOST.DISPLAY_COMPANY IS 'Text for the company short that allows identification after all host information is gone. Used for display.';
COMMENT ON COLUMN MSS.DECOMM_HOST.DISPLAY_HOST IS 'Text for the host name that allows identification after all host information is gone. Used for display.';
COMMENT ON COLUMN MSS.DECOMM_HOST.APPROVAL_DATE IS 'The timestamp when the request was approved/rejected. Null when not yet approved/rejected.';
COMMENT ON COLUMN MSS.DECOMM_HOST.APPROVAL_CONTACT_ID IS 'The login id that was used to approve/decline the request. Null when not yet approved/rejected.';
COMMENT ON COLUMN MSS.DECOMM_HOST.COMPLETION_DATE IS 'Point in time when the entry reached its final state (COMPLETED, FAILED, REJECTED). Null when not yet reached.';
COMMENT ON COLUMN MSS.DECOMM_HOST.TICKET_TRANSFER_HOST_ID IS 'Host where the Tickers should be transferred to. May be null when no transfer is needed. Always null when the status is COMPLETED|FAILED|REJECTED.';
COMMENT ON COLUMN MSS.DECOMM_HOST.ORIGINAL_SERVICE_ID IS 'Service where the host was attached before the process started. Null if the status is FAILED, REJECTED or COMPLETED.';
COMMENT ON COLUMN MSS.DECOMM_HOST.REPATRIATE_HW IS 'True if hw should be repatriated. If false the hw is marked for disposal during decommissioning.';
COMMENT ON COLUMN MSS.DECOMM_STATUS.ID IS 'The primary key';
COMMENT ON COLUMN MSS.DNS_ZONE.DNSSEC IS 'Indicates if DNSSEC is enabled for this zone. 0 means DNSSEC is disabled, 1 means DNSSEC is enabled. If NULL, the corresponding field of the DNS zone group is to be considered.';
COMMENT ON COLUMN MSS.FIELD_MAPPING.OBJECT_TYPE_ID IS 'the object type where this field belongs to';
COMMENT ON COLUMN MSS.FIELD_MAPPING.JAVA_FIELD_NAME IS 'the java field name';
COMMENT ON COLUMN MSS.FIELD_MAPPING.FIELD_MAPPING_TYPE_ID IS 'mapping type (value, one-many, etc.)';
COMMENT ON COLUMN MSS.FIELD_MAPPING.COLUMN_NAME IS 'the database column name in case of simple values or one-to-one mappings (for one-one, the column contains an ID)';
COMMENT ON COLUMN MSS.FIELD_MAPPING.REF_TABLE IS 'the referenced table in case of one-one, one-many and many-many mappings (for many-many, this ist not the link-table, but the table where the link table points to)';
COMMENT ON COLUMN MSS.FIELD_MAPPING.REF_COLUMN IS 'the "back-reference" column name in REF_TABLE for one-many and many-many mappings';
COMMENT ON COLUMN MSS.FIELD_MAPPING.ELEMENT_COLUMN IS 'the "forward-reference" column name in many-many link tables, the column which points to the element table';
COMMENT ON COLUMN MSS.FIELD_MAPPING.LINK_TABLE IS 'the link-table for many-many mappings';
COMMENT ON COLUMN MSS.FIELD_MAPPING_TYPE.NAME IS 'descriptive, human-readable name';
COMMENT ON COLUMN MSS.FIELD_MAPPING_TYPE.SHORT IS 'short mapping type name exactly like in package.mapping; value, one-one, one-many, many-many';
COMMENT ON COLUMN MSS.HARDWARE.HARDWARE_DISPOSAL_REASON_ID IS 'link to the hardware_disposal_reason table';
COMMENT ON COLUMN MSS.HARDWARE.HARDWARE_DISPOSAL_COMMENTS IS 'comments on hardware disposal (if any)';
COMMENT ON COLUMN MSS.HARDWARE.HARDWARE_DISPOSAL_CONTACT_ID IS 'contact of the OSAG person who did the disposal action';
COMMENT ON COLUMN MSS.HARDWARE.HARDWARE_DEPLOY_REASON_ID IS 'reason for the deployement, null if the hardware is not assigned to a host at the moment';
COMMENT ON COLUMN MSS.HARDWARE.HARDWARE_LIFECYCLE_ITEM_ID IS 'The latest (and therefore active) hardware lifecycle item';
COMMENT ON COLUMN MSS.HARDWARE_DEPLOY_REASON.NAME IS 'short descriptive name of the deploy reason';
COMMENT ON COLUMN MSS.HARDWARE_DEPLOY_REASON.DESCRIPTION IS 'description of the deploy reason';
COMMENT ON COLUMN MSS.HARDWARE_DISPOSAL_REASON.NAME IS 'short descriptive name of the disposal reason';
COMMENT ON COLUMN MSS.HARDWARE_DISPOSAL_REASON.DESCRIPTION IS 'description of the disposal reason';
COMMENT ON COLUMN MSS.HARDWARE_DISPOSAL_REASON.OBSOLETE IS 'when != 0, this reason is obsolete and may not be selected any more.
it is preserved for being referenced by the hardware_history table.';
COMMENT ON COLUMN MSS.HARDWARE_HISTORY.COMPANY_SHORT IS 'the company where the host/hardware belonged to';
COMMENT ON COLUMN MSS.HARDWARE_HISTORY.HOST_NAME IS 'the name of the host where the hardware belonged to';
COMMENT ON COLUMN MSS.HARDWARE_HISTORY.SERVICE_TYPE_INTERNAL_CODE IS 'the internal code of the service type which ran on the host';
COMMENT ON COLUMN MSS.HARDWARE_HISTORY.PURCHASE_DATE IS 'purchase date of the hardware';
COMMENT ON COLUMN MSS.HARDWARE_HISTORY.DISPOSAL_DATE IS 'disposal date of the hardware';
COMMENT ON COLUMN MSS.HARDWARE_HISTORY.HISTORY_DATE IS 'the date when the history record was created';
COMMENT ON COLUMN MSS.HARDWARE_HISTORY.MAC_ADDRESS IS 'the hardware''s ''primary'' (?) MAC address';
COMMENT ON COLUMN MSS.HARDWARE_HISTORY.SERIAL_NUMBER IS 'serial number of the hardware';
COMMENT ON COLUMN MSS.HARDWARE_HISTORY.BARCODE IS 'barcode of the hardware';
COMMENT ON COLUMN MSS.HARDWARE_HISTORY.HARDWARE_DISPOSAL_COMMENTS IS 'comments';
COMMENT ON COLUMN MSS.HARDWARE_HISTORY.LOG IS 'contains "selected information" related to this host in order to preserve it when related objects are deleted,
f.e. the company and host where this hardware belonged to might be deleted.';
COMMENT ON COLUMN MSS.HARDWARE_HISTORY.HARDWARE_DISPOSAL_REASON_ID IS 'link to the hardware_disposal_reason table';
COMMENT ON COLUMN MSS.HARDWARE_HISTORY.HARDWARE_DISPOSAL_CONTACT_ID IS 'contact of the OSAG person who did the disposal action';
COMMENT ON COLUMN MSS.HARDWARE_HISTORY.HARDWARE_TYPE_ID IS 'link to the hardware_type table';
COMMENT ON COLUMN MSS.HARDWARE_HISTORY.HARDWARE_DEPLOY_REASON_ID IS 'The reason why the hardware was deployed for this entry';
COMMENT ON COLUMN MSS.HOST.UNSTABLE IS 'Host is in a unreliable environment (frequent power interruptions or unreliable layer 2 infrastructure). Certain GUMA events will be suppressed.';
COMMENT ON COLUMN MSS.HOST.MAINTENANCE_STATUS_ID IS 'Maintenance status of the host (active, inactive, maintenance, unknown) as determined by according DB job';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT.COMPANY_ID IS 'Reference to the customer company for this project.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT.CUSTOMER_CONTACT_ID IS 'Reference to the responsible project lead on the customer side.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT.OSAG_CONTACT_ID IS 'Reference to the responsible project lead on OSAG side.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT.COMPLETED IS 'Denotes the completion of the project.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.CUSTOMER_CONTACT_ID IS 'Reference to the responsible contact on the customer side.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.OSAG_CONTACT_ID IS 'Reference to the responsible contact on OSAG side.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.PROJECT_ITEM_STATUS_ID IS 'The current state of the project item.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.ADDRESS_ID IS 'The location for this project item.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.ORIGINAL_COMPLETION_DATE IS 'The initially set target completion date.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.ESTIMATED_COMPLETION_DATE IS 'The currently estimated completion date, initialized with the ORIGINAL_COMPLETION_DATE.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.COMPLETION_DATE IS 'The date when the item was actually set to status ''completed''.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.ORDER_DATE IS 'Date when the project item''s status got changed to ''ordered''.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.CONFIG_RECEIVED_DATE IS 'Date when the project item''s status got changed to ''confirmed''.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.SHIPMENT_DATE IS 'Date when the hardware got shipped to the client.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.SHIPMENT_ARRIVED_DATE IS 'Date when the shipment of the hardware arrived at the client.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.ACTIVATED_DATE IS 'Date when the project item''s status got changed to ''activate'', former ''ready_date''.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.CANCELLATION_DATE IS 'Date when the project item''s status got changed to ''canceled''.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.DELAYED IS 'Denotes whether or not this project item is delayed.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.DELAY_DATE IS 'Date until when the item is expected to be delayed.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.SHIPMENT_EST_ARRIVED_DATE IS 'Date when the shipment of the hardware is estimated to arrive at the client.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.PROCESSED_DATE IS 'When the item was processed by service delivery. Set on ''processed'' state.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.LATEST_DISPATCH_DATE IS 'Date until when the items must be shipped.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.ORDER_CONTACT_ID IS 'Reference to the responsible contact that ordered the item.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.APPROVAL_CONTACT_ID IS 'Reference to the responsible contact that approved (=signed off) the item.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.RUNBOOK_URL IS 'Optional link to the runnbook.';
COMMENT ON COLUMN MSS.INSTALLATION_PROJECT_ITEM.CREATION_DATE IS 'Creation date of the item. Nullable as this column was added with already existing items.';
COMMENT ON COLUMN MSS.INTERFACE.EXTERNAL IS 'Flag that indicates whether this interface leads to an external or an internal address space';
COMMENT ON COLUMN MSS.INTERFACE.DISABLE_ANTI_SPOOFING_CHECKS IS 'Flag for disabling anti spoofing security/consistency checks and magic of external interfaces during chenerator rule generation.
               This flag is enabled in the ChE interface editor GUI.';
COMMENT ON COLUMN MSS.INTERFACE.INHERIT_TOS IS 'Flag that indicates whether DiffServ/TOS field is copied from GRE to IPSec packets on this interface';
COMMENT ON COLUMN MSS.INTERFACE.HIDING_NAT IS 'Should hiding NAT be done when traffic leaves through this interface?';
COMMENT ON COLUMN MSS.INTERFACE.PUBLIC_NAT_IP IS 'Public IPv4 address under which this host is reachable from the Internet if it is placed behind a NAT box';
COMMENT ON COLUMN MSS.INTERFACE_ADDRESS.ID IS 'The primary key';
COMMENT ON COLUMN MSS.INTERFACE_ADDRESS.INTERFACE_ID IS 'Reference to the interface';
COMMENT ON COLUMN MSS.INTERFACE_ADDRESS.IPV6_ADDRESS_ID IS 'Reference to the IPv6 address';
COMMENT ON COLUMN MSS.INTERFACE_ADDRESS.IPV6_PREFIX_ID IS 'Reference to the IPV6 prefix the address is in';
COMMENT ON COLUMN MSS.INTERFACE_ADDRESS.MGMTACCESS IS 'Flag whether the address is used for mgmt access';
COMMENT ON COLUMN MSS.INTERFACE_ADDRESS.OSPF_DONT_PROPAGATE IS 'Flag whether to propagate the attached prefix over OSPF or not';
COMMENT ON COLUMN MSS.INTERFACE_ADDRESS.VRRP IS 'Flag whether the address is used as VRRP address';
COMMENT ON COLUMN MSS.INTERFACE_DYNAMIC_IP_STATE.PUBLIC_IP_ADDRESS IS 'Public Router IP obtained by the reflector service';
COMMENT ON COLUMN MSS.INTERFACE_DYNAMIC_IP_STATE.MTU IS 'The MTU reported by the DHCP options';
COMMENT ON COLUMN MSS.IPV6_ADDRESS.ID IS 'The primary key';
COMMENT ON COLUMN MSS.IPV6_ADDRESS.NAME IS 'An optional name for the IPv6 address';
COMMENT ON COLUMN MSS.IPV6_ADDRESS.COMPANY_ID IS 'A reference to the company this address belongs to. If null, the address is shared among all companies.';
COMMENT ON COLUMN MSS.IPV6_ADDRESS.ADDRESS_1 IS 'The most significant 64 bits of the address.';
COMMENT ON COLUMN MSS.IPV6_ADDRESS.ADDRESS_2 IS 'The least significant 64 bits of the address.';
COMMENT ON COLUMN MSS.IPV6_ADDRESS.COMMENTS IS 'An optional comment to the address.';
COMMENT ON COLUMN MSS.IPV6_PREFIX.ID IS 'The primary key';
COMMENT ON COLUMN MSS.IPV6_PREFIX.NAME IS 'An optional name for the IPv6 prefix';
COMMENT ON COLUMN MSS.IPV6_PREFIX.COMPANY_ID IS 'A reference to the company this prefix belongs to. If null, the prefix is shared among all companies.';
COMMENT ON COLUMN MSS.IPV6_PREFIX.ADDRESS_1 IS 'The higher 64bit of the prefix';
COMMENT ON COLUMN MSS.IPV6_PREFIX.ADDRESS_2 IS 'The lower 64bit of the prefix, usually 0';
COMMENT ON COLUMN MSS.IPV6_PREFIX.MASK IS 'The netmask of this prefix in CIDR notation.';
COMMENT ON COLUMN MSS.IPV6_PREFIX.COMMENTS IS 'An optional comment to the address.';
COMMENT ON COLUMN MSS.IPV6_STATIC_ROUTE.ID IS 'The primary key';
COMMENT ON COLUMN MSS.IPV6_STATIC_ROUTE.PREFIX_ID IS 'Reference to the prefix that should be routed';
COMMENT ON COLUMN MSS.IPV6_STATIC_ROUTE.OUTGOING_INTERFACE_ID IS 'Reference to the outgoing interface, only mandatory for link local targetted routes';
COMMENT ON COLUMN MSS.IPV6_STATIC_ROUTE.NEXTHOP_ADDRESS_ID IS 'Reference to the IPv6 address of the nexthop/gateway';
COMMENT ON COLUMN MSS.IPV6_STATIC_ROUTE.ROUTE_OWNER_HOST_ID IS 'Reference to the host that owns this route entry';
COMMENT ON COLUMN MSS.IPV6_STATIC_ROUTE.COMMENTS IS 'Optional comment for a route entry';
COMMENT ON COLUMN MSS.IPV6_STATIC_ROUTE.PRIORITY IS 'The priority for default route switching. The lower the number the higher the priority for default routes. The lowest possible value is 1. Must be 1 for all non-default routes.';
COMMENT ON COLUMN MSS.ISP_LINK.MONITORING_MTTR IS 'if MONITORING is set this denotes the MTTR, mean time to repair/recover [minutes]';
COMMENT ON COLUMN MSS.ISP_LINK.CURRENCY_ID IS 'currency that applies to all fees for this isp link';
COMMENT ON COLUMN MSS.ISP_LINK.LINK_INSTALLATION_FEE IS 'local loop cost';
COMMENT ON COLUMN MSS.ISP_LINK.ISP_NOTIFICATION IS 'boolean: denotes if notifications are sent to the ISP when ''ISP outage'' events occur';
COMMENT ON COLUMN MSS.ISP_LINK.ROUTER_NUMBER IS 'Non-OSAG ID of the router used for this ISP link';
COMMENT ON COLUMN MSS.ISP_LINK.MEASURED_DOWNLOAD IS 'Sliding window average of download traffic on the link interface in kilobits per second';
COMMENT ON COLUMN MSS.ISP_LINK.DISABLE_OSAG_ISP_MONITORING IS 'Disable availability monitoring for this ISP link (affects OSAGlinkmon)';
COMMENT ON COLUMN MSS.ISP_LINK.MEASURED_UPLOAD IS 'Sliding window average of upload traffic on the link interface in kilobits per second';
COMMENT ON COLUMN MSS.ISP_LINK.ISP_LINK_STATUS_TYPE_ID IS 'Reference to the status type that describes current state of ISP link';
COMMENT ON COLUMN MSS.ISP_LINK.PING_IP_GROUP_ID IS 'Reference to the IP Group that will be used as ping targets for linkmon';
COMMENT ON COLUMN MSS.ISP_LINK.MAINTENANCE_STATUS_ID IS 'Maintenance status of the host (active, inactive, maintenance, unknown) as determined by according DB job';
COMMENT ON COLUMN MSS.ISP_LINK.USAGE_INTERFACE_ID IS 'Interface that has been used to compute the measurements for download and upload usage';
COMMENT ON COLUMN MSS.ISP_LINK.IPSEC_INTERNAL_FRAGMENTATION IS 'Internal fragmentation for IPSEC tunnels';
COMMENT ON COLUMN MSS.ISP_LINK.ROUTER_IPV6_ADDRESS_ID IS 'Reference to the IPv6 address of the ISP router';
COMMENT ON COLUMN MSS.ISP_LINK.WAN_MANAGED_IGNORE_MISMATCH IS 'Should we exclude this ISP line from the check against the service option?';
COMMENT ON COLUMN MSS.ISP_LINK.WAN_MANAGED_IGNORE_REASON IS 'Reason for excluding the line from the service option check (WAN_MANAGED_IGNORE_MISMATCH)';
COMMENT ON COLUMN MSS.ISP_LINK.ISP_LINK_SOURCING_TYPE_ID IS 'Denotes who is responsible for managing this ISP link';
COMMENT ON COLUMN MSS.ISP_LINK.VARIABLE_BANDWIDTH IS 'Is this ISP link enabled for variable bandwidth?';
COMMENT ON COLUMN MSS.ISP_LINK.VARIABLE_BANDWIDTH_IDENTIFIER IS 'Free-text ID that is used to map this link to the provider''s link ID';
COMMENT ON COLUMN MSS.ISP_LINK.VARIABLE_BANDWIDTH_DOWN IS 'Provided downstream bandwidth [kbit/s] of this variable bandwidth-enabled link';
COMMENT ON COLUMN MSS.ISP_LINK.VARIABLE_BANDWIDTH_UP IS 'Provided upstream bandwidth [kbit/s] of this variable bandwidth-enabled link';
COMMENT ON COLUMN MSS.ISP_LINK.VARIABLE_BANDWIDTH_QOS_DOWN IS 'Downstream QoS bandwidth [kbit/s] of this variable bandwidth-enabled link';
COMMENT ON COLUMN MSS.ISP_LINK.VARIABLE_BANDWIDTH_QOS_UP IS 'Upstream QoS bandwidth [kbit/s] of this variable bandwidth-enabled link';
COMMENT ON COLUMN MSS.ISP_LINK.COMPANY_ID IS 'the ISP company (usually different from the host company)';
COMMENT ON COLUMN MSS.ISP_LINK.MC_CUSTOMER_ID IS 'The customer to which this isp link belongs to';
COMMENT ON COLUMN MSS.ISP_LINK.BANDWIDTH_DOWN IS 'provided downstream bandwidth [kbit/s]';
COMMENT ON COLUMN MSS.ISP_LINK.BANDWIDTH_UP IS 'provided upstream bandwidth [kbit/s]';
COMMENT ON COLUMN MSS.ISP_LINK.SLA_AVAILABILITY IS 'Service Level Agreement availability of this link [%](0-100)';
COMMENT ON COLUMN MSS.ISP_LINK.MTU IS 'Maximum Transmission Unit [Bytes], maximum size of packets which this link supports';
COMMENT ON COLUMN MSS.ISP_LINK.ROUTER_IP_ADDRESS1 IS 'IPv4 address of the router from the ISP';
COMMENT ON COLUMN MSS.ISP_LINK.ACCOUNT_MANAGER_ID IS 'if set, denotes the person that is responsible for this account/line';
COMMENT ON COLUMN MSS.ISP_LINK.SUPPORT_ID IS 'if set, denotes the (24h) support helpdesk of the ISP';
COMMENT ON COLUMN MSS.ISP_LINK.EVENT_TYPE_ID IS 'event type to generate when an ISP outage happens for this line';
COMMENT ON COLUMN MSS.ISP_LINK.PRODUCT_NAME IS 'how the ISP entitles this product';
COMMENT ON COLUMN MSS.ISP_LINK.CONTRACT_DURATION IS 'denotes the duration period of the contract [month]';
COMMENT ON COLUMN MSS.ISP_LINK.CANCELLATION_PERIOD IS 'denotes the cancellation period of the contract [month]';
COMMENT ON COLUMN MSS.ISP_LINK.LAST_REVIEW_DATE IS 'denotes the date of the last review/update of ISP contract data from this link
this is set automatically for new links, but manually for edited links';
COMMENT ON COLUMN MSS.LOCAL_CONTACT.PRIORITY IS 'The priority orders the contacts for a certain criteria (e.g. on-site intervention local contacts in
the order they get called by mc). Priorities are assigned individual for every address and every type.
The highest priority is the one with the lowest number, starting with 1. There should not be any ''holes''
in the priority e.g.  1-2-4.
';
COMMENT ON COLUMN MSS.LOCAL_CONTACT_NOTIFICATION.ID IS 'The primary key ID';
COMMENT ON COLUMN MSS.LOCAL_CONTACT_NOTIFICATION.LOCAL_CONTACT_ID IS 'The local contact that has the according notification configured';
COMMENT ON COLUMN MSS.LOCAL_CONTACT_NOTIFICATION.EVENT_NOTIFICATION_TYPE_ID IS 'The event notification type (email,sms,etc.) for this notification';
COMMENT ON COLUMN MSS.OBJECT_TYPE.TABLE_NAME IS 'canonical name of the table which stores objects of type java_class_name (schema.table)';
COMMENT ON COLUMN MSS.OBJECT_TYPE.JAVA_CLASS_NAME IS 'canonical java class name of objects stored in the table table_name (package.classname)';
COMMENT ON COLUMN MSS.OPENVPN_INTERFACE.ID IS 'Primary key';
COMMENT ON COLUMN MSS.OPENVPN_INTERFACE.HOST_ID IS 'The host, to which the interface belongs';
COMMENT ON COLUMN MSS.OPENVPN_INTERFACE.NAME IS 'Name of the interface, currently it has to be like ''mvpnX'' (checked by a constraint)';
COMMENT ON COLUMN MSS.OPENVPN_INTERFACE.IP_ADDRESS IS 'The IP address of the interface';
COMMENT ON COLUMN MSS.OPENVPN_INTERFACE.NETWORK_ID IS 'The network directly attached to the interface. Note that the IP_ADDRESS has to lie within this network';
COMMENT ON COLUMN MSS.OPENVPN_INTERFACE.MGMTACCESS IS 'Flag whether or not this interface is used to manage the host.';
COMMENT ON COLUMN MSS.PING_IP.ID IS 'The primary key';
COMMENT ON COLUMN MSS.PING_IP.PING_IP_GROUP_ID IS 'Reference to the ping_ip_group';
COMMENT ON COLUMN MSS.PING_IP.ADDRESS_HIGH IS '64 highest bits of IP address (is NULL for IPv4)';
COMMENT ON COLUMN MSS.PING_IP.ADDRESS_LOW IS '64 lowest bits of IP address';
COMMENT ON COLUMN MSS.PING_IP_GROUP.ID IS 'The primary key';
COMMENT ON COLUMN MSS.PING_IP_GROUP.NAME IS 'A descriptive name for this set of IP addresses';
COMMENT ON COLUMN MSS.PING_IP_GROUP.COMPANY_ID IS 'Reference to the company id';
COMMENT ON COLUMN MSS.RELEASE_INSTALLATION.SOFTWARE_RELEASE_ID IS 'Reference to the release this entry is related.';
COMMENT ON COLUMN MSS.RELEASE_INSTALLATION.COMPANY_ID IS 'Reference to the customer this affects.';
COMMENT ON COLUMN MSS.RELEASE_INSTALLATION.INSTALL_START_DATE IS 'Date of the update of the first host.';
COMMENT ON COLUMN MSS.RELEASE_INSTALLATION.INSTALL_COMPLETE_DATE IS '
          Set when the installation ratio reaches 95%. The install ratio is computed from the heartbeats from OSIX LX hosts of this company as follows:
          (number of heartbeats reporting the current version)/(number of heartbeats). Only updated iff null.
        ';
COMMENT ON COLUMN MSS.RELEASE_INSTALLATION.INSTALL_END_DATE IS 'Date when the INSTALL_COUNT dropped to 0, only updated iff null.';
COMMENT ON COLUMN MSS.RELEASE_INSTALLATION.INSTALL_COUNT IS 'Number of hosts that have the release installed, only updated iff INSTALL_END_DATE is null.';
COMMENT ON COLUMN MSS.REPORT.REQUESTED_DATE IS 'The date when the report was requested.';
COMMENT ON COLUMN MSS.REPORT.COMPLETED_DATE IS 'The date when the report was completed or aborted.';
COMMENT ON COLUMN MSS.REPORT.REPORT_START_DATE IS 'The starting date of the report.';
COMMENT ON COLUMN MSS.REPORT.REPORT_END_DATE IS 'The ending date of the report.';
COMMENT ON COLUMN MSS.SERVICE.INSTALLATION_COMMENTS IS 'Comment on the current installation state of the service. Is displayed in the MCA task overview.';
COMMENT ON COLUMN MSS.SERVICE.CONFIGURATION_GROUP_ID IS 'Links to the config group';
COMMENT ON COLUMN MSS.SERVICE_FEATURE.SERVICE_ID IS 'Links to the service where this feature is attached to';
COMMENT ON COLUMN MSS.SERVICE_FEATURE.ENTITLEMENT_REF IS 'Contains the entitlement id from Sitrox when the feature is linked';
COMMENT ON COLUMN MSS.SERVICE_FEATURE.SERVICE_OPTION_TYPE_ID IS 'Links to the service option type';
COMMENT ON COLUMN MSS.SERVICE_FEATURE.SERVICE_FEATURE_STATE_ID IS 'The current state of the feature, links to MSS.SERVICE_FEATURE_STATE';
COMMENT ON COLUMN MSS.SERVICE_FEATURE.OPERATIONAL_DATE IS 'The date when the feature was marked operational';
COMMENT ON COLUMN MSS.SERVICE_FEATURE.APPROVED_DATE IS 'The date when the feature was marked approved';
COMMENT ON COLUMN MSS.SERVICE_FEATURE.INSTALLATION_PROJECT_ITEM_ID IS 'Links back to the project item if the service feature was created from a blueprint.';
COMMENT ON COLUMN MSS.SERVICE_FEATURE.INITIALIZED_DATE IS 'The date when the feature was created';
COMMENT ON COLUMN MSS.SOFTWARE_RELEASE.MAJOR_SOFTWARE_RELEASE_ID IS 'Reference to major release, null means it''s a major release.';
COMMENT ON COLUMN MSS.SOFTWARE_RELEASE.RELEASE_DATE IS 'Availability date';
COMMENT ON COLUMN MSS.SOFTWARE_RELEASE.RELEASE_NOTES IS 'Release notes for this release.';
COMMENT ON COLUMN MSS.SOFTWARE_RELEASE.RELEASE_NUMBER IS 'Major release number of this release.';
COMMENT ON COLUMN MSS.SOFTWARE_RELEASE.RELEASE_CARTRIDGE IS 'Minor release number of this release.';
COMMENT ON COLUMN MSS.SOFTWARE_RELEASE.SECURITY_UPDATE IS 'Does this release contain security updates?';
COMMENT ON COLUMN MSS.SOFTWARE_RELEASE.PERFORMANCE_UPDATE IS 'Does this release contain performance updates';
COMMENT ON COLUMN MSS.SOFTWARE_RELEASE.FEATURE_UPDATE IS 'Does this release contain feature updates?';
COMMENT ON COLUMN MSS.SOFTWARE_RELEASE.PUBLISHED IS 'Only published software releases are visible in the MC portal.';
COMMENT ON COLUMN MSS.STATIC_ROUTE.PRIORITY IS 'The priority for default route switching. The lower the number the higher the priority for default routes. The lowest possible value is 1. Must be 1 for all non-default routes.';
COMMENT ON COLUMN MSS.TAXCODE.NAME IS 'The tax id';
COMMENT ON COLUMN MSS.TAXCODE.DESCRIPTION IS 'The description of the tax id';
COMMENT ON TABLE NIDS.DYNAMIC_SIGNATURE_GROUP IS 'group of dynamic signature objects';
COMMENT ON TABLE NIDS.INVESTIGATION IS 'NIDS investigation';
COMMENT ON TABLE NIDS.INVESTIGATION_ENTRY IS 'NIDS investigation entry';
COMMENT ON TABLE NIDS.KS_ENFORCEMENT IS 'Kill switch enforcement';
COMMENT ON TABLE NIDS.KS_ENFORCEMENT_SCOPE IS 'Kill switch enforcement scope';
COMMENT ON TABLE NIDS.NIDS_DEVICE IS 'A device';
COMMENT ON TABLE NIDS.NIDS_ENTITY_GROUP IS 'group of entity objects';
COMMENT ON TABLE NIDS.NIDS_EVENT IS 'Events reported by the NIDS correlator host to be escalated as
Tickets via the MC transport layer. These are the events that were found
positives by the "escalation rules". Note that most fields of this table
are not used directly by MC, since we mostly use the database on the host
itself (HostDB). It is currently used only to map between Ticket and NIDS
Event and vice versa (LOCAL_EVENT_ID, TT_EVENT_ID). The other fields are
here for future statistical analysis.';
COMMENT ON TABLE NIDS.NIDS_FILE IS 'A NIDS file';
COMMENT ON TABLE NIDS.NIDS_IP_ADDRESS IS 'Simple IP addresses';
COMMENT ON TABLE NIDS.NIDS_USER IS 'A NIDS user';
COMMENT ON TABLE NIDS.SIGNATURE_GROUP IS 'group of signature objects';
COMMENT ON COLUMN NIDS.INVESTIGATION.START_DATE IS 'Timestamp when this investigation was opened';
COMMENT ON COLUMN NIDS.INVESTIGATION.END_DATE IS 'Timestamp when this investigation was opened';
COMMENT ON COLUMN NIDS.KS_ENFORCEMENT.START_DATE IS 'Timestamp when this kill switch enforcement was activated';
COMMENT ON COLUMN NIDS.KS_ENFORCEMENT.END_DATE IS 'Timestamp when this kill switch enforcement is disabled';
COMMENT ON COLUMN NIDS.KS_ENFORCEMENT.ACTIVE IS 'Boolean describing whether the enforcement is currently active';
COMMENT ON COLUMN NIDS.NIDS_ENTITY_GROUP.AUTOMATIC IS 'The boolean property "automatic" defines whether this group has been automatically created or if it was created by a user.';
COMMENT ON COLUMN NIDS.NIDS_EVENT.DB_DATE IS 'Timestamp when this event was entered in the database.';
COMMENT ON COLUMN NIDS.NIDS_EVENT.LOG_DATE IS 'Original timestamp of the event';
COMMENT ON COLUMN NIDS.NIDS_EVENT.SENSOR_HOST_ID IS 'Host-ID of the sensor that reported this event to the correlator.';
COMMENT ON COLUMN NIDS.NIDS_EVENT.SENDER_HOST_ID IS 'Host-ID of the NIDS correlator that sent this event via MC transport layer';
COMMENT ON COLUMN NIDS.NIDS_EVENT.LOCAL_EVENT_ID IS 'Event-ID in the Host-DB (database on the correlator)';
COMMENT ON COLUMN NIDS.NIDS_EVENT.SUPPRESSED IS 'Number of other events with same source and signature that were
not separately reported.';
COMMENT ON COLUMN NIDS.NIDS_FILE.NIDS_FILE IS 'Can contain a hash, a filename or (parts of) a path';
COMMENT ON COLUMN NIDS.NIDS_IPV6_ADDRESS.NAME IS 'An optional name for the IPv6 address';
COMMENT ON COLUMN NIDS.NIDS_IPV6_ADDRESS.COMPANY_ID IS 'A reference to the company this address belongs to. If null, the address is shared among all companies.';
COMMENT ON COLUMN NIDS.NIDS_IPV6_ADDRESS.ADDRESS_1 IS 'The most significant 64 bits of the address.';
COMMENT ON COLUMN NIDS.NIDS_IPV6_ADDRESS.ADDRESS_2 IS 'The least significant 64 bits of the address.';
COMMENT ON COLUMN NIDS.NIDS_IPV6_ADDRESS.COMMENTS IS 'An optional comment to the address.';
COMMENT ON COLUMN NIDS.NIDS_IPV6_PREFIX.ID IS 'The primary key';
COMMENT ON COLUMN NIDS.NIDS_IPV6_PREFIX.NAME IS 'An optional name for the IPv6 prefix';
COMMENT ON COLUMN NIDS.NIDS_IPV6_PREFIX.COMPANY_ID IS 'A reference to the company this prefix belongs to. If null, the prefix is shared among all companies.';
COMMENT ON COLUMN NIDS.NIDS_IPV6_PREFIX.ADDRESS_1 IS 'The higher 64bit of the prefix';
COMMENT ON COLUMN NIDS.NIDS_IPV6_PREFIX.ADDRESS_2 IS 'The lower 64bit of the prefix, usually 0';
COMMENT ON COLUMN NIDS.NIDS_IPV6_PREFIX.MASK IS 'The netmask of this prefix in CIDR notation.';
COMMENT ON COLUMN NIDS.NIDS_IPV6_PREFIX.COMMENTS IS 'An optional comment to the address.';
COMMENT ON COLUMN NIDS.SIGNATURE_GROUP.AUTOMATIC IS 'The boolean property "automatic" defines whether this group has been automatically created or if it was created by a user.';
COMMENT ON TABLE PRX.PRX_POLICY_GROUP IS 'Contains the proxy policy groups';
COMMENT ON TABLE PRX.PRX_POLICY_GROUP_ENTRY IS 'Contains the proxy policy group entries, being either an IPv4/6 network or an AD name';
COMMENT ON TABLE PRX.PRX_POLICY_ITEM IS 'Contains a proxy policy item of a item type in a policy';
COMMENT ON TABLE PRX.PRX_POLICY_ITEM2GROUP IS 'Links a policy item to a group';
COMMENT ON TABLE PRX.URL_CATEGORIZATION IS 'This table tracks the categorization of an URL mentioned in a miscategorization
        with their categories and their types of an categorization. Each URL can have several
        categories forming together a categorization. Furthermore, there are several types of
        categorization per miscategorization request, i.e. the original categorization or the
        suggest categorization. Hence, there will be several entries belonging to one
        URL_MISCATEGORIZATION.';
COMMENT ON TABLE PRX.URL_CATEGORIZATION_TYPE IS 'A helper table providing all valid types for a URL_CATEGORIZATION type.';
COMMENT ON TABLE PRX.URL_CATEGORY IS 'A helper table providing all valid categories an URL can have. This table is periodically updated.';
COMMENT ON TABLE PRX.URL_MISCATEGORIZATION IS 'Meta information of miscategorization report send to Cyren.';
COMMENT ON TABLE PRX.URL_MISCAT_STATUS IS 'A helper table providing all valid status for the URL_MISCATEGORIZATION. ';
COMMENT ON COLUMN PRX.PRX_POLICY_GROUP_ENTRY.IP6_ADDRESS1 IS 'The most significant 64 bits of the address.';
COMMENT ON COLUMN PRX.PRX_POLICY_GROUP_ENTRY.IP6_ADDRESS2 IS 'The least significant 64 bits of the address.';
COMMENT ON COLUMN PRX.PRX_POLICY_GROUP_ENTRY.NETMASK IS 'The netmask';
COMMENT ON COLUMN PRX.PRX_POLICY_GROUP_ENTRY.AUTHENTICATED_GROUP_NAME IS 'The AD name';
COMMENT ON COLUMN PRX.PRX_POLICY_ITEM.LAST_MODIFIED_TIME IS 'The time when the entry was updated the last time';
COMMENT ON COLUMN PRX.PRX_POLICY_ITEM.LAST_MODIFIED_CONTACT_ID IS 'The contact that updated the entry the last time';
COMMENT ON COLUMN PRX.PRX_POLICY_ITEM.CUSTOMER_REFERENCE IS 'A reference to the customer''s incident/ticketing system';
COMMENT ON COLUMN PRX.URL_CATEGORY.NAME IS 'Cyren category name';
COMMENT ON COLUMN PRX.URL_CATEGORY.DESCRIPTION IS 'Cyren category description';
COMMENT ON COLUMN PRX.URL_MISCATEGORIZATION.COMPANY_ID IS 'The company ID this recategorization request belongs to.';
COMMENT ON COLUMN PRX.URL_MISCATEGORIZATION.REF_ID IS 'The Cyren recategorization ID.';
COMMENT ON COLUMN PRX.URL_MISCATEGORIZATION.URL IS 'The reported URL.';
COMMENT ON COLUMN PRX.URL_MISCATEGORIZATION.URL_MISCAT_STATUS_ID IS 'The Status of the miscategorization request, e.g. IN PROGRESS, CHANGED, NOT CHANGED.';
COMMENT ON COLUMN PRX.URL_MISCATEGORIZATION.COMMENTS IS 'The comments written in the recategorization request (provided by user/MC).';
COMMENT ON COLUMN PRX.URL_MISCATEGORIZATION.REASON IS 'The reject reason provided by Cyren on declined recategorization.';
COMMENT ON COLUMN PRX.URL_MISCATEGORIZATION.CREATION_DATE IS 'Date of recategorization creation.';
COMMENT ON COLUMN PRX.URL_MISCATEGORIZATION.LAST_CHECKED_DATE IS 'Date of last check of this request.';
COMMENT ON COLUMN PRX.URL_MISCATEGORIZATION.COMPLETION_DATE IS ' Date of status change from IN PROGRESS => CHANGED/NOT CHANGED.';
COMMENT ON TABLE REPORT.HOST_COUNT IS '
        Table to hold monthly host counts (active hosts). "Temporary" solution until this is fixed in influx.
      ';
COMMENT ON COLUMN REPORT.CHANNELKEY.NAME IS 'The name of this tag, that can be used as a parameter in "value name="tagname"';
COMMENT ON COLUMN REPORT.CHANNELKEY.EXECDAY IS '
        The day of the week on which the query in SQLQUERY should be executed. If this value is set to NULL
        the query will be executed every day. Days of the week are numbered from 0 to 6.
        0 is Monday, 6 is Sunday. If either EXECMINUTE or EXECHOUR are set to NULL, EXECDAY will be ignored.
        ';
COMMENT ON COLUMN REPORT.CHANNELKEY.EXECHOUR IS '
        The hour at which the query in field SQLQUERY should be executed. If this value is set to NULL
        the query will be executed once every hour at the minute specified in the EXECMINUTE field.
        ';
COMMENT ON COLUMN REPORT.CHANNELKEY.EXECMINUTE IS '
        The minute at which the query in field SQLQUERY should be executed. If this value is set to NULL
        the query will be executed once every minute. If both values are NULL
        then EXECMINUTE takes precedence and the query shall be executed once per minute.
        ';
COMMENT ON COLUMN REPORT.CHANNELKEY.EXECINTERVAL IS '
        The execution interval in minutes. This value takes precedence over EXECMINUTE,
        EXECHOUR and EXECDAY if it is set. The query in SQLQUERY will be executed,
        if SYSDATE >= LASTUPDATED + EXECINTERVAL.
        ';
COMMENT ON COLUMN REPORT.CHANNELKEY.HISTORYSIZE IS ' The number of history values that are kept for this tag.';
COMMENT ON COLUMN REPORT.CHANNELKEY.LASTUPDATED IS 'The last time this query has been executed. ';
COMMENT ON COLUMN REPORT.CHANNELKEY.LAST_VALUE_ID IS 'The last value written for this key';
COMMENT ON COLUMN REPORT.CHANNELKEY.SQLQUERY IS 'The query that provides the value for this tag.';
COMMENT ON COLUMN REPORT.CHANNELKEY.DESCRIPTION IS 'A description of what the tag records.';
COMMENT ON COLUMN REPORT.CHANNELVALUE.ID IS 'Unique id for this value.';
COMMENT ON COLUMN REPORT.CHANNELVALUE.CHANNELKEY_ID IS 'foreign key to REPORT.CHANNELKEY.ID.';
COMMENT ON COLUMN REPORT.CHANNELVALUE.TIMESTAMP IS 'A timestamp in Oracle format that records when this value was entered.';
COMMENT ON COLUMN REPORT.CHANNELVALUE.VALUE IS 'The value recorded at TIMESTAMP for the tag referred to by CHANNELKEY_ID.';
COMMENT ON COLUMN REPORT.HOST_COUNT.ID IS 'Unique id for a host count.';
COMMENT ON COLUMN REPORT.HOST_COUNT.DATE_COUNTED IS 'Date on which the count was recorded';
COMMENT ON COLUMN REPORT.HOST_COUNT.HOSTCOUNT IS 'The actual host count';
COMMENT ON COLUMN STOP.COMPANY.SWISS_ONLY_OPS IS 'Can only be accessed by admins in MC center EMEA/Zurich.';
COMMENT ON COLUMN STOP.COMPANY.NO_BITC_OPS IS 'Can not be accessed by admins in MC center BITC/India.';
COMMENT ON COLUMN STOP.COMPANY.ADDRESS_ID IS 'main address';
COMMENT ON COLUMN STOP.COMPANY.DEFAULT_COMPANY_UNIT_ID IS 'Company unit for escalations or changes when service does not provide a company unit';
COMMENT ON COLUMN STOP.COMPANY.ALIASES IS 'Holds new-line separated company alias names';
COMMENT ON COLUMN STOP.COMPANY.SIGN_OFF_NOT_BY_REQUESTER IS 'Boolean to indicate whether a change request can be signed-off by the requester or not.';
COMMENT ON COLUMN STOP.COMPANY.CONNECTIVITY_SLA IS 'Indicates whether connectivity SLA reporting is done for this company or not.';
COMMENT ON COLUMN STOP.COMPANY.SUBPROCESSOR_CONSENT IS 'Indicates whether customer has signed the sub-processor agreement.';
COMMENT ON COLUMN STOP.COMPANY.API_ENABLED IS 'Indicates whether customer has API usage enabled.';
COMMENT ON COLUMN STOP.CONTACT_LIST_MEMBER.CONTACT_ID IS 'When the CONTACT_ID is null, this entry denotes the set of "Local Contacts" which can then be loaded dynamically';
COMMENT ON COLUMN STOP.CONTACT_SYNC.GUID IS 'globally unique id';
COMMENT ON COLUMN STOP.CONTACT_SYNC.SID IS 'active directory "security ID"';
COMMENT ON COLUMN STOP.CONTACT_SYNC.USNCHANGED IS 'active directory "update sequence number"';
COMMENT ON COLUMN STOP.CONTACT_SYNC.DISTINGUISHEDNAME IS 'active directory "distinguishedName" or "dn"';
COMMENT ON COLUMN TIM.BLACKLIST_VALUE.BLACKLIST_VALUE_CATEGORY_ID IS 'FK to BLACKLIST_VALUE_CATEGORY table. Category for the blacklist entry (Spam, Phishing, Malware, Pup).';
COMMENT ON COLUMN TIM.BLACKLIST_VALUE.LAST_MODIFIED_TIME IS 'The time when the entry was updated the last time';
COMMENT ON COLUMN TIM.BLACKLIST_VALUE.LAST_MODIFIED_CONTACT_ID IS 'The contact that updated the entry the last time';
COMMENT ON COLUMN TIM.BLACKLIST_VALUE.BLACKLIST_ZONE_FILE_ID IS 'FK to BLACKLIST_ZONE_FILE table.';
COMMENT ON COLUMN TIM.BLACKLIST_VALUE.CUSTOMER_REFERENCE IS 'A reference to the customer''s incident/ticketing system';
COMMENT ON COLUMN TIM.BLACKLIST_ZONE_FILE.COMPANY_ID IS 'FK to the company. Default scope if NULL.';
COMMENT ON COLUMN TIM.BLACKLIST_ZONE_FILE.BLACKLIST_VALUE_TYPE_ID IS 'FK to BLACKLIST_VALUE_TYPE table. The actual type of the entry (IPv4, IPv6, domain).';
COMMENT ON COLUMN TIM.BLACKLIST_ZONE_FILE.UPDATE_TIMESTAMP IS 'The serial number will be calculated based on the date value in this field.';
COMMENT ON COLUMN TIM.EXCLUSION_LIST_VALUE.COMPANY_ID IS 'FK to the company. Shared scope if NULL.';
COMMENT ON COLUMN TIM.EXCLUSION_LIST_VALUE.EXCLUSION_LIST_VALUE_TYPE_ID IS 'FK to EXCLUSION_LIST_VALUE_TYPE table. The actual type of the entry (IP, email etc).';
COMMENT ON COLUMN TIM.EXCLUSION_LIST_VALUE.LAST_MODIFIED_TIME IS 'The time when the entry was updated the last time';
COMMENT ON COLUMN TIM.EXCLUSION_LIST_VALUE.LAST_MODIFIED_CONTACT_ID IS 'The contact that updated the entry the last time';
COMMENT ON COLUMN TIM.EXCLUSION_LIST_VALUE.CUSTOMER_REFERENCE IS 'A reference to the customer''s incident/ticketing system';
COMMENT ON TABLE TT.CHANGE_REQUEST IS 'A change request inside a change ticket.';
COMMENT ON TABLE TT.CHANGE_REQUEST_STATE IS 'The status of a change request inside a change ticket.';
COMMENT ON TABLE TT.CUST_MAINTENANCE_WINDOW IS 'A service window extension for type customer maintenance window.';
COMMENT ON TABLE TT.MAINTENANCE_WINDOW IS 'A service window extension for type maintenance window.';
COMMENT ON TABLE TT.ROLLOUT_WINDOW IS 'A service window extension for type rollout window.';
COMMENT ON TABLE TT.SERVICE_WINDOW IS 'A service window for a ticket. A ticket can only have one service window.';
COMMENT ON TABLE TT.TICKET_FLOW IS 'Ticket Flow Data that tracks in and out flow as well as queue stay in MCC';
COMMENT ON COLUMN TT.ATTACHMENT.NAME IS 'The files original file name how it was uploaded (after sanitizing). Used
          also as file name when attachment is downloaded.
        ';
COMMENT ON COLUMN TT.ATTACHMENT.FILE_SIZE IS 'File size in bytes';
COMMENT ON COLUMN TT.ATTACHMENT.CREATION_DATE IS 'Timestamp of when the file was persisted.';
COMMENT ON COLUMN TT.CHANGE_REQUEST.DESCRIPTION IS 'Publicly visible description text for the change request';
COMMENT ON COLUMN TT.CHANGE_REQUEST.PRIVATE_DESCRIPTION IS 'Private description text for the change request';
COMMENT ON COLUMN TT.CHANGE_REQUEST.REQUESTER_ID IS 'The contact that requested the change';
COMMENT ON COLUMN TT.CHANGE_REQUEST.APPROVER_ID IS 'The contact that approved or rejected the request (depending on the current state)';
COMMENT ON COLUMN TT.CHANGE_REQUEST.CREATION_DATE IS 'The date and time when the change request has been created';
COMMENT ON COLUMN TT.CHANGE_REQUEST.LAST_REQUEST_DATE IS 'The date and time when the change request has been put into state ''requested'' for the last time';
COMMENT ON COLUMN TT.CHANGE_REQUEST.LAST_ONHOLD_DATE IS 'The date and time when the change request has been put into state ''on hold'' for the last time';
COMMENT ON COLUMN TT.CHANGE_REQUEST.APPROVAL_DENIAL_DATE IS 'The date and time when the change request has been put into state ''approved'' or ''rejected'' for the last time';
COMMENT ON COLUMN TT.CHANGE_REQUEST.COMPLETION_DATE IS 'The date and time when the change request has been put into state ''implemented'', ''denied'' or ''abandoned'' for the last time';
COMMENT ON COLUMN TT.CHANGE_REQUEST.TICKET_ID IS 'Reference to the related ticket';
COMMENT ON COLUMN TT.CHANGE_REQUEST.OTHER_REQUESTER IS 'Free-form text field in case the requester is not a contact.';
COMMENT ON COLUMN TT.CHANGE_REQUEST_STATE.NAME IS 'Descriptive name for the change request status';
COMMENT ON COLUMN TT.CUST_MAINTENANCE_WINDOW.DISABLE_EVENTS IS 'If set to 1 all events that belong to this node (and the ticket''s company) and not explicitly added to a ticket (tt.event_interface.addevent())
          but with tt.event_interface.newevent() will be dropped. This causes no escalation actions or notifications to be processed for
          those events during the service window period. Of course the upcoming event must provide a host (service id), otherwise it is not possible
          to determine, if there is a service window. This function is implemented in tt.event_interface.newevent().';
COMMENT ON COLUMN TT.CUST_MAINTENANCE_WINDOW.COLLECT_EVENTS IS 'If set to 1 all upcoming events not explicitly added to another ticket will get collected into this ticket until the end of the
          service window if it belongs to this host (service id) and this company. Any event that is not dropped (either because
          the specified service is not active or a service window requests event dropping (see above) for this service) will be
          collected into that  ticket with the highest id specifying a matching service window. This functionality is also implemented
          in tt.event_interface.newticket().';
COMMENT ON COLUMN TT.CUST_MAINTENANCE_WINDOW.DISABLE_GUMA_ESCALATION IS 'If set to 1 any escalation to mcc, the customer and the isp caused by GUMA events is turned off during the service
          window. Only for these GUMA events escalation is suppressed: id alert, hardware error, application failure, system failure.
          If an escalation is to be suppressed is determined in event_interface.exec_event_type_actions() by calling the function tt.event_interface.is_esc_supp_active().
          The following conditions must be met for an escalation to be suppressed:
          (1) for the host (service_id the event belongs to a currently open service window must exist, which has the disable_conn_escalation flag set to 1
          (2) the tt.event_type.id must be one out of these 10002 (id alert), 10005 (hardware error), 10007 (application failure) or 10009 (system failure)
          When the escalation is to be suppressed, no action will be carried out by tt.event_interface.exec_event_type_actions().
        ';
COMMENT ON COLUMN TT.CUST_MAINTENANCE_WINDOW.DISABLE_CONN_ESCALATION IS 'If set to 1 any escalation to mcc, the customer and the isp caused by connection down (TT.EVENT_ACTION.ID is 2) is turned off during the service window.
          If an escalation is to be suppressed is determined in event_interface.exec_event_type_actions() by calling the function tt.event_interface.is_esc_supp_active().
          The following conditions must be met for an escalation to be suppressed:
          (1) for the host (service_id the event belongs to a currently open service window must exist, which has the disable_conn_escalation flag set to 1
          (2) the tt.event_action.id must be either 2 (connection down escalation)
          When the escalation is to be suppressed, no action will be carried out by tt.event_interface.exec_event_type_actions().
        ';
COMMENT ON COLUMN TT.CUST_MAINTENANCE_WINDOW.DISABLE_NOTIFICATION IS 'If set to 1 notification for any added event to this ticket is turned off during the service window.
          However the notification ticket bound events (resolved, manual event added and waiting) and test notifications
          will not be affected.
          Implementation is in tt.osag_notify.is_notify_suppressor_active() which checks if there is a service window open for the ticket that has
          the disable_notification flag set to 1. If so the procedure notify.event_notify() leaves out any registered notifications for this event tpye.
          It does handle the ticket specific notifications anyway.';
COMMENT ON COLUMN TT.EVENT.SIGN_OFF_OK IS '
This is one of the few legitimate places to define a "nullable ''boolean''",
cause for older events, the sticky signoff status is just not known, and we
need to know that.
';
COMMENT ON COLUMN TT.EVENT_ACTION.PROCEDURE_NAME IS 'plsql procedure that is called
(if PROCEDURE_KEY_ID is defined and a corresponding VALUE is found for the host on
which the event occured, that value is used as the procedure name instead)';
COMMENT ON COLUMN TT.EVENT_ACTION.PROCEDURE_KEY_ID IS 'db property that specifies which procedure should be called, see also PROCEDURE_NAME';
COMMENT ON COLUMN TT.EVENT_NOTIFICATION.ID IS 'Notification ID';
COMMENT ON COLUMN TT.EVENT_NOTIFICATION.LOGIN_ID IS 'Login / Contact that is notified';
COMMENT ON COLUMN TT.EVENT_NOTIFICATION.EVENT_NOTIFICATION_TYPE_ID IS 'Type of notification (e.g. SMS, email)';
COMMENT ON COLUMN TT.EVENT_NOTIFICATION.EVENT_TYPE_ID IS 'Matches kind of event (e.g. ISP outage)';
COMMENT ON COLUMN TT.EVENT_NOTIFICATION.EVENT_TYPE_GROUP_ID IS 'Matches group of events (e.g. VPN-related events)';
COMMENT ON COLUMN TT.EVENT_NOTIFICATION.COMPANY_ID IS 'Matches Company';
COMMENT ON COLUMN TT.EVENT_NOTIFICATION.SERVICE_ID IS 'Matches MSS Service (e.g. cust-prx-1, cust-prx-2)';
COMMENT ON COLUMN TT.EVENT_NOTIFICATION.COMPANY_UNIT_ID IS 'Matches Company Unit';
COMMENT ON COLUMN TT.EVENT_NOTIFICATION.SERVICE_TYPE_ID IS 'Matches Service Type (e.g. Security Gateway)';
COMMENT ON COLUMN TT.EVENT_NOTIFICATION.TICKET_ID IS 'Matches a specific Ticket';
COMMENT ON COLUMN TT.EVENT_NOTIFICATION.TICKET_TYPE_ID IS 'Matches Ticket Type (e.g. trouble ticket)';
COMMENT ON COLUMN TT.EVENT_NOTIFICATION.REGEXP IS 'Matches regular expression on event public content';
COMMENT ON COLUMN TT.EVENT_NOTIFICATION.ONLY_IF_WORKER IS 'If this is non-0, the notification is only sent if the notification owner is the
assigned worker of the associated ticket. Obviously, this is an OSAG-only feature.';
COMMENT ON COLUMN TT.EVENT_NOTIFICATION_TYPE.ID IS 'Event Notification Type ID';
COMMENT ON COLUMN TT.EVENT_NOTIFICATION_TYPE.NAME IS 'Name of notification type.';
COMMENT ON COLUMN TT.EVENT_TYPE.IS_NOTIFIED IS 'If set to 1, MC users can subscribe to event notifications for the specific event type.';
COMMENT ON COLUMN TT.EVENT_TYPE.SMS_MESSAGE_TEMPLATE_ID IS 'Specifies which event type message template is used if a SMS notification is sent for an event of this event type.';
COMMENT ON COLUMN TT.EVENT_TYPE.EMAIL_MESSAGE_TEMPLATE_ID IS 'Specifies which event type message template is used if an email notification is sent for an event of this event type.';
COMMENT ON COLUMN TT.EVENT_TYPE.PINNABLE IS 'Whether events of this type can be pinned or not.';
COMMENT ON COLUMN TT.EVENT_TYPE.AUTOPIN IS 'Whether event will be pinned when created or not';
COMMENT ON COLUMN TT.EVENT_TYPE2EVENT_TYPE_GROUP.EVENT_TYPE_GROUP_ID IS 'Group ID';
COMMENT ON COLUMN TT.EVENT_TYPE2EVENT_TYPE_GROUP.EVENT_TYPE_ID IS 'Event type belonging to that group.';
COMMENT ON COLUMN TT.EVENT_TYPE_GROUP.ID IS 'Group ID';
COMMENT ON COLUMN TT.EVENT_TYPE_GROUP.NAME IS 'Displayable name for the group.';
COMMENT ON COLUMN TT.EVENT_TYPE_GROUP.DESCRIPTION IS 'Description for the help popup window.';
COMMENT ON COLUMN TT.EVENT_TYPE_MESSAGE.ID IS 'Event type message ID';
COMMENT ON COLUMN TT.EVENT_TYPE_MESSAGE.SUBJECT_TEMPLATE IS 'Event type subject template. This subject can be used for email event notifications.';
COMMENT ON COLUMN TT.EVENT_TYPE_MESSAGE.MESSAGE_TEMPLATE IS 'Event type message template. This message template can be used for email or SMS event notifications.';
COMMENT ON COLUMN TT.MAINTENANCE_WINDOW.DISABLE_EVENTS IS 'If set to 1 all events that belong to this node (and the ticket''s company) and not explicitly added to a ticket (tt.event_interface.addevent())
          but with tt.event_interface.newevent() will be dropped. This causes no escalation actions or notifications to be processed for
          those events during the service window period. Of course the upcoming event must provide a host (service id), otherwise it is not possible
          to determine, if there is a service window. This function is implemented in tt.event_interface.newevent().';
COMMENT ON COLUMN TT.MAINTENANCE_WINDOW.COLLECT_EVENTS IS 'If set to 1 all upcoming events not explicitly added to another ticket will get collected into this ticket until the end of the
          service window if it belongs to this host (service id) and this company. Any event that is not dropped (either because
          the specified service is not active or a service window requests event dropping (see above) for this service) will be
          collected into that  ticket with the highest id specifying a matching service window. This functionality is also implemented
          in tt.event_interface.newticket().';
COMMENT ON COLUMN TT.MAINTENANCE_WINDOW.DISABLE_GUMA_ESCALATION IS 'If set to 1 any escalation to mcc, the customer and the isp caused by GUMA events is turned off during the service
          window. Only for these GUMA events escalation is suppressed: id alert, hardware error, application failure, system failure.
          If an escalation is to be suppressed is determined in event_interface.exec_event_type_actions() by calling the function tt.event_interface.is_esc_supp_active().
          The following conditions must be met for an escalation to be suppressed:
          (1) for the host (service_id the event belongs to a currently open service window must exist, which has the disable_conn_escalation flag set to 1
          (2) the tt.event_type.id must be one out of these 10002 (id alert), 10005 (hardware error), 10007 (application failure) or 10009 (system failure)
          When the escalation is to be suppressed, no action will be carried out by tt.event_interface.exec_event_type_actions().
        ';
COMMENT ON COLUMN TT.MAINTENANCE_WINDOW.DISABLE_CONN_ESCALATION IS 'If set to 1 any escalation to mcc, the customer and the isp caused by connection down (TT.EVENT_ACTION.ID is 2) is turned off during the service window.
          If an escalation is to be suppressed is determined in event_interface.exec_event_type_actions() by calling the function tt.event_interface.is_esc_supp_active().
          The following conditions must be met for an escalation to be suppressed:
          (1) for the host (service_id the event belongs to a currently open service window must exist, which has the disable_conn_escalation flag set to 1
          (2) the tt.event_action.id must be either 2 (connection down escalation)
          When the escalation is to be suppressed, no action will be carried out by tt.event_interface.exec_event_type_actions().
        ';
COMMENT ON COLUMN TT.MAINTENANCE_WINDOW.DISABLE_NOTIFICATION IS 'If set to 1 notification for any added event to this ticket is turned off during the service window.
          However the notification ticket bound events (resolved, manual event added and waiting) and test notifications
          will not be affected.
          Implementation is in tt.osag_notify.is_notify_suppressor_active() which checks if there is a service window open for the ticket that has
          the disable_notification flag set to 1. If so the procedure notify.event_notify() leaves out any registered notifications for this event tpye.
          It does handle the ticket specific notifications anyway.';
COMMENT ON COLUMN TT.SERVICE_WINDOW.START_DATE IS 'The date when the service window begins in UTC (as a convention all dates should be stored in UTC).';
COMMENT ON COLUMN TT.SERVICE_WINDOW.END_DATE IS 'The date when the service window ends in UTC (as a convention all dates should be stored in UTC).';
COMMENT ON COLUMN TT.TICKET.EVENT_NOTIFY_COUNT IS 'counts automatic events notified in this ticket (based on the event_notification table)';
COMMENT ON COLUMN TT.TICKET.EVENT_NOTIFY_COUNT_OSAG IS 'counts automatic events notified in this ticket for OSAG admins';
COMMENT ON COLUMN TT.TICKET.CUSTOMER_REFERENCE IS 'a string that is prefixed to all outgoing notifications';
COMMENT ON COLUMN TT.TICKET.PARTNER_REFERENCE IS 'used for partner tickets associated with this ticket';
COMMENT ON COLUMN TT.TICKET.EMERGENCY IS 'boolean: 1 means that this is an emergency ticket, 0 that it is not';
COMMENT ON COLUMN TT.TICKET.ALWAYS_VISIBLE IS 'boolean: 1 means that this ticket is shown on top of all customer pages, 0 that it is not';
COMMENT ON COLUMN TT.TICKET.HANDLED_BY_MCC IS 'boolean: 1 means that this ticket is processed by MCC';
COMMENT ON COLUMN TT.TICKET.ESCALATION_STATUS_ID IS 'escalation status of the ticket';
COMMENT ON COLUMN TT.TICKET.LAST_ESCALATION_DATE IS 'date of last escalation of the ticket';
COMMENT ON COLUMN TT.TICKET.CUSTOMER_TICKET_RATING_ID IS 'The newest customer rating regarding the ticket handling of this ticket';
COMMENT ON COLUMN TT.TICKET.ENGINEER_TICKET_RATING_ID IS 'The newest engineer rating regarding the ticket handling of this ticket';
COMMENT ON COLUMN TT.TICKET.TYPE_CONFIRMED IS 'Boolean: Whether the ticket type has been confirmed';
COMMENT ON COLUMN TT.TICKET.SERVICE_CONFIRMED IS 'Boolean: Whether the service has been confirmed';
COMMENT ON COLUMN TT.TICKET.FAST_RESOLVABLE IS 'Boolean: 1 means the ticket can be resolved without adding an event';
COMMENT ON COLUMN TT.TICKET.LAST_PUBLIC_EVENT_ID IS 'The ID of the last public event of this ticket (non-history, non-notification)';
COMMENT ON COLUMN TT.TICKET.RECOVERABLE_STATUS_ID IS 'The ID of the recoverable ticket status (if any)';
COMMENT ON COLUMN TT.TICKET.SUMMARY_RELEVANT_EVENTS_COUNT IS 'Counter for the number of events since the last summary update.';
COMMENT ON COLUMN TT.TICKET.LAST_DEFERRAL_DATE IS 'The date of the last deferral/waiting/third-party change (yes, reused).';
COMMENT ON COLUMN TT.TICKET.LAST_DEFERRAL_ESCALATED IS 'True means "escalate after deferral" was set when the ticket was deferred the last time.';
COMMENT ON COLUMN TT.TICKET.UPDATE_TIMESTAMP IS 'Tells when the row was last updated. This column is updated by the trigger tt.ticket_update_trg.';
COMMENT ON COLUMN TT.TICKET.WAS_EMERGENCY IS 'boolean: 1 means that this ticket had the emergency flag set at least once, 0 that it never was an emergency';
COMMENT ON COLUMN TT.TICKET.STEPS_TOTAL IS 'The total number of steps in the Todo List of this ticket.';
COMMENT ON COLUMN TT.TICKET.STEPS_COMPLETED IS 'The number of completed steps in the Todo List of this ticket.';
COMMENT ON COLUMN TT.TICKET.TODO_RELEVANT_EVENTS_COUNT IS 'Counter for the number of relevant events since the last todo list update.';
COMMENT ON COLUMN TT.TICKET.UX_TIMEOUT IS 'The timeout until which MC should update the ticket with an event.';
COMMENT ON COLUMN TT.TICKET.UX_TIMEOUT_START IS 'Defines the time from which the ux timeout should start.';
COMMENT ON COLUMN TT.TICKET.MERGED_INTO_TICKET_ID IS 'Specifies the ticket this ticket was merged into. Requires status to be set to merged (110)';
COMMENT ON COLUMN TT.TICKET_DOCS_PAGE.ID IS 'Ticket-to-Docs page Reference ID';
COMMENT ON COLUMN TT.TICKET_DOCS_PAGE.TICKET_ID IS 'The ticket to which the Docs page is linked';
COMMENT ON COLUMN TT.TICKET_DOCS_PAGE.PAGE_ID IS 'The ID of the referenced Docs page';
COMMENT ON COLUMN TT.TICKET_DOCS_PAGE.PAGE_VERSION IS 'The version of the referenced Docs page';
COMMENT ON COLUMN TT.TICKET_DOCS_PAGE.HOT_ISSUE IS 'Boolean: Whether this page was labeled as hot issue when it was added to the ticket';
COMMENT ON COLUMN TT.TICKET_FLOW.TICKET_ID IS 'Ticket ID for to which the flow state entry belongs to';
COMMENT ON COLUMN TT.TICKET_FLOW.FLOW_IN_DATE IS 'timestamp when the ticket entered the MCC queue, moment of in-flow';
COMMENT ON COLUMN TT.TICKET_FLOW.FLOW_OUT_DATE IS 'timestamp when the ticket left the MCC queue, moment of out-flow, may be null for tickets currently in the queue';
COMMENT ON COLUMN TT.TICKET_FLOW.OPEN_TIME IS 'the time in seconds the ticket spent in open status while it was in the queue';
COMMENT ON COLUMN TT.TICKET_RATING.ID IS 'Ticket rating ID';
COMMENT ON COLUMN TT.TICKET_RATING.RATING IS 'The rating value, must be in {1,2,3,4,5}';
COMMENT ON COLUMN TT.TICKET_RATING.EVENT_ID IS 'The rating event to which this rating belongs';
COMMENT ON COLUMN TT.TICKET_REQUEST_CLASSIFICATION.CLASSIFICATION IS 'The classification value: 1 = very precise, 2 = standard, 3 = imprecise';
COMMENT ON COLUMN TT.TICKET_TIME_STATISTIC.OPEN_TIME IS 'The time the ticket was in open state in seconds';
COMMENT ON COLUMN TT.TICKET_TIME_STATISTIC.WAITING_TIME IS 'The time the ticket was in waiting state in seconds';
COMMENT ON COLUMN TT.TICKET_TIME_STATISTIC.THIRD_PARTY_TIME IS 'The time the ticket was in third-party state in seconds';
COMMENT ON COLUMN TT.TICKET_TIME_STATISTIC.DEFERRED_TIME IS 'The time the ticket was in deferred state in seconds';
COMMENT ON COLUMN TT.TICKET_TIME_STATISTIC.RESOLVED_TIME IS 'The time the ticket was in resolved status in seconds';
COMMENT ON COLUMN TT.TODO_ITEM.SEQ_NO IS 'The sequence number of this item in its todo list';
COMMENT ON COLUMN TT.TODO_ITEM.UPDATE_TIMESTAMP IS 'Tells when the row was last updated. This column is updated by the trigger tt.todo_item_update_trg.';
COMMENT ON COLUMN VPN.AZURE_VWAN_TUNNEL.PEER_IP_1 IS 'The higher 64bit of the prefix in case of IPv6 or null in case of IPv4.';
COMMENT ON COLUMN VPN.AZURE_VWAN_TUNNEL.PEER_IP_2 IS 'The lower 64bit of the prefix (IPv4/v6)';
COMMENT ON COLUMN VPN.PARTITION.TUNNELMODE IS ' 0 = no tunnels
 1 = full mesh
 2 = star topology';
COMMENT ON COLUMN VPN.PARTNER_ACCESS_RANGE.RANGE_NETWORK_ADDRESS_1 IS 'The higher 64bit of the prefix in case of IPv6 or null in case of IPv4.';
COMMENT ON COLUMN VPN.PARTNER_ACCESS_RANGE.RANGE_NETWORK_ADDRESS_2 IS 'The lower 64bit of the prefix (IPv4/v6)';
COMMENT ON COLUMN VPN.PARTNER_ACCESS_RANGE.RANGE_NETWORK_MASK IS 'The netmask of this prefix in CIDR notation.';
COMMENT ON COLUMN VPN.PARTNER_MONITORING.MONITORING_IP_2 IS 'The lower 64bit of the prefix (IPv4/v6)';
COMMENT ON COLUMN VPN.PARTNER_MONITORING.MONITORING_IP_1 IS 'The higher 64bit of the prefix in case of IPv6 or null in case of IPv4.';
COMMENT ON COLUMN VPN.PARTNER_PHASE1.PARTNER_IP1 IS 'The most significant 64 bits of the IPv6 address. Not set in case of an IPv4 address.';
COMMENT ON COLUMN VPN.PARTNER_PHASE1.PARTNER_IP2 IS 'The least significant 64 bits of the IPv4/v6 address.';
COMMENT ON COLUMN VPN.PARTNER_PHASE2.LOCAL_NETWORK_ADDRESS_1 IS 'The higher 64bit of the prefix in case of IPv6 or null in case of IPv4.';
COMMENT ON COLUMN VPN.PARTNER_PHASE2.LOCAL_NETWORK_ADDRESS_2 IS 'The lower 64bit of the prefix (IPv4/v6)';
COMMENT ON COLUMN VPN.PARTNER_PHASE2.LOCAL_NETWORK_MASK IS 'The netmask of this prefix in CIDR notation.';
COMMENT ON COLUMN VPN.PARTNER_PHASE2.PARTNER_NETWORK_ADDRESS_1 IS 'The higher 64bit of the prefix in case of IPv6 or null in case of IPv4.';
COMMENT ON COLUMN VPN.PARTNER_PHASE2.PARTNER_NETWORK_ADDRESS_2 IS 'The lower 64bit of the prefix (IPv4/v6)';
COMMENT ON COLUMN VPN.PARTNER_PHASE2.PARTNER_NETWORK_MASK IS 'The netmask of this prefix in CIDR notation.';
COMMENT ON COLUMN VPN.PARTNER_PHASE2.INTERN_NETWORK_ADDRESS_1 IS 'The higher 64bit of the prefix in case of IPv6 or null in case of IPv4.';
COMMENT ON COLUMN VPN.PARTNER_PHASE2.INTERN_NETWORK_ADDRESS_2 IS 'The lower 64bit of the prefix (IPv4/v6)';
COMMENT ON COLUMN VPN.PARTNER_PHASE2.INTERN_NETWORK_MASK IS 'The netmask of this prefix in CIDR notation.';
COMMENT ON COLUMN VPN.PARTNER_PHASE2.NAT_IP1 IS 'The most significant 64 bits of the IPv6 address. Not set in case of an IPv4 address.';
COMMENT ON COLUMN VPN.PARTNER_PHASE2.NAT_IP2 IS 'The least significant 64 bits of the IPv4/v6 address.';
COMMENT ON COLUMN VPN.PARTNER_PHASE2.LOCAL_PING_IP1 IS 'The most significant 64 bits of the IPv6 local ping address. Not set in case of an IPv4 address.';
COMMENT ON COLUMN VPN.PARTNER_PHASE2.LOCAL_PING_IP2 IS 'The least significant 64 bits of the IPv4/v6 local ping address.';
COMMENT ON COLUMN VPN.PARTNER_STATIC_NET.LOCAL_NETWORK_ADDRESS_1 IS 'The higher 64bit of the prefix in case of IPv6 or null in case of IPv4.';
COMMENT ON COLUMN VPN.PARTNER_STATIC_NET.LOCAL_NETWORK_ADDRESS_2 IS 'The lower 64bit of the prefix (IPv4/v6)';
COMMENT ON COLUMN VPN.PARTNER_STATIC_NET.LOCAL_NETWORK_MASK IS 'The netmask of this prefix in CIDR notation.';
COMMENT ON COLUMN VPN.TUNNEL.TUNNELMODE IS 'Any value different than 0 means the tunnel is active! The positive
value just indicates the SOURCE of the setting

 0 = disabled
 1 = enabled (source: full mesh mode in partition)
 2 = enabled (source: hub mode in partition)
 3 = enabled (source: explicitly enabled in VPN matrix)';
COMMENT ON COLUMN VPN.TUNNEL.IPV6_TUNNEL IS 'Tells whether the tunnel is an IPv6 one or not.';

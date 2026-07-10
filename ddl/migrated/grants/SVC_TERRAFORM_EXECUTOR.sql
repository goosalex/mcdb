GRANT SELECT ON "mss"."key" TO "svc_terraform_executor";
GRANT SELECT ON "mss"."mv_value_host" TO "svc_terraform_executor";
GRANT SELECT ON "mss"."value" TO "svc_terraform_executor";
GRANT SELECT ON "stop"."company" TO "svc_terraform_executor";
GRANT USAGE ON SCHEMA "stop" TO "svc_terraform_executor";
GRANT USAGE ON SCHEMA "mss" TO "svc_terraform_executor";
GRANT  "mss_login_user" TO "svc_terraform_executor";

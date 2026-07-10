GRANT SELECT ON "auth"."login" TO "svc_automation_dbwatcher";
GRANT SELECT ON "tt"."change_request" TO "svc_automation_dbwatcher";
GRANT SELECT ON "tt"."event" TO "svc_automation_dbwatcher";
GRANT SELECT ON "tt"."ticket" TO "svc_automation_dbwatcher";
GRANT USAGE ON SCHEMA "auth" TO "svc_automation_dbwatcher";
GRANT USAGE ON SCHEMA "tt" TO "svc_automation_dbwatcher";
GRANT  "mss_login_user" TO "svc_automation_dbwatcher";

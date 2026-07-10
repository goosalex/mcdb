GRANT REFERENCES ON "mss"."object_type" TO "mcaudit";
GRANT SELECT ON "mss"."object_type" TO "mcaudit";
GRANT REFERENCES ON "stop"."company" TO "mcaudit";
GRANT REFERENCES ON "stop"."contact" TO "mcaudit";
GRANT REFERENCES ON "tt"."ticket" TO "mcaudit";
GRANT USAGE ON SCHEMA "tt" TO "mcaudit";
GRANT USAGE ON SCHEMA "mss" TO "mcaudit";
GRANT USAGE ON SCHEMA "stop" TO "mcaudit";
GRANT  "mss_schema_user" TO "mcaudit";

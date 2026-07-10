GRANT REFERENCES ON "mss"."address" TO "esp";
GRANT REFERENCES ON "mss"."country" TO "esp";
GRANT REFERENCES ON "stop"."company" TO "esp";
GRANT SELECT ON "stop"."company" TO "esp";
GRANT REFERENCES ON "stop"."contact" TO "esp";
GRANT SELECT ON "stop"."contact" TO "esp";
GRANT USAGE ON SCHEMA "mss" TO "esp";
GRANT USAGE ON SCHEMA "stop" TO "esp";
GRANT  "mss_schema_user" TO "esp";

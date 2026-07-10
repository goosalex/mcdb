GRANT REFERENCES ON "mss"."configuration_group" TO "certs";
GRANT REFERENCES ON "mss"."host" TO "certs";
GRANT REFERENCES ON "mss"."service" TO "certs";
GRANT REFERENCES ON "stop"."company" TO "certs";
GRANT REFERENCES ON "tt"."ticket" TO "certs";
GRANT USAGE ON SCHEMA "stop" TO "certs";
GRANT USAGE ON SCHEMA "tt" TO "certs";
GRANT USAGE ON SCHEMA "mss" TO "certs";
GRANT  "mss_schema_user" TO "certs";

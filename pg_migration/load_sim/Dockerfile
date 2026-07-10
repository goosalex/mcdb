# nosemgrep: dockerfile-source-not-pinned
FROM perl:5.36-threaded

WORKDIR /app

# Install required Perl modules
RUN cpan -i DBI DBD::Pg Time::HiRes && cpan -i threads Thread::Queue Thread::Semaphore

# Copy the script
COPY osdb/mcdb/pg_migration/load_sim/tunnel_load_multi.pl /app/
COPY osdb/mcdb/pg_migration/load_sim/tunnel_ids.csv /app/

# Make script executable
RUN chmod +x /app/tunnel_load_multi.pl

# Environment variables for configuration
ENV CSV_FILE="tunnel_ids.csv" \
    DB_NAME="mcdb" \
    DB_HOST="::1" \
    DB_PORT="5432" \
    DB_USER="postgres" \
    DB_PASS="password" \
    SLEEP_INTERVAL="0.01"
# nosemgrep: missing-user
CMD ["perl", "/app/tunnel_load_multi.pl"]
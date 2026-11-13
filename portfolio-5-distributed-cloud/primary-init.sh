#!/bin/bash
# Runs once, when the primary is first created.
# 1. Create a user that the replica uses to copy data.
# 2. Allow that user to make replication connections.
set -e
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
     -c "CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'repl_password';"
echo "host replication replicator all scram-sha-256" >> "$PGDATA/pg_hba.conf"

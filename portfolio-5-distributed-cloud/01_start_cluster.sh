#!/usr/bin/env bash
# =====================================================================
# MIT 8103 Portfolio 5: start the primary + replica and load NRS data
#
# Always starts FRESH (old cluster data is deleted first), then loads
# the small Portfolio 1 data into the PRIMARY ONLY. Replication copies
# it to the replica by itself.
#
# Run from anywhere:   bash portfolio-5-distributed-cloud/01_start_cluster.sh
# Stop when finished:  docker compose -f portfolio-5-distributed-cloud/docker-compose.yml down -v
# =====================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
P1="$HERE/../portfolio-1-database-design"
COMPOSE=(docker compose -f "$HERE/docker-compose.yml")

echo "Starting a fresh primary + replica..."
"${COMPOSE[@]}" down -v > /dev/null 2>&1 || true
"${COMPOSE[@]}" up -d 2>&1 | grep -E "Started|Error" || true

wait_ready() {
  until docker exec "$1" pg_isready -U nrs_admin -d nrs_tax_db > /dev/null 2>&1; do sleep 1; done
}
wait_ready nrs_pg_primary
wait_ready nrs_pg_replica
echo "Both servers are up."

echo "Loading Portfolio 1 data into the PRIMARY only..."
docker exec -i nrs_pg_primary psql -q -v ON_ERROR_STOP=1 -U nrs_admin -d nrs_tax_db < "$P1/01_schema.sql" 2>/dev/null
docker exec -i nrs_pg_primary psql -q -v ON_ERROR_STOP=1 -U nrs_admin -d nrs_tax_db < "$P1/02_seed_data.sql" > /dev/null
echo "Done."

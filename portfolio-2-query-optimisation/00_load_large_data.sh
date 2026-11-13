#!/usr/bin/env bash
# =====================================================================
# MIT 8103 Portfolio 2: load the LARGE synthetic data set
#
# Rebuilds the Portfolio 1 schema and loads it at scale 25, which gives
# 50,000 taxpayers and about 460,000 tax returns. Takes about 3 minutes.
#
# Run from anywhere:  bash portfolio-2-query-optimisation/00_load_large_data.sh
# To go back to the small Portfolio 1 data, run the Portfolio 1 scripts again.
# =====================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
P1="$HERE/../portfolio-1-database-design"
SCALE="${SCALE:-25}"

psql_nrs() { docker exec -i nrs_postgres psql -v ON_ERROR_STOP=1 -q -U nrs_admin -d nrs_tax_db "$@"; }

echo "Creating schema..."
psql_nrs < "$P1/01_schema.sql" 2>/dev/null
echo "Loading data at scale $SCALE (please wait)..."
psql_nrs -v scale="$SCALE" < "$P1/02_seed_data.sql" | tail -14
echo "Done."

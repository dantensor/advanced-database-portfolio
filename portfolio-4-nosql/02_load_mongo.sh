#!/usr/bin/env bash
# =====================================================================
# MIT 8103 Portfolio 4: copy the NRS taxpayers from PostgreSQL to MongoDB
#
#   PostgreSQL --(01_build_documents.sql)--> JSON documents --> MongoDB
#
# Creates database "nrs", collection "taxpayers" (replaces it if it exists).
# Use the small Portfolio 1 data (2,000 taxpayers).
#
# Run from anywhere:  bash portfolio-4-nosql/02_load_mongo.sh
# =====================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

docker exec -i nrs_postgres psql -X -q -A -t -v ON_ERROR_STOP=1 -U nrs_admin -d nrs_tax_db \
    < "$HERE/01_build_documents.sql" \
  | docker exec -i nrs_mongo mongoimport --quiet --db nrs --collection taxpayers --drop

echo "Documents in MongoDB collection nrs.taxpayers:"
docker exec nrs_mongo mongosh nrs --quiet --eval 'db.taxpayers.countDocuments()'

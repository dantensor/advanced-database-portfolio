#!/usr/bin/env bash
# =====================================================================
# MIT 8103 Portfolio 5: replication and failover demo
#
#   Demo 1  Replication status (is the replica connected and streaming?)
#   Demo 2  Write on the primary -> it appears on the replica
#   Demo 3  The replica is READ-ONLY
#   Demo 4  Failover: the primary "crashes", the replica is promoted
#           and becomes the new primary
#
# Run after 01_start_cluster.sh:
#   bash portfolio-5-distributed-cloud/02_replication_demo.sh
# Output is also saved to results/replication_demo.txt
# NOTE: demo 4 stops the primary. Run 01_start_cluster.sh again to reset.
# =====================================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HERE/results"

primary() { docker exec -i nrs_pg_primary sh -c 'psql -X -q -U nrs_admin -d nrs_tax_db 2>&1'; }
replica() { docker exec -i nrs_pg_replica sh -c 'psql -X -q -U nrs_admin -d nrs_tax_db 2>&1'; }

{
echo "################ Demo 1: replication status ################"
echo "On the PRIMARY - who is copying from me?"
primary <<'SQL'
SELECT client_addr, state, sync_state, replay_lag
FROM pg_stat_replication;
SQL
echo "Is each server a standby (read-only copy)?"
echo "  primary: $(echo 'SELECT pg_is_in_recovery();' | primary | sed -n 3p)   (f = no, it is the primary)"
echo "  replica: $(echo 'SELECT pg_is_in_recovery();' | replica | sed -n 3p)   (t = yes, it is a standby)"

echo
echo "################ Demo 2: write on primary, read on replica ################"
echo "[PRIMARY] register a new taxpayer, TIN 2000000002"
primary <<'SQL'
SET search_path TO nrs;
WITH t AS (
  INSERT INTO taxpayer (tin, taxpayer_type, office_id, registration_date)
  VALUES ('2000000002', 'I', 1, DATE '2026-11-13') RETURNING taxpayer_id)
INSERT INTO individual_taxpayer (taxpayer_id, first_name, last_name, date_of_birth)
SELECT taxpayer_id, 'Replica', 'Demo', DATE '1995-06-01' FROM t;
SQL
sleep 1
echo "[REPLICA] one second later, look for the same taxpayer:"
replica <<'SQL'
SELECT tin, taxpayer_name FROM nrs.v_taxpayer_name WHERE tin = '2000000002';
SQL
echo "[PRIMARY] how long did the replica take to apply that change? (replication lag)"
primary <<'SQL'
SELECT state, sync_state, replay_lag FROM pg_stat_replication;
SQL

echo
echo "################ Demo 3: the replica is read-only ################"
echo "[REPLICA] try to change data:"
replica <<'SQL'
UPDATE nrs.taxpayer SET status = 'CLOSED' WHERE tin = '2000000002';
SQL
echo "[REPLICA] reading still works:"
replica <<'SQL'
SELECT count(*) AS taxpayers FROM nrs.taxpayer;
SQL

echo
echo "################ Demo 4: failover ################"
echo "Step 1: the PRIMARY crashes (container killed)"
docker kill nrs_pg_primary > /dev/null
sleep 2
echo "Step 2: [REPLICA] reads still work (taxpayers can still view their records):"
replica <<'SQL'
SELECT count(*) AS taxpayers FROM nrs.taxpayer;
SQL
echo "Step 3: [REPLICA] but writes are refused (no primary any more):"
replica <<'SQL'
UPDATE nrs.taxpayer SET status = 'CLOSED' WHERE tin = '2000000002';
SQL
echo "Step 4: PROMOTE the replica to be the new primary:"
replica <<'SQL'
SELECT pg_promote() AS promoted;
SQL
echo "Step 5: [NEW PRIMARY] is it still a standby?  $(echo 'SELECT pg_is_in_recovery();' | replica | sed -n 3p)   (f = no, it is now the primary)"
echo "Step 6: [NEW PRIMARY] writes work again:"
replica <<'SQL'
UPDATE nrs.taxpayer SET status = 'CLOSED' WHERE tin = '2000000002';
SELECT tin, status FROM nrs.taxpayer WHERE tin = '2000000002';
SQL
echo "Failover complete. No committed data was lost."
} 2>&1 | tee "$HERE/results/replication_demo.txt"

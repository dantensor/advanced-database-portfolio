#!/usr/bin/env bash
# =====================================================================
# MIT 8103 Portfolio 3: concurrency demos (two sessions at once)
#
# Each demo starts two database sessions, A and B, at the same time.
# They act like two tax officers working on the same taxpayer.
# pg_sleep() pauses make the steps happen in a fixed order:
#     t=0s  A starts      t=1s  B starts      t=2s, t=3s ... next steps
#
# Run from anywhere (after 01_setup.sql):
#   bash portfolio-3-transactions-concurrency/03_concurrency_demos.sh
# Output is also saved in portfolio-3-transactions-concurrency/results/
# =====================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/results"
mkdir -p "$OUT"

# One database session. Reads SQL from stdin. Errors are shown in order.
session() { docker exec -i nrs_postgres sh -c 'psql -X -q -U nrs_admin -d nrs_tax_db 2>&1'; }

reset_credit() {
  echo "SET search_path TO nrs; UPDATE tax_credit SET balance = 100000;" | session > /dev/null
}

# Run session A and session B at the same time, then print both outputs.
# $1 = demo name, $2 = file with A's SQL, $3 = file with B's SQL
run_pair() {
  local name="$1"
  session < "$2" > "$OUT/.a.txt" &
  local pid_a=$!
  session < "$3" > "$OUT/.b.txt" &
  local pid_b=$!
  wait "$pid_a" "$pid_b" || true
  {
    echo "################ $name ################"
    echo "----- Session A -----"; cat "$OUT/.a.txt"
    echo "----- Session B -----"; cat "$OUT/.b.txt"
    echo "----- Final balance -----"
    echo "SELECT taxpayer_id, balance FROM nrs.tax_credit WHERE taxpayer_id = 1;" | session
  } | tee "$OUT/$name.txt"
  rm -f "$OUT/.a.txt" "$OUT/.b.txt"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------
# DEMO 1: LOST UPDATE (the problem)
# Both officers read N100,000, both think there is enough credit for
# N60,000, both write. N120,000 is spent from a N100,000 credit, and the
# balance shows N40,000. Officer A's update has been "lost".
# ---------------------------------------------------------------------
cat > "$TMP/a.sql" <<'SQL'
SET search_path TO nrs;
BEGIN;
SELECT balance, balance >= 60000 AS enough, balance - 60000 AS new_balance FROM tax_credit WHERE taxpayer_id = 1 \gset
\echo '[A t=0s] reads balance =' :balance
SELECT pg_sleep(2) \gset
\if :enough
  UPDATE tax_credit SET balance = :new_balance WHERE taxpayer_id = 1;
  \echo '[A t=2s] enough credit -> uses N60,000, writes balance =' :new_balance
\endif
COMMIT;
\echo '[A] committed'
SQL
cat > "$TMP/b.sql" <<'SQL'
SET search_path TO nrs;
SELECT pg_sleep(1) \gset
BEGIN;
SELECT balance, balance >= 60000 AS enough, balance - 60000 AS new_balance FROM tax_credit WHERE taxpayer_id = 1 \gset
\echo '[B t=1s] reads balance =' :balance '  (A has not committed yet)'
SELECT pg_sleep(2) \gset
\if :enough
  UPDATE tax_credit SET balance = :new_balance WHERE taxpayer_id = 1;
  \echo '[B t=3s] enough credit -> uses N60,000, writes balance =' :new_balance
\endif
COMMIT;
\echo '[B] committed'
SQL
reset_credit
run_pair "demo1_lost_update" "$TMP/a.sql" "$TMP/b.sql"

# ---------------------------------------------------------------------
# DEMO 2: THE FIX - lock the row with SELECT ... FOR UPDATE
# B's SELECT has to WAIT until A commits. B then reads the new balance
# (N40,000), sees there is not enough credit, and refuses.
# ---------------------------------------------------------------------
sed 's/FROM tax_credit WHERE taxpayer_id = 1 \\gset/FROM tax_credit WHERE taxpayer_id = 1 FOR UPDATE \\gset/' "$TMP/a.sql" > "$TMP/a2.sql"
cat > "$TMP/b2.sql" <<'SQL'
SET search_path TO nrs;
SELECT pg_sleep(1) \gset
BEGIN;
\echo '[B t=1s] asks for the row with FOR UPDATE ... (A holds the lock, B must wait)'
SELECT balance, balance >= 60000 AS enough FROM tax_credit WHERE taxpayer_id = 1 FOR UPDATE \gset
\echo '[B t=2s] lock granted after A committed. Reads balance =' :balance
\if :enough
  UPDATE tax_credit SET balance = :balance - 60000 WHERE taxpayer_id = 1;
  \echo '[B] uses N60,000'
\else
  \echo '[B] NOT enough credit -> request refused'
\endif
COMMIT;
\echo '[B] committed'
SQL
reset_credit
run_pair "demo2_fixed_with_for_update" "$TMP/a2.sql" "$TMP/b2.sql"

# ---------------------------------------------------------------------
# DEMO 3: ISOLATION LEVELS - non-repeatable read
# A (a manager running a report) reads the balance twice in one
# transaction. Between the two reads, B uses N30,000 and commits.
#   READ COMMITTED  (PostgreSQL default): A's two reads DIFFER
#   REPEATABLE READ: A sees the SAME value both times (a snapshot)
# ---------------------------------------------------------------------
for LEVEL in "READ COMMITTED" "REPEATABLE READ"; do
cat > "$TMP/a3.sql" <<SQL
SET search_path TO nrs;
BEGIN ISOLATION LEVEL $LEVEL;
SELECT balance AS first_read FROM tax_credit WHERE taxpayer_id = 1 \gset
\echo '[A t=0s] $LEVEL - 1st read: balance =' :first_read
SELECT pg_sleep(2) \gset
SELECT balance AS second_read FROM tax_credit WHERE taxpayer_id = 1 \gset
\echo '[A t=2s] $LEVEL - 2nd read: balance =' :second_read
COMMIT;
SQL
cat > "$TMP/b3.sql" <<'SQL'
SET search_path TO nrs;
SELECT pg_sleep(1) \gset
UPDATE tax_credit SET balance = balance - 30000 WHERE taxpayer_id = 1;
\echo '[B t=1s] used N30,000 and committed (balance is now 70000.00)'
SQL
reset_credit
run_pair "demo3_$(echo "$LEVEL" | tr 'A-Z ' 'a-z_')" "$TMP/a3.sql" "$TMP/b3.sql"
done

# ---------------------------------------------------------------------
# DEMO 4: DEADLOCK
# A locks taxpayer 1 then wants taxpayer 2.
# B locks taxpayer 2 then wants taxpayer 1.
# Each waits for the other forever, so PostgreSQL detects the deadlock
# and cancels one transaction so the other can finish.
# ---------------------------------------------------------------------
cat > "$TMP/a4.sql" <<'SQL'
SET search_path TO nrs;
BEGIN;
UPDATE tax_credit SET balance = balance - 1000 WHERE taxpayer_id = 1;
\echo '[A t=0s] locked taxpayer 1'
SELECT pg_sleep(2) \gset
\echo '[A t=2s] wants taxpayer 2 (held by B) ... waiting'
UPDATE tax_credit SET balance = balance - 1000 WHERE taxpayer_id = 2;
\echo '[A] got taxpayer 2'
COMMIT;
\echo '[A] committed'
SQL
cat > "$TMP/b4.sql" <<'SQL'
SET search_path TO nrs;
SELECT pg_sleep(1) \gset
BEGIN;
UPDATE tax_credit SET balance = balance - 1000 WHERE taxpayer_id = 2;
\echo '[B t=1s] locked taxpayer 2'
SELECT pg_sleep(3) \gset
\echo '[B t=4s] wants taxpayer 1 (held by A) ... waiting'
UPDATE tax_credit SET balance = balance - 1000 WHERE taxpayer_id = 1;
\if :ERROR
  \echo '[B] cancelled by PostgreSQL as the deadlock victim'
\else
  \echo '[B] got taxpayer 1'
\endif
COMMIT;
\echo '[B] COMMIT is turned into ROLLBACK, so B changed nothing'
SQL
reset_credit
run_pair "demo4_deadlock" "$TMP/a4.sql" "$TMP/b4.sql"

# ---------------------------------------------------------------------
# DEMO 5: DURABILITY - committed data survives a crash
# Commit a change, then KILL the database server without warning (like
# a power cut), start it again, and check the change is still there.
# ---------------------------------------------------------------------
{
  echo "################ demo5_durability ################"
  reset_credit
  echo "SET search_path TO nrs; UPDATE tax_credit SET balance = 12345 WHERE taxpayer_id = 3;" | session
  echo "Committed: taxpayer 3 balance = 12345.00"
  echo "Killing the database server (no clean shutdown)..."
  docker kill --signal=KILL nrs_postgres > /dev/null
  docker start nrs_postgres > /dev/null
  until docker exec nrs_postgres pg_isready -U nrs_admin -d nrs_tax_db > /dev/null 2>&1; do sleep 1; done
  echo "Server restarted. Server log shows crash recovery from the WAL:"
  docker logs nrs_postgres 2>&1 | grep -E "not properly shut down|redo starts|redo done" | tail -3 | sed 's/^/   /'
  echo "Balance after the crash:"
  echo "SELECT taxpayer_id, balance FROM nrs.tax_credit WHERE taxpayer_id = 3;" | session
} | tee "$OUT/demo5_durability.txt"

reset_credit
echo "All demos finished. Outputs saved in $OUT"

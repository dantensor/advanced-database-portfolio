-- =====================================================================
-- MIT 8103 Portfolio 3: ACID properties, one session
-- Run after 01_setup.sql:
--   docker exec -i nrs_postgres psql -U nrs_admin -d nrs_tax_db < 02_acid_demo.sql
-- Errors in this file are EXPECTED. They show the database protecting itself.
-- =====================================================================
SET search_path TO nrs;

\echo
\echo '=== A. ATOMICITY: all or nothing ==='
\echo 'Register a new taxpayer = 2 inserts. The 2nd insert fails (the NIN is'
\echo 'already used by taxpayer 1), so the 1st insert must be undone too.'

BEGIN;
INSERT INTO taxpayer (taxpayer_id, tin, taxpayer_type, office_id, registration_date)
VALUES (999999, '2999999999', 'I', 1, DATE '2026-11-13');
\echo 'Step 1 done: taxpayer row inserted (not yet committed).'
INSERT INTO individual_taxpayer (taxpayer_id, first_name, last_name, date_of_birth, nin)
VALUES (999999, 'Test', 'Atomic', DATE '1990-01-01', '30000001013');   -- duplicate NIN -> ERROR
COMMIT;   -- because of the error, PostgreSQL turns this COMMIT into a ROLLBACK

\echo 'Is the half-registered taxpayer in the database? (expect 0 rows)'
SELECT taxpayer_id, tin FROM taxpayer WHERE tin = '2999999999';


\echo
\echo '=== B. CONSISTENCY: rules are never broken ==='
\echo 'Try to use N150,000 from a credit of N100,000. CHECK (balance >= 0) refuses it.'

UPDATE tax_credit SET balance = balance - 150000 WHERE taxpayer_id = 1;   -- ERROR
SELECT taxpayer_id, balance FROM tax_credit WHERE taxpayer_id = 1;


\echo
\echo '=== C. SAVEPOINT: undo only part of a transaction ==='
\echo 'Use N20,000 of credit, then a mistaken N5,000,000 entry is rolled back to'
\echo 'the savepoint. The good N20,000 step is kept.'

BEGIN;
UPDATE tax_credit SET balance = balance - 20000 WHERE taxpayer_id = 2;
SAVEPOINT before_mistake;
UPDATE tax_credit SET balance = balance - 5000000 WHERE taxpayer_id = 2;  -- ERROR
ROLLBACK TO SAVEPOINT before_mistake;
COMMIT;

\echo 'Taxpayer 2 balance (expect 80000.00):'
SELECT taxpayer_id, balance FROM tax_credit WHERE taxpayer_id = 2;


\echo
\echo '=== D. ISOLATION ==='
\echo 'Needs two sessions at the same time. See 03_concurrency_demos.sh.'

\echo
\echo '=== E. DURABILITY ==='
\echo 'Once COMMIT returns, the change is safe in the write-ahead log (WAL),'
\echo 'even if the server crashes. 03_concurrency_demos.sh proves it by'
\echo 'restarting the database container and reading the data again.'

-- put the demo table back to its starting values
UPDATE tax_credit SET balance = 100000;

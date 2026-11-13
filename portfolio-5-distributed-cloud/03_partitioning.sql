-- =====================================================================
-- MIT 8103 Portfolio 5: horizontal fragmentation (partitioning)
--
-- Splits the payment table into one piece (partition) per YEAR.
-- In a distributed database each piece could live on a different
-- server; that is called SHARDING. Here all pieces are on one server
-- so the idea is easy to see.
--
-- Runs on the MAIN database (Portfolio 1 data):
--   docker exec -i nrs_postgres psql -U nrs_admin -d nrs_tax_db < portfolio-5-distributed-cloud/03_partitioning.sql
-- The demo table is removed at the end.
-- =====================================================================
SET search_path TO nrs;
SET client_min_messages = warning;   -- hide "does not exist, skipping" notices
DROP TABLE IF EXISTS payment_by_year;

-- 1. A table split by payment_date ranges
CREATE TABLE payment_by_year (LIKE payment INCLUDING DEFAULTS)
    PARTITION BY RANGE (payment_date);

CREATE TABLE payment_y2024 PARTITION OF payment_by_year
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE payment_y2025 PARTITION OF payment_by_year
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
CREATE TABLE payment_y2026 PARTITION OF payment_by_year
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
CREATE TABLE payment_other PARTITION OF payment_by_year DEFAULT;   -- anything else

-- 2. Copy the payments in. PostgreSQL puts each row in the right piece.
INSERT INTO payment_by_year SELECT * FROM payment;
ANALYZE payment_by_year;

\echo
\echo '=== Rows in each partition (fragment) ==='
SELECT tableoid::regclass AS partition, count(*) AS payments,
       min(payment_date) AS first_date, max(payment_date) AS last_date
FROM payment_by_year
GROUP BY 1 ORDER BY 1;

\echo '=== Query for 2025 revenue: which partitions are read? ==='
\echo '(only payment_y2025 should appear: this is "partition pruning")'
EXPLAIN (COSTS OFF)
SELECT sum(amount) FROM payment_by_year
WHERE payment_date >= DATE '2025-01-01' AND payment_date < DATE '2026-01-01';

\echo '=== Same answer as the normal table? ==='
SELECT (SELECT sum(amount) FROM payment_by_year
         WHERE payment_date >= DATE '2025-01-01' AND payment_date < DATE '2026-01-01') AS partitioned_table,
       (SELECT sum(amount) FROM payment
         WHERE payment_date >= DATE '2025-01-01' AND payment_date < DATE '2026-01-01') AS normal_table;

-- 3. Clean up
DROP TABLE payment_by_year;

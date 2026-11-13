-- Trade-off test: indexes speed up reads but slow down writes.
-- Inserts 50,000 payments, then ROLLS BACK, so no data changes.
-- Run once in the baseline state and once after 20_optimise.sql.
BEGIN;
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO payment (assessment_id, amount, payment_date, payment_method, payment_ref)
SELECT assessment_id, 1000.00, DATE '2026-11-13', 'REMITA', 'WCOST' || assessment_id
FROM assessment
ORDER BY assessment_id
LIMIT 50000;
ROLLBACK;

-- =====================================================================
-- MIT 8103 Portfolio 1: NRS Tax Administration Database
-- File: 03_sample_queries.sql
--
-- Part A walks through the 7 key operations of the case study for one
-- new taxpayer, inside a transaction that is ROLLED BACK at the end, so
-- the sample data is left unchanged and this file can be re-run.
-- Part B contains reports over the full synthetic data set.
--
-- Run:  docker exec -i nrs_postgres psql -U nrs_admin -d nrs_tax_db < 03_sample_queries.sql
-- =====================================================================
SET search_path TO nrs;

-- =====================================================================
-- PART A: the key operations, step by step
-- =====================================================================
BEGIN;

-- Operation 1: Register a taxpayer and issue a TIN
-- (supertype row + subtype row are written in ONE statement, so a
--  taxpayer can never exist without its individual details)
WITH new_tp AS (
    INSERT INTO taxpayer (tin, taxpayer_type, office_id, registered_by,
                          registration_date, email, phone, address)
    VALUES ('2000000001', 'I',
            (SELECT office_id FROM tax_office WHERE office_code = 'LG-IKJ'),
            (SELECT officer_id FROM tax_officer WHERE role = 'TAX_OFFICER' ORDER BY officer_id LIMIT 1),
            DATE '2025-02-10', 'new.taxpayer@mail.example', '08000000001', '1 Demo Street, Ikeja')
    RETURNING taxpayer_id
)
INSERT INTO individual_taxpayer (taxpayer_id, first_name, last_name, date_of_birth, nin, occupation)
SELECT taxpayer_id, 'Ada', 'Demo', DATE '1990-05-17', '99999999991', 'Software Developer'
FROM new_tp;

SELECT * FROM v_taxpayer_name WHERE tin = '2000000001';

-- Operation 2: File a tax return (PIT for 2025, filed 3 weeks LATE)
INSERT INTO tax_return (taxpayer_id, tax_type_id, period_start, period_end,
                        due_date, filing_date, declared_amount)
SELECT t.taxpayer_id, tt.tax_type_id, DATE '2025-01-01', DATE '2025-12-31',
       DATE '2026-03-31', DATE '2026-04-21', 9600000.00
FROM taxpayer t, tax_type tt
WHERE t.tin = '2000000001' AND tt.tax_code = 'PIT';

-- Operation 3: Generate the assessment (declared amount x tax rate)
INSERT INTO assessment (return_id, assessment_type, amount_due, assessment_date, remarks)
SELECT r.return_id, 'ORIGINAL', round(r.declared_amount * tt.rate_percent / 100, 2),
       r.filing_date, 'Self-assessment on filing'
FROM tax_return r
JOIN tax_type tt USING (tax_type_id)
JOIN taxpayer t  USING (taxpayer_id)
WHERE t.tin = '2000000001';

-- Operation 6: Apply a penalty for late filing
INSERT INTO penalty (return_id, reason, amount, date_applied)
SELECT r.return_id, 'LATE_FILING',
       25000 + 5000 * floor((r.filing_date - r.due_date) / 30),
       r.filing_date + 7
FROM tax_return r JOIN taxpayer t USING (taxpayer_id)
WHERE t.tin = '2000000001' AND r.filing_date > r.due_date;

-- Balance now: tax due + penalty, nothing paid yet
SELECT tin, taxpayer_name, total_assessed, total_penalties, total_paid, balance_owed
FROM v_taxpayer_balance WHERE tin = '2000000001';

-- Operation 4: Record a payment (the taxpayer pays N1,500,000, which is
-- more than the N1,440,000 assessed) and see the balance update
INSERT INTO payment (assessment_id, amount, payment_date, payment_method, payment_ref)
SELECT a.assessment_id, 1500000.00, DATE '2026-04-25', 'REMITA', 'DEMO-PAY-0001'
FROM assessment a
JOIN tax_return r USING (return_id)
JOIN taxpayer t   USING (taxpayer_id)
WHERE t.tin = '2000000001' AND a.assessment_type = 'ORIGINAL';

SELECT tin, taxpayer_name, total_assessed, total_penalties, total_paid, balance_owed
FROM v_taxpayer_balance WHERE tin = '2000000001';

-- Operation 5: Process a refund for the over-payment
-- Overpaid = N1,500,000 - N1,440,000 = N60,000. The NRS first keeps back
-- the unpaid N25,000 late-filing penalty, so N35,000 is refunded and the
-- balance becomes zero. A manager approves it.
INSERT INTO refund (payment_id, amount, request_date, status, approved_by, decision_date)
SELECT p.payment_id,
       p.amount - a.amount_due
         - (SELECT COALESCE(sum(pen.amount), 0) FROM penalty pen WHERE pen.return_id = a.return_id),
       DATE '2026-05-02', 'PAID',
       (SELECT officer_id FROM tax_officer WHERE role = 'MANAGER' ORDER BY officer_id LIMIT 1),
       DATE '2026-05-20'
FROM payment p JOIN assessment a USING (assessment_id)
WHERE p.payment_ref = 'DEMO-PAY-0001' AND p.amount > a.amount_due;

SELECT tin, taxpayer_name, total_assessed, total_penalties, total_paid,
       total_refunded, balance_owed
FROM v_taxpayer_balance WHERE tin = '2000000001';

-- Constraints in action: each of these would be rejected by the database.
--   Duplicate TIN                -> UNIQUE (tin)
--     INSERT INTO taxpayer (tin, taxpayer_type, office_id) VALUES ('2000000001','I',1);
--   Second return, same period   -> UNIQUE (taxpayer_id, tax_type_id, period_start)
--   Negative payment             -> CHECK (amount > 0)
--   Company row for a person     -> FK (taxpayer_id, taxpayer_type) + CHECK (taxpayer_type = 'C')
--   Approved refund, no approver -> CHECK on refund status / approved_by

ROLLBACK;   -- undo the demo so the sample data stays the same

-- =====================================================================
-- PART B: reports (Operation 7 and other management queries)
-- =====================================================================

-- 7a. Revenue collected by geopolitical zone and state (2025 payments)
SELECT s.geo_zone, s.state_name,
       count(DISTINCT t.taxpayer_id)  AS paying_taxpayers,
       sum(p.amount)                  AS revenue_collected
FROM payment p
JOIN assessment a  ON a.assessment_id = p.assessment_id
JOIN tax_return r  ON r.return_id     = a.return_id
JOIN taxpayer t    ON t.taxpayer_id   = r.taxpayer_id
JOIN tax_office o  ON o.office_id     = t.office_id
JOIN state s       ON s.state_id      = o.state_id
WHERE p.payment_date BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
GROUP BY s.geo_zone, s.state_name
ORDER BY revenue_collected DESC
LIMIT 10;

-- 7b. Revenue collected by tax type per year
SELECT EXTRACT(YEAR FROM p.payment_date)::int AS year, tt.tax_code,
       sum(p.amount) AS revenue_collected
FROM payment p
JOIN assessment a ON a.assessment_id = p.assessment_id
JOIN tax_return r ON r.return_id     = a.return_id
JOIN tax_type tt  ON tt.tax_type_id  = r.tax_type_id
GROUP BY 1, 2
ORDER BY 1, 2;

-- 7c. Top 10 tax offices by revenue collected (all time)
SELECT o.office_code, o.office_name, sum(p.amount) AS revenue_collected
FROM payment p
JOIN assessment a ON a.assessment_id = p.assessment_id
JOIN tax_return r ON r.return_id     = a.return_id
JOIN taxpayer t   ON t.taxpayer_id   = r.taxpayer_id
JOIN tax_office o ON o.office_id     = t.office_id
GROUP BY o.office_code, o.office_name
ORDER BY revenue_collected DESC
LIMIT 10;

-- Filing compliance: share of returns filed on time, by tax type
SELECT tt.tax_code,
       count(*) AS returns_filed,
       count(*) FILTER (WHERE r.filing_date <= r.due_date) AS on_time,
       round(100.0 * count(*) FILTER (WHERE r.filing_date <= r.due_date) / count(*), 1) AS pct_on_time
FROM tax_return r JOIN tax_type tt USING (tax_type_id)
GROUP BY tt.tax_code
ORDER BY tt.tax_code;

-- Top 10 debtors (largest outstanding balances)
SELECT tin, taxpayer_name, balance_owed
FROM v_taxpayer_balance
WHERE balance_owed > 0
ORDER BY balance_owed DESC
LIMIT 10;

-- Refunds waiting for a decision, oldest first
SELECT f.refund_id, n.tin, n.taxpayer_name, f.amount, f.request_date
FROM refund f
JOIN payment p     ON p.payment_id    = f.payment_id
JOIN assessment a  ON a.assessment_id = p.assessment_id
JOIN tax_return r  ON r.return_id     = a.return_id
JOIN v_taxpayer_name n ON n.taxpayer_id = r.taxpayer_id
WHERE f.status = 'PENDING'
ORDER BY f.request_date;

-- Officer workload: returns reviewed per officer role
SELECT o.role, count(*) AS returns_reviewed, count(DISTINCT o.officer_id) AS officers
FROM tax_return r JOIN tax_officer o ON o.officer_id = r.reviewed_by
GROUP BY o.role;

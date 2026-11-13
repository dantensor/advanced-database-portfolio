-- =====================================================================
-- MIT 8103 Portfolio 2: the OPTIMISATIONS
-- Each change is aimed at one query in queries/. See README section 4.
-- =====================================================================
SET search_path TO nrs;

-- Q1: composite B-tree index. The most selective / most searched
--     column (last_name) goes first, so the index also serves
--     surname-only searches.
CREATE INDEX idx_individual_name
    ON individual_taxpayer (last_name, first_name);

-- Q2: EXPRESSION (functional) index. A plain index on email cannot be
--     used for lower(email) = ..., because the index stores the
--     original values, not lower-case ones.
CREATE INDEX idx_taxpayer_email_lower
    ON taxpayer (lower(email));

-- Q3: composite index (equality column first, range column second).
--     It only helps once the query is rewritten as a date range.
CREATE INDEX idx_return_type_filing
    ON tax_return (tax_type_id, filing_date);

-- Q4: COVERING index. INCLUDE stores assessment_id and amount in the
--     index leaf pages, so October's payments can be read from the
--     index alone (Index Only Scan) without visiting the table.
CREATE INDEX idx_payment_date_cover
    ON payment (payment_date) INCLUDE (assessment_id, amount);

-- Q5: PARTIAL index. Only the ~6% of returns that are UNDER_REVIEW are
--     indexed, already sorted by filing_date, so "oldest 50" is a
--     short walk along the index with no sort step.
CREATE INDEX idx_return_review_queue
    ON tax_return (filing_date) WHERE status = 'UNDER_REVIEW';

-- Q6: MATERIALIZED VIEW. The balance view aggregates ~1.5 million rows
--     every time it is queried. A materialized view stores the result
--     once; it must be refreshed (e.g. nightly) to pick up new payments:
--         REFRESH MATERIALIZED VIEW CONCURRENTLY mv_taxpayer_balance;
CREATE MATERIALIZED VIEW mv_taxpayer_balance AS
SELECT * FROM v_taxpayer_balance;
CREATE UNIQUE INDEX idx_mv_balance_id  ON mv_taxpayer_balance (taxpayer_id);  -- needed for CONCURRENTLY
CREATE INDEX        idx_mv_balance_owed ON mv_taxpayer_balance (balance_owed DESC);

-- Fresh statistics so the optimiser knows about the new structures.
-- Postgres also VACUUMs automatically; this makes the visibility map
-- current, which lets Index Only Scans skip table visits.
VACUUM ANALYZE;

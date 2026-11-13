-- =====================================================================
-- MIT 8103 Portfolio 2: return the database to the BASELINE state
-- Removes everything 20_optimise.sql adds. The Portfolio 1 keys and
-- foreign-key indexes stay, because they are part of the base design.
-- =====================================================================
SET search_path TO nrs;

DROP INDEX IF EXISTS idx_individual_name;
DROP INDEX IF EXISTS idx_taxpayer_email_lower;
DROP INDEX IF EXISTS idx_return_type_filing;
DROP INDEX IF EXISTS idx_payment_date_cover;
DROP INDEX IF EXISTS idx_return_review_queue;
DROP MATERIALIZED VIEW IF EXISTS mv_taxpayer_balance;

ANALYZE;

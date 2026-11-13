-- =====================================================================
-- MIT 8103 Portfolio 3: setup
-- Adds ONE small table used by all the demos: tax_credit.
--
-- When a taxpayer overpays, the NRS can keep the extra money as a
-- "tax credit" and use it to pay future tax. Two officers using the same
-- credit at the same moment is a classic concurrency problem.
--
-- Run:  docker exec -i nrs_postgres psql -U nrs_admin -d nrs_tax_db < 01_setup.sql
-- =====================================================================
SET search_path TO nrs;

DROP TABLE IF EXISTS tax_credit;
CREATE TABLE tax_credit (
    taxpayer_id  INT           PRIMARY KEY REFERENCES taxpayer(taxpayer_id),
    balance      NUMERIC(15,2) NOT NULL CHECK (balance >= 0)   -- can never go negative
);

-- Three taxpayers, each with N100,000 of credit
INSERT INTO tax_credit VALUES (1, 100000), (2, 100000), (3, 100000);

SELECT * FROM tax_credit ORDER BY taxpayer_id;

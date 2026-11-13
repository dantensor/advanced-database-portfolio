-- =====================================================================
-- MIT 8103 Portfolio 1: NRS Tax Administration Database
-- File: 01_schema.sql  (creates all tables, keys and constraints)
--
-- Run:  docker exec -i nrs_postgres psql -U nrs_admin -d nrs_tax_db < 01_schema.sql
-- Safe to re-run: it drops and recreates the schema "nrs".
-- All data used with this schema is synthetic.
-- =====================================================================

DROP SCHEMA IF EXISTS nrs CASCADE;
CREATE SCHEMA nrs;
SET search_path TO nrs;

-- ---------------------------------------------------------------------
-- 1. Reference / lookup tables
-- ---------------------------------------------------------------------

-- Nigeria's 36 states + FCT, grouped into the six geopolitical zones.
CREATE TABLE state (
    state_id    SMALLSERIAL  PRIMARY KEY,
    state_name  VARCHAR(40)  NOT NULL UNIQUE,
    geo_zone    VARCHAR(20)  NOT NULL
        CHECK (geo_zone IN ('North Central','North East','North West',
                            'South East','South South','South West'))
);

-- NRS tax offices (field offices that administer taxpayers).
CREATE TABLE tax_office (
    office_id    SERIAL       PRIMARY KEY,
    office_code  VARCHAR(10)  NOT NULL UNIQUE,
    office_name  VARCHAR(100) NOT NULL,
    state_id     SMALLINT     NOT NULL REFERENCES state(state_id),
    address      VARCHAR(200)
);

-- Types of tax the NRS administers.
CREATE TABLE tax_type (
    tax_type_id       SMALLSERIAL  PRIMARY KEY,
    tax_code          VARCHAR(5)   NOT NULL UNIQUE,      -- CIT, VAT, PIT, WHT
    tax_name          VARCHAR(60)  NOT NULL,
    rate_percent      NUMERIC(5,2) NOT NULL CHECK (rate_percent >= 0 AND rate_percent <= 100),
    filing_frequency  VARCHAR(10)  NOT NULL CHECK (filing_frequency IN ('MONTHLY','ANNUAL'))
);

-- ---------------------------------------------------------------------
-- 2. Staff
-- ---------------------------------------------------------------------
CREATE TABLE tax_officer (
    officer_id   SERIAL       PRIMARY KEY,
    staff_no     VARCHAR(12)  NOT NULL UNIQUE,
    first_name   VARCHAR(50)  NOT NULL,
    last_name    VARCHAR(50)  NOT NULL,
    role         VARCHAR(20)  NOT NULL
        CHECK (role IN ('TAX_OFFICER','AUDITOR','MANAGER','ADMIN')),
    office_id    INT          NOT NULL REFERENCES tax_office(office_id),
    email        VARCHAR(100) NOT NULL UNIQUE,
    hire_date    DATE         NOT NULL
);

-- ---------------------------------------------------------------------
-- 3. Taxpayers (supertype / subtype design)
--    taxpayer            = attributes common to every taxpayer
--    individual_taxpayer = attributes only individuals have
--    company_taxpayer    = attributes only companies have
-- ---------------------------------------------------------------------
CREATE TABLE taxpayer (
    taxpayer_id        SERIAL       PRIMARY KEY,
    tin                CHAR(10)     NOT NULL UNIQUE
        CHECK (tin ~ '^[0-9]{10}$'),                    -- 10-digit TIN
    taxpayer_type      CHAR(1)      NOT NULL CHECK (taxpayer_type IN ('I','C')),
    office_id          INT          NOT NULL REFERENCES tax_office(office_id),
    registered_by      INT          REFERENCES tax_officer(officer_id),
    registration_date  DATE         NOT NULL DEFAULT CURRENT_DATE,
    email              VARCHAR(100),
    phone              VARCHAR(20),
    address            VARCHAR(200),
    status             VARCHAR(10)  NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE','DORMANT','CLOSED')),
    UNIQUE (taxpayer_id, taxpayer_type)       -- lets subtypes enforce the right type
);

CREATE TABLE individual_taxpayer (
    taxpayer_id    INT          PRIMARY KEY,
    taxpayer_type  CHAR(1)      NOT NULL DEFAULT 'I' CHECK (taxpayer_type = 'I'),
    first_name     VARCHAR(50)  NOT NULL,
    last_name      VARCHAR(50)  NOT NULL,
    date_of_birth  DATE         NOT NULL CHECK (date_of_birth > DATE '1900-01-01'),
    nin            CHAR(11)     UNIQUE CHECK (nin ~ '^[0-9]{11}$'),   -- National ID No.
    occupation     VARCHAR(60),
    FOREIGN KEY (taxpayer_id, taxpayer_type)
        REFERENCES taxpayer(taxpayer_id, taxpayer_type) ON DELETE CASCADE
);

CREATE TABLE company_taxpayer (
    taxpayer_id         INT          PRIMARY KEY,
    taxpayer_type       CHAR(1)      NOT NULL DEFAULT 'C' CHECK (taxpayer_type = 'C'),
    company_name        VARCHAR(120) NOT NULL,
    rc_number           VARCHAR(12)  NOT NULL UNIQUE,   -- CAC registration no.
    incorporation_date  DATE         NOT NULL,
    business_sector     VARCHAR(40)  NOT NULL,
    FOREIGN KEY (taxpayer_id, taxpayer_type)
        REFERENCES taxpayer(taxpayer_id, taxpayer_type) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- 4. Tax administration transactions
-- ---------------------------------------------------------------------

-- A return filed by one taxpayer, for one tax type, for one period.
CREATE TABLE tax_return (
    return_id         SERIAL        PRIMARY KEY,
    taxpayer_id       INT           NOT NULL REFERENCES taxpayer(taxpayer_id),
    tax_type_id       SMALLINT      NOT NULL REFERENCES tax_type(tax_type_id),
    period_start      DATE          NOT NULL,
    period_end        DATE          NOT NULL,
    due_date          DATE          NOT NULL,
    filing_date       DATE          NOT NULL,
    declared_amount   NUMERIC(15,2) NOT NULL CHECK (declared_amount >= 0), -- taxable income / sales
    status            VARCHAR(12)   NOT NULL DEFAULT 'SUBMITTED'
        CHECK (status IN ('SUBMITTED','UNDER_REVIEW','ACCEPTED','AUDITED')),
    reviewed_by       INT           REFERENCES tax_officer(officer_id),
    CHECK (period_end > period_start),
    CHECK (due_date >= period_end),
    UNIQUE (taxpayer_id, tax_type_id, period_start)   -- no duplicate returns
);

-- The tax amount the NRS says is due on a return.
-- ORIGINAL = from the return; ADDITIONAL = raised later by an auditor.
CREATE TABLE assessment (
    assessment_id    SERIAL        PRIMARY KEY,
    return_id        INT           NOT NULL REFERENCES tax_return(return_id),
    assessment_type  VARCHAR(10)   NOT NULL CHECK (assessment_type IN ('ORIGINAL','ADDITIONAL')),
    amount_due       NUMERIC(15,2) NOT NULL CHECK (amount_due >= 0),
    assessment_date  DATE          NOT NULL,
    assessed_by      INT           REFERENCES tax_officer(officer_id),
    remarks          VARCHAR(200)
);
-- Only one ORIGINAL assessment per return.
CREATE UNIQUE INDEX uq_assessment_one_original
    ON assessment(return_id) WHERE assessment_type = 'ORIGINAL';

-- Money received against an assessment.
CREATE TABLE payment (
    payment_id       SERIAL        PRIMARY KEY,
    assessment_id    INT           NOT NULL REFERENCES assessment(assessment_id),
    amount           NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    payment_date     DATE          NOT NULL,
    payment_method   VARCHAR(15)   NOT NULL
        CHECK (payment_method IN ('BANK_TRANSFER','CARD','REMITA','BANK_DRAFT')),
    payment_ref      VARCHAR(20)   NOT NULL UNIQUE
);

-- Penalty for late filing (or other offences) on a return.
CREATE TABLE penalty (
    penalty_id    SERIAL        PRIMARY KEY,
    return_id     INT           NOT NULL REFERENCES tax_return(return_id),
    reason        VARCHAR(20)   NOT NULL
        CHECK (reason IN ('LATE_FILING','LATE_PAYMENT','UNDER_DECLARATION')),
    amount        NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    date_applied  DATE          NOT NULL
);

-- Refund of an overpayment.
CREATE TABLE refund (
    refund_id      SERIAL        PRIMARY KEY,
    payment_id     INT           NOT NULL REFERENCES payment(payment_id),
    amount         NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    request_date   DATE          NOT NULL,
    status         VARCHAR(10)   NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING','APPROVED','REJECTED','PAID')),
    approved_by    INT           REFERENCES tax_officer(officer_id),
    decision_date  DATE,
    CHECK (decision_date IS NULL OR decision_date >= request_date),
    -- an approved / paid refund must say who approved it and when
    CHECK (status IN ('PENDING') OR (approved_by IS NOT NULL AND decision_date IS NOT NULL))
);

-- ---------------------------------------------------------------------
-- 5. Indexes on foreign keys (PostgreSQL does not create these itself)
-- ---------------------------------------------------------------------
CREATE INDEX idx_taxpayer_office     ON taxpayer(office_id);
CREATE INDEX idx_return_taxpayer     ON tax_return(taxpayer_id);
CREATE INDEX idx_return_taxtype      ON tax_return(tax_type_id);
CREATE INDEX idx_assessment_return   ON assessment(return_id);
CREATE INDEX idx_payment_assessment  ON payment(assessment_id);
CREATE INDEX idx_penalty_return      ON penalty(return_id);
CREATE INDEX idx_refund_payment      ON refund(payment_id);

-- ---------------------------------------------------------------------
-- 6. Views
--    The taxpayer balance is DERIVED (not stored) so it can never go
--    out of step with the underlying assessments/payments (3NF).
-- ---------------------------------------------------------------------
CREATE VIEW v_taxpayer_name AS
SELECT t.taxpayer_id, t.tin, t.taxpayer_type,
       COALESCE(c.company_name, i.first_name || ' ' || i.last_name) AS taxpayer_name
FROM taxpayer t
LEFT JOIN individual_taxpayer i ON i.taxpayer_id = t.taxpayer_id
LEFT JOIN company_taxpayer   c ON c.taxpayer_id = t.taxpayer_id;

CREATE VIEW v_taxpayer_balance AS
WITH due AS (
    SELECT r.taxpayer_id, SUM(a.amount_due) AS total_assessed
    FROM tax_return r JOIN assessment a ON a.return_id = r.return_id
    GROUP BY r.taxpayer_id
), pen AS (
    SELECT r.taxpayer_id, SUM(p.amount) AS total_penalties
    FROM tax_return r JOIN penalty p ON p.return_id = r.return_id
    GROUP BY r.taxpayer_id
), paid AS (
    SELECT r.taxpayer_id, SUM(p.amount) AS total_paid
    FROM tax_return r
    JOIN assessment a ON a.return_id = r.return_id
    JOIN payment p    ON p.assessment_id = a.assessment_id
    GROUP BY r.taxpayer_id
), refunded AS (
    SELECT r.taxpayer_id, SUM(f.amount) AS total_refunded
    FROM tax_return r
    JOIN assessment a ON a.return_id = r.return_id
    JOIN payment p    ON p.assessment_id = a.assessment_id
    JOIN refund f     ON f.payment_id = p.payment_id AND f.status = 'PAID'
    GROUP BY r.taxpayer_id
)
SELECT n.taxpayer_id, n.tin, n.taxpayer_name,
       COALESCE(due.total_assessed, 0)       AS total_assessed,
       COALESCE(pen.total_penalties, 0)      AS total_penalties,
       COALESCE(paid.total_paid, 0)          AS total_paid,
       COALESCE(refunded.total_refunded, 0)  AS total_refunded,
       COALESCE(due.total_assessed, 0) + COALESCE(pen.total_penalties, 0)
         - COALESCE(paid.total_paid, 0) + COALESCE(refunded.total_refunded, 0) AS balance_owed
FROM v_taxpayer_name n
LEFT JOIN due      ON due.taxpayer_id      = n.taxpayer_id
LEFT JOIN pen      ON pen.taxpayer_id      = n.taxpayer_id
LEFT JOIN paid     ON paid.taxpayer_id     = n.taxpayer_id
LEFT JOIN refunded ON refunded.taxpayer_id = n.taxpayer_id;

-- =====================================================================
-- MIT 8103 Portfolio 1: NRS Tax Administration Database
-- File: 02_seed_data.sql  (loads SYNTHETIC sample data)
--
-- Run AFTER 01_schema.sql:
--   docker exec -i nrs_postgres psql -U nrs_admin -d nrs_tax_db < 02_seed_data.sql
--
-- Every name, TIN, NIN, RC number and amount below is generated.
-- None of it describes a real person, company or NRS record.
-- setseed() makes the "random" data the same every time it is loaded.
-- =====================================================================
SET search_path TO nrs;
SELECT setseed(0.8103);

-- "Today" for the simulation. Nothing is dated after this.
CREATE TEMP TABLE sim AS SELECT DATE '2026-11-13' AS today;

-- ---------------------------------------------------------------------
-- States (36 + FCT) and geopolitical zones
-- ---------------------------------------------------------------------
INSERT INTO state (state_name, geo_zone) VALUES
 ('Benue','North Central'),('Kogi','North Central'),('Kwara','North Central'),
 ('Nasarawa','North Central'),('Niger','North Central'),('Plateau','North Central'),
 ('FCT Abuja','North Central'),
 ('Adamawa','North East'),('Bauchi','North East'),('Borno','North East'),
 ('Gombe','North East'),('Taraba','North East'),('Yobe','North East'),
 ('Jigawa','North West'),('Kaduna','North West'),('Kano','North West'),
 ('Katsina','North West'),('Kebbi','North West'),('Sokoto','North West'),
 ('Zamfara','North West'),
 ('Abia','South East'),('Anambra','South East'),('Ebonyi','South East'),
 ('Enugu','South East'),('Imo','South East'),
 ('Akwa Ibom','South South'),('Bayelsa','South South'),('Cross River','South South'),
 ('Delta','South South'),('Edo','South South'),('Rivers','South South'),
 ('Ekiti','South West'),('Lagos','South West'),('Ogun','South West'),
 ('Ondo','South West'),('Osun','South West'),('Oyo','South West');

-- ---------------------------------------------------------------------
-- Tax types (rates simplified for the simulation)
-- ---------------------------------------------------------------------
INSERT INTO tax_type (tax_code, tax_name, rate_percent, filing_frequency) VALUES
 ('CIT', 'Companies Income Tax',            30.00, 'ANNUAL'),
 ('VAT', 'Value Added Tax',                  7.50, 'MONTHLY'),
 ('PIT', 'Personal Income Tax (flat, simplified)', 15.00, 'ANNUAL'),
 ('WHT', 'Withholding Tax',                 10.00, 'MONTHLY');

-- ---------------------------------------------------------------------
-- Tax offices: one per state, plus extra offices in busy states
-- ---------------------------------------------------------------------
INSERT INTO tax_office (office_code, office_name, state_id, address)
SELECT 'TO' || lpad(state_id::text, 3, '0'),
       'NRS ' || state_name || ' Tax Office',
       state_id,
       state_id || ' Revenue Close, ' || state_name
FROM state ORDER BY state_id;

INSERT INTO tax_office (office_code, office_name, state_id, address)
SELECT x.code, x.name, s.state_id, x.addr
FROM (VALUES
  ('LG-IKJ','NRS Ikeja Tax Office',              'Lagos',     '12 Revenue Close, Ikeja'),
  ('LG-VI', 'NRS Victoria Island Tax Office',    'Lagos',     '5 Revenue Close, Victoria Island'),
  ('LG-LKI','NRS Lekki Tax Office',              'Lagos',     '9 Revenue Close, Lekki'),
  ('LG-APP','NRS Apapa Large Taxpayers Office',  'Lagos',     '3 Revenue Close, Apapa'),
  ('AB-GAR','NRS Garki Tax Office',              'FCT Abuja', '7 Revenue Close, Garki'),
  ('AB-WSE','NRS Wuse Tax Office',               'FCT Abuja', '4 Revenue Close, Wuse'),
  ('RV-PH2','NRS Port Harcourt II Tax Office',   'Rivers',    '15 Revenue Close, Port Harcourt'),
  ('KN-NAS','NRS Nassarawa (Kano) Tax Office',   'Kano',      '2 Revenue Close, Kano')
) AS x(code, name, state_name, addr)
JOIN state s ON s.state_name = x.state_name;

-- Name lists used to generate people and companies
CREATE TEMP TABLE names AS SELECT
 ARRAY['Adebayo','Chinedu','Aisha','Emeka','Fatima','Oluwaseun','Ngozi','Ibrahim','Tunde','Amina',
       'Chiamaka','Yusuf','Folake','Obinna','Zainab','Segun','Halima','Ifeanyi','Bisi','Musa',
       'Kemi','Uche','Hauwa','Kunle','Nkechi','Abdullahi','Funmi','Chukwuma','Hadiza','Dayo',
       'Ebere','Sani','Temitope','Ikenna','Maryam','Bolaji','Adaeze','Bello','Yemi','Efe'] AS first_names,
 ARRAY['Okafor','Adeyemi','Bello','Okonkwo','Abubakar','Eze','Ogunleye','Mohammed','Nwosu','Balogun',
       'Ibrahim','Obi','Adebayo','Usman','Nwachukwu','Ojo','Danjuma','Okeke','Afolabi','Garba',
       'Onyeka','Lawal','Uzor','Akinola','Suleiman','Chukwu','Oyelaran','Aliyu','Edet','Ikpe',
       'Okoro','Bassey','Fashola','Yakubu','Ndukwe','Olatunji','Umar','Ekwueme','Adamu','Etim'] AS last_names,
 ARRAY['Trader','Teacher','Engineer','Doctor','Nurse','Accountant','Lawyer','Farmer','Civil Servant',
       'Tailor','Driver','Pharmacist','Banker','Consultant','Artisan','Software Developer'] AS occupations,
 ARRAY['Zenith','Crescent','Savannah','Delta','Unity','Heritage','Sapphire','Golden','Royal','Pinnacle',
       'Harmony','Evergreen','Summit','Horizon','Benue Valley','Atlantic','Sahel','Niger Bridge','Cedar','Northstar'] AS co_prefix,
 ARRAY['Logistics','Agro Allied','Ventures','Foods','Construction','Pharmaceuticals','Telecoms',
       'Oil and Gas Services','Microfinance','Textiles','Motors','Properties','Tech Solutions','Packaging','Energy'] AS co_middle,
 ARRAY['Ltd','Nigeria Ltd','Plc','Enterprises Ltd','Holdings Ltd'] AS co_suffix,
 ARRAY['Agriculture','Manufacturing','Oil and Gas','Telecommunications','Financial Services',
       'Construction','Retail and Trade','Transport','Health','ICT','Real Estate','Hospitality'] AS sectors;

-- ---------------------------------------------------------------------
-- Tax officers (200)
-- ---------------------------------------------------------------------
INSERT INTO tax_officer (staff_no, first_name, last_name, role, office_id, email, hire_date)
SELECT 'NRS' || lpad(g::text, 6, '0'),
       fn, ln,
       CASE WHEN r < 0.70 THEN 'TAX_OFFICER' WHEN r < 0.90 THEN 'AUDITOR'
            WHEN r < 0.98 THEN 'MANAGER' ELSE 'ADMIN' END,
       1 + (g % (SELECT count(*) FROM tax_office))::int,      -- spread across all offices
       lower(fn || '.' || ln || g) || '@nrs.example',
       DATE '2008-01-01' + floor(random() * 5800)::int
FROM (
  SELECT g, random() AS r,
         first_names[1 + floor(random() * array_length(first_names, 1))::int] AS fn,
         last_names [1 + floor(random() * array_length(last_names, 1))::int]  AS ln
  FROM generate_series(1, 200) g, names
) o;

-- ---------------------------------------------------------------------
-- Taxpayers: 1,500 individuals (ids 1-1500) + 500 companies (1501-2000)
-- 35% registered in Lagos offices, 15% in Abuja, the rest anywhere.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE office_pick AS SELECT
 (SELECT array_agg(o.office_id) FROM tax_office o JOIN state s USING (state_id) WHERE s.state_name = 'Lagos')     AS lagos,
 (SELECT array_agg(o.office_id) FROM tax_office o JOIN state s USING (state_id) WHERE s.state_name = 'FCT Abuja') AS fct,
 (SELECT array_agg(office_id) FROM tax_office) AS all_offices;

INSERT INTO taxpayer (taxpayer_id, tin, taxpayer_type, office_id, registration_date,
                      email, phone, address, status)
SELECT g,
       to_char(1000000000 + g * 4271, 'FM0000000000'),
       CASE WHEN g <= 1500 THEN 'I' ELSE 'C' END,
       CASE WHEN r < 0.35 THEN lagos[1 + floor(random() * array_length(lagos, 1))::int]
            WHEN r < 0.50 THEN fct  [1 + floor(random() * array_length(fct, 1))::int]
            ELSE all_offices[1 + floor(random() * array_length(all_offices, 1))::int] END,
       DATE '2015-01-01' + floor(random() * 2900)::int,          -- 2015 .. end of 2022
       'taxpayer' || g || '@mail.example',
       '080' || lpad((10000000 + g * 37)::text, 8, '0'),
       g || ' Market Road',
       CASE WHEN s < 0.92 THEN 'ACTIVE' WHEN s < 0.98 THEN 'DORMANT' ELSE 'CLOSED' END
FROM (SELECT g, random() AS r, random() AS s FROM generate_series(1, 2000) g) x, office_pick;
SELECT setval('taxpayer_taxpayer_id_seq', (SELECT max(taxpayer_id) FROM taxpayer));

-- Who registered each taxpayer: an officer from the same office
UPDATE taxpayer t
SET registered_by = (SELECT o.officer_id FROM tax_officer o
                     WHERE o.office_id = t.office_id AND t.taxpayer_id > 0
                     ORDER BY random() LIMIT 1);

INSERT INTO individual_taxpayer (taxpayer_id, first_name, last_name, date_of_birth, nin, occupation)
SELECT g,
       first_names[1 + floor(random() * array_length(first_names, 1))::int],
       last_names [1 + floor(random() * array_length(last_names, 1))::int],
       DATE '1955-01-01' + floor(random() * 17500)::int,          -- born 1955 .. ~2002
       to_char(30000000000 + g * 1013, 'FM00000000000'),
       occupations[1 + floor(random() * array_length(occupations, 1))::int]
FROM generate_series(1, 1500) g, names;

INSERT INTO company_taxpayer (taxpayer_id, company_name, rc_number, incorporation_date, business_sector)
SELECT g,
       co_prefix[1 + floor(random() * array_length(co_prefix, 1))::int] || ' ' ||
       co_middle[1 + floor(random() * array_length(co_middle, 1))::int] || ' ' ||
       co_suffix[1 + floor(random() * array_length(co_suffix, 1))::int],
       'RC' || (100000 + g * 17),
       DATE '1990-01-01' + floor(random() * 9000)::int,
       sectors[1 + floor(random() * array_length(sectors, 1))::int]
FROM generate_series(1501, 2000) g, names;

-- ---------------------------------------------------------------------
-- Tax returns
--   Individuals : PIT, yearly 2023-2025      (due 31 March next year)
--   Companies   : CIT, yearly 2023-2025      (due 30 June next year)
--                 VAT, monthly Jan 2025 - Sep 2026 (due 21st of next month)
--                 WHT, monthly, for every 3rd company
--   About 8% of expected returns are never filed (non-filers).
--   About 20% of filed returns are late.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tp_size AS
SELECT taxpayer_id, taxpayer_type, random() AS size FROM taxpayer;   -- small vs big taxpayers

CREATE TEMP TABLE expected_return AS
SELECT tp.taxpayer_id, tt.tax_type_id, tt.tax_code, tp.size,
       make_date(y, 1, 1)   AS period_start,
       make_date(y, 12, 31) AS period_end,
       CASE tt.tax_code WHEN 'PIT' THEN make_date(y + 1, 3, 31) ELSE make_date(y + 1, 6, 30) END AS due_date
FROM tp_size tp
JOIN tax_type tt ON (tp.taxpayer_type = 'I' AND tt.tax_code = 'PIT')
                 OR (tp.taxpayer_type = 'C' AND tt.tax_code = 'CIT')
CROSS JOIN generate_series(2023, 2025) y
UNION ALL
SELECT tp.taxpayer_id, tt.tax_type_id, tt.tax_code, tp.size,
       m::date,
       (m + interval '1 month' - interval '1 day')::date,
       (m + interval '1 month' + interval '20 days')::date
FROM tp_size tp
JOIN tax_type tt ON tp.taxpayer_type = 'C'
                AND (tt.tax_code = 'VAT' OR (tt.tax_code = 'WHT' AND tp.taxpayer_id % 3 = 0))
CROSS JOIN generate_series(DATE '2025-01-01', DATE '2026-09-01', interval '1 month') m;

CREATE TEMP TABLE draw AS
SELECT e.*, random() AS r_file, random() AS r_late, random() AS r_amt, random() AS r_status
FROM expected_return e;

INSERT INTO tax_return (taxpayer_id, tax_type_id, period_start, period_end, due_date,
                        filing_date, declared_amount, status)
SELECT taxpayer_id, tax_type_id, period_start, period_end, due_date,
       fdate,
       round((CASE tax_code
                WHEN 'PIT' THEN 1200000 * exp(size * 3.5)    -- ~1.2m .. 40m a year
                WHEN 'CIT' THEN 5000000 * exp(size * 6.5)    -- ~5m .. 3.3bn a year
                WHEN 'VAT' THEN 1000000 * exp(size * 5.5)    -- ~1m .. 245m a month
                ELSE             500000 * exp(size * 5.0)    -- ~0.5m .. 74m a month
              END * (0.8 + r_amt * 0.4))::numeric, 2),
       CASE WHEN fdate > today - 30 THEN 'SUBMITTED'
            WHEN fdate > today - 90 THEN 'UNDER_REVIEW'
            WHEN r_status < 0.04     THEN 'AUDITED'
            ELSE 'ACCEPTED' END
FROM (
  SELECT d.*, s.today,
         LEAST(CASE WHEN r_late < 0.80
                    THEN due_date - floor(r_late * 25)::int          -- on time
                    ELSE due_date + 1 + floor((r_late - 0.80) * 450)::int  -- 1..90 days late
               END, s.today) AS fdate
  FROM draw d, sim s
  WHERE d.r_file > 0.08
) f
ORDER BY period_start, taxpayer_id, tax_type_id;

-- Reviewing officer for returns that have been looked at
UPDATE tax_return r
SET reviewed_by = (SELECT o.officer_id FROM tax_officer o
                   WHERE o.role = CASE WHEN r.status = 'AUDITED' THEN 'AUDITOR' ELSE 'TAX_OFFICER' END
                     AND r.return_id > 0
                   ORDER BY random() LIMIT 1)
WHERE r.status <> 'SUBMITTED';

-- ---------------------------------------------------------------------
-- Assessments
--   Every return gets an ORIGINAL assessment = declared amount x rate.
--   Every AUDITED return also gets an ADDITIONAL assessment (5-40% more).
-- ---------------------------------------------------------------------
INSERT INTO assessment (return_id, assessment_type, amount_due, assessment_date, assessed_by, remarks)
SELECT r.return_id, 'ORIGINAL',
       round(r.declared_amount * tt.rate_percent / 100, 2),
       LEAST(r.filing_date + floor(random() * 15)::int, s.today),
       r.reviewed_by,
       'Self-assessment on filing'
FROM tax_return r JOIN tax_type tt USING (tax_type_id), sim s
ORDER BY r.return_id;

INSERT INTO assessment (return_id, assessment_type, amount_due, assessment_date, assessed_by, remarks)
SELECT r.return_id, 'ADDITIONAL',
       round(a.amount_due * (0.05 + random()::numeric * 0.35), 2),
       LEAST(a.assessment_date + 60 + floor(random() * 240)::int, s.today),
       r.reviewed_by,
       'Additional assessment after audit'
FROM tax_return r
JOIN assessment a ON a.return_id = r.return_id AND a.assessment_type = 'ORIGINAL', sim s
WHERE r.status = 'AUDITED'
ORDER BY r.return_id;

-- ---------------------------------------------------------------------
-- Payments
--   ORIGINAL:   73% paid in full, 10% paid in 2 instalments,
--               10% part-paid, 2% over-paid, 5% unpaid
--   ADDITIONAL: 70% paid in full, 30% unpaid
-- ---------------------------------------------------------------------
CREATE TEMP TABLE pay_plan AS
SELECT a.assessment_id, a.amount_due, a.assessment_date,
       CASE WHEN a.assessment_type = 'ADDITIONAL' THEN
                 CASE WHEN r < 0.30 THEN 'NONE' ELSE 'FULL' END
            WHEN r < 0.05 THEN 'NONE'
            WHEN r < 0.15 THEN 'PARTIAL'
            WHEN r < 0.25 THEN 'INSTALMENT'
            WHEN r < 0.27 THEN 'OVERPAY'
            ELSE 'FULL' END AS kind
FROM (SELECT *, random() AS r FROM assessment WHERE amount_due > 0) a;

INSERT INTO payment (assessment_id, amount, payment_date, payment_method, payment_ref)
SELECT p.assessment_id,
       CASE p.kind
         WHEN 'FULL'       THEN p.amount_due
         WHEN 'PARTIAL'    THEN round(p.amount_due * (0.5 + random()::numeric * 0.4), 2)
         WHEN 'OVERPAY'    THEN round(p.amount_due * (1.05 + random()::numeric * 0.15), 2)
         WHEN 'INSTALMENT' THEN CASE WHEN n = 1 THEN round(p.amount_due / 2, 2)
                                     ELSE p.amount_due - round(p.amount_due / 2, 2) END
       END,
       LEAST(p.assessment_date + (n - 1) * 30 + floor(random() * 25)::int, s.today),
       (ARRAY['BANK_TRANSFER','REMITA','REMITA','CARD','BANK_DRAFT'])[1 + floor(random() * 5)::int],
       'T' || substr(md5(p.assessment_id || '-' || n), 1, 19)          -- temporary, replaced below
FROM pay_plan p
CROSS JOIN LATERAL generate_series(1, CASE WHEN p.kind = 'INSTALMENT' THEN 2 ELSE 1 END) n
CROSS JOIN sim s
WHERE p.kind <> 'NONE'
ORDER BY 3, 1;

UPDATE payment
SET payment_ref = 'NRS' || to_char(payment_date, 'YYYYMMDD') || lpad(payment_id::text, 7, '0');

-- ---------------------------------------------------------------------
-- Penalties
--   LATE_FILING: N25,000 + N5,000 for each further 30 days late
--   UNDER_DECLARATION: 10% of the additional assessment after an audit
-- ---------------------------------------------------------------------
INSERT INTO penalty (return_id, reason, amount, date_applied)
SELECT r.return_id, 'LATE_FILING',
       25000 + 5000 * floor((r.filing_date - r.due_date) / 30),
       LEAST(r.filing_date + 7, s.today)
FROM tax_return r, sim s
WHERE r.filing_date > r.due_date
ORDER BY r.return_id;

INSERT INTO penalty (return_id, reason, amount, date_applied)
SELECT a.return_id, 'UNDER_DECLARATION', round(a.amount_due * 0.10, 2), a.assessment_date
FROM assessment a
WHERE a.assessment_type = 'ADDITIONAL' AND a.amount_due > 0
ORDER BY a.return_id;

-- ---------------------------------------------------------------------
-- Refunds: every over-payment produces a refund request.
--   Requested 5-39 days after paying; decided 10-59 days after the
--   request. Requests whose decision date is still in the future stay
--   PENDING.
-- ---------------------------------------------------------------------
INSERT INTO refund (payment_id, amount, request_date, status, approved_by, decision_date)
SELECT payment_id, amount, request_date,
       CASE WHEN decided THEN CASE WHEN r < 0.15 THEN 'REJECTED' WHEN r < 0.35 THEN 'APPROVED' ELSE 'PAID' END
            ELSE 'PENDING' END,
       CASE WHEN decided THEN mgr END,
       CASE WHEN decided THEN request_date + decide_after END
FROM (
  SELECT p.payment_id,
         p.amount - a.amount_due                                        AS amount,
         LEAST(p.payment_date + 5 + floor(random() * 35)::int, s.today) AS request_date,
         10 + floor(random() * 50)::int                                 AS decide_after,
         random() AS r,
         (SELECT o.officer_id FROM tax_officer o
           WHERE o.role = 'MANAGER' AND p.payment_id > 0 ORDER BY random() LIMIT 1) AS mgr,
         s.today
  FROM payment p
  JOIN assessment a ON a.assessment_id = p.assessment_id
  CROSS JOIN sim s
  WHERE p.amount > a.amount_due
) x
CROSS JOIN LATERAL (SELECT (x.request_date + x.decide_after <= x.today) AS decided) d
ORDER BY request_date;

-- ---------------------------------------------------------------------
-- Tidy up and refresh planner statistics
-- ---------------------------------------------------------------------
DROP TABLE sim, names, office_pick, tp_size, expected_return, draw, pay_plan;
ANALYZE;

-- Row counts (printed when the script runs)
SELECT 'state' AS table_name, count(*) AS row_count FROM state
UNION ALL SELECT 'tax_office',          count(*) FROM tax_office
UNION ALL SELECT 'tax_type',            count(*) FROM tax_type
UNION ALL SELECT 'tax_officer',         count(*) FROM tax_officer
UNION ALL SELECT 'taxpayer',            count(*) FROM taxpayer
UNION ALL SELECT 'individual_taxpayer', count(*) FROM individual_taxpayer
UNION ALL SELECT 'company_taxpayer',    count(*) FROM company_taxpayer
UNION ALL SELECT 'tax_return',          count(*) FROM tax_return
UNION ALL SELECT 'assessment',          count(*) FROM assessment
UNION ALL SELECT 'payment',             count(*) FROM payment
UNION ALL SELECT 'penalty',             count(*) FROM penalty
UNION ALL SELECT 'refund',              count(*) FROM refund;

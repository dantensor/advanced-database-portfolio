-- =====================================================================
-- MIT 8103 Portfolio 4: turn relational rows into MongoDB documents
--
-- Builds ONE JSON document per taxpayer. Everything that belongs to the
-- taxpayer (office, personal/company details, returns, assessments,
-- payments, penalties) is NESTED inside it. This is called "embedding".
--
-- Output: one JSON document per line (the format mongoimport reads).
-- Used by 02_load_mongo.sh, which you normally run instead of this file.
-- =====================================================================
SET search_path TO nrs;

-- Small helper: write a date the way MongoDB understands ({"$date": ...})
CREATE FUNCTION pg_temp.d(x date) RETURNS json LANGUAGE sql AS $$
  SELECT CASE WHEN x IS NULL THEN NULL
              ELSE json_build_object('$date', to_char(x, 'YYYY-MM-DD') || 'T00:00:00Z') END
$$;

SELECT json_strip_nulls(json_build_object(           -- strip_nulls: no empty fields
  '_id',           t.taxpayer_id,
  'tin',           t.tin,
  'type',          CASE t.taxpayer_type WHEN 'I' THEN 'INDIVIDUAL' ELSE 'COMPANY' END,
  'name',          COALESCE(c.company_name, i.first_name || ' ' || i.last_name),
  'status',        t.status,
  'registered_on', pg_temp.d(t.registration_date),
  'contact',       json_build_object('email', t.email, 'phone', t.phone, 'address', t.address),

  -- the office is COPIED into every taxpayer document (no join needed)
  'office',        json_build_object('code', o.office_code, 'name', o.office_name,
                                     'state', s.state_name, 'zone', s.geo_zone),

  -- individuals get a "person" section, companies a "company" section
  'person',  CASE WHEN i.taxpayer_id IS NOT NULL THEN json_build_object(
                 'first_name', i.first_name, 'last_name', i.last_name,
                 'date_of_birth', pg_temp.d(i.date_of_birth),
                 'nin', i.nin, 'occupation', i.occupation) END,
  'company', CASE WHEN c.taxpayer_id IS NOT NULL THEN json_build_object(
                 'rc_number', c.rc_number, 'sector', c.business_sector,
                 'incorporated_on', pg_temp.d(c.incorporation_date)) END,

  -- all the taxpayer's returns, each with its assessments and penalties
  'returns', COALESCE((
     SELECT json_agg(json_build_object(
              'return_id',       r.return_id,
              'tax',             tt.tax_code,
              'period_start',    pg_temp.d(r.period_start),
              'period_end',      pg_temp.d(r.period_end),
              'due_date',        pg_temp.d(r.due_date),
              'filed_on',        pg_temp.d(r.filing_date),
              'declared_amount', r.declared_amount,
              'status',          r.status,
              'assessments', (
                 SELECT json_agg(json_build_object(
                          'type',       a.assessment_type,
                          'amount_due', a.amount_due,
                          'date',       pg_temp.d(a.assessment_date),
                          'payments', COALESCE((
                             SELECT json_agg(json_build_object(
                                      'ref',    p.payment_ref,
                                      'amount', p.amount,
                                      'date',   pg_temp.d(p.payment_date),
                                      'method', p.payment_method) ORDER BY p.payment_date)
                             FROM payment p WHERE p.assessment_id = a.assessment_id), '[]'))
                        ORDER BY a.assessment_id)
                 FROM assessment a WHERE a.return_id = r.return_id),
              'penalties', COALESCE((
                 SELECT json_agg(json_build_object(
                          'reason', pe.reason, 'amount', pe.amount,
                          'date', pg_temp.d(pe.date_applied)))
                 FROM penalty pe WHERE pe.return_id = r.return_id), '[]'))
            ORDER BY r.period_start, tt.tax_code)
     FROM tax_return r JOIN tax_type tt USING (tax_type_id)
     WHERE r.taxpayer_id = t.taxpayer_id), '[]')
))
FROM taxpayer t
JOIN tax_office o ON o.office_id = t.office_id
JOIN state s      ON s.state_id  = o.state_id
LEFT JOIN individual_taxpayer i ON i.taxpayer_id = t.taxpayer_id
LEFT JOIN company_taxpayer   c ON c.taxpayer_id = t.taxpayer_id
ORDER BY t.taxpayer_id;

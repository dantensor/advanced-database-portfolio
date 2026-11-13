-- Q4  Monthly revenue report: money collected in October 2026, by state
SELECT s.geo_zone, s.state_name, count(*) AS payments, sum(p.amount) AS revenue
FROM payment p
JOIN assessment a ON a.assessment_id = p.assessment_id
JOIN tax_return r ON r.return_id     = a.return_id
JOIN taxpayer t   ON t.taxpayer_id   = r.taxpayer_id
JOIN tax_office o ON o.office_id     = t.office_id
JOIN state s      ON s.state_id      = o.state_id
WHERE p.payment_date >= DATE '2026-10-01'
  AND p.payment_date <  DATE '2026-11-01'
GROUP BY s.geo_zone, s.state_name
ORDER BY revenue DESC;

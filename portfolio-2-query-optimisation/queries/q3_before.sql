-- Q3  Compliance check: VAT returns filed LATE during December 2025
--     (written with EXTRACT(), a common beginner style)
SELECT r.return_id, r.taxpayer_id, r.period_start, r.due_date, r.filing_date
FROM tax_return r
WHERE r.tax_type_id = 2                                  -- VAT
  AND EXTRACT(YEAR  FROM r.filing_date) = 2025
  AND EXTRACT(MONTH FROM r.filing_date) = 12
  AND r.filing_date > r.due_date;

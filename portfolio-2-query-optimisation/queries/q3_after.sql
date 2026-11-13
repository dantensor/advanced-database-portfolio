-- Q3  Compliance check: VAT returns filed LATE during December 2025
--     (rewritten as a date RANGE so an index on filing_date can be used)
SELECT r.return_id, r.taxpayer_id, r.period_start, r.due_date, r.filing_date
FROM tax_return r
WHERE r.tax_type_id = 2                                  -- VAT
  AND r.filing_date >= DATE '2025-12-01'
  AND r.filing_date <  DATE '2026-01-01'
  AND r.filing_date > r.due_date;

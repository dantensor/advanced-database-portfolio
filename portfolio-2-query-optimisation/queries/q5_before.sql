-- Q5  Officer work queue: the 50 oldest returns still waiting for review
SELECT return_id, taxpayer_id, tax_type_id, filing_date
FROM tax_return
WHERE status = 'UNDER_REVIEW'
ORDER BY filing_date
LIMIT 50;

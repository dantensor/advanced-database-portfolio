-- Q6  Management dashboard: top 10 debtors (read from a materialized view)
SELECT tin, taxpayer_name, balance_owed
FROM mv_taxpayer_balance
ORDER BY balance_owed DESC
LIMIT 10;

-- Q6  Management dashboard: top 10 debtors (computed live from the view)
SELECT tin, taxpayer_name, balance_owed
FROM v_taxpayer_balance
ORDER BY balance_owed DESC
LIMIT 10;

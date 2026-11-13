-- Q2  Online portal log-in: look up a taxpayer by e-mail, ignoring case
SELECT taxpayer_id, tin, taxpayer_type, status
FROM taxpayer
WHERE lower(email) = lower('Taxpayer31337@mail.example');

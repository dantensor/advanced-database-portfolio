-- Q1  Taxpayer search screen: find an individual by surname + first name
SELECT taxpayer_id, first_name, last_name, date_of_birth, occupation
FROM individual_taxpayer
WHERE last_name = 'Okafor' AND first_name = 'Ngozi';

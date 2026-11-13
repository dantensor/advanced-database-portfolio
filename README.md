# Advanced Database Systems Portfolio – MIT 8103

**Student:** Daniel Ugbudia | **Matric No.:** 301932324 | **Email:** d.ugbudia32324@miva.edu.ng
**Session:** 2026/2027, First Semester

---

## Selected Organisation / Case Study

**Organisation:** Nigeria Revenue Service (NRS) — *simulated case study*

**Nature of the system:**
The Nigeria Revenue Service is Nigeria's central federal revenue authority. It replaced the
Federal Inland Revenue Service (FIRS) under the Nigeria Revenue Service (Establishment) Act, 2025.
This portfolio models a simplified **NRS Tax Administration Database** that covers taxpayer
registration, tax return filing, assessment, payment and refunds.

**Users of the database:**
- Taxpayers (individuals and companies)
- Tax officers (register taxpayers, review returns)
- Auditors (investigate and adjust assessments)
- Tax office managers (monitor collections and reports)
- System administrators

**Major data stored:**
Taxpayers, Tax Identification Numbers (TINs), tax offices, tax types (CIT, VAT, PIT, WHT),
tax returns, assessments, payments, refunds and penalties.

**Key operations supported:**
1. Register a taxpayer and issue a TIN
2. File a tax return for a period
3. Generate an assessment (amount of tax due)
4. Record a payment and update the taxpayer's balance
5. Process a refund for overpayment
6. Apply a penalty for late filing
7. Produce revenue reports by state, tax office and tax type

**Data disclaimer:**
All data in this repository is **synthetic (made up)**. It contains no real taxpayer
information and does not describe NRS's internal systems. The design is based only on
NRS's publicly known mandate.

---

## Repository Structure

| Folder | Portfolio | Status |
|---|---|---|
| `portfolio-1-database-design/` | Database Design and Modelling | ✅ Draft complete |
| `portfolio-2-query-optimisation/` | Query Processing and Optimisation | ✅ Draft complete |
| `portfolio-3-transactions-concurrency/` | Transactions and Concurrency | ✅ Draft complete |
| `portfolio-4-nosql/` | NoSQL and Advanced Data Models | ✅ Draft complete |
| `portfolio-5-distributed-cloud/` | Distributed and Cloud Database | ✅ Draft complete |

## Tools Used
- **PostgreSQL 16** (running in Docker), relational database for Portfolios 1–3
- **pgAdmin 4** (running in Docker), graphical tool for running SQL and viewing execution plans
- **Docker Desktop**, runs all databases without installing them directly
- **MongoDB 7.0** + **mongo-express** (running in Docker), document database for Portfolio 4 (web viewer at http://localhost:8081)
- **Two extra PostgreSQL 16 containers** (primary + replica), streaming replication for Portfolio 5

## How to Run
```bash
docker compose up -d        # start PostgreSQL + pgAdmin
# open http://localhost:5050 in your browser
docker compose down         # stop everything
```

## AI Use Declaration
_(AI tools were used as learning and support resources during this assignment. AI assistance used to clarify concepts, explain challenging areas, troubleshoot issues, and improve my understanding of the project.)_

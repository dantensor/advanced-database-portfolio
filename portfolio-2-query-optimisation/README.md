# Portfolio 2 – Query Processing and Optimisation

**Case study:** NRS Tax Administration Database (the Portfolio 1 design, loaded with a larger synthetic data set)
**DBMS:** PostgreSQL 16 in Docker (4 CPUs, default memory settings, `work_mem` = 4 MB)

This portfolio picks six realistic NRS queries and measures each one. It reads the execution plan to explain *why* the query is slow, applies one targeted optimisation, and measures again. Every number below comes from [`results/summary.md`](results/summary.md), which the benchmark script produces.

## Files in this folder

| File | What it does |
|---|---|
| [`00_load_large_data.sh`](00_load_large_data.sh) | Rebuilds the Portfolio 1 schema and loads it at **scale 25**, which takes about 3 minutes |
| [`queries/`](queries/) | The six test queries: `qN_before.sql` is the original and `qN_after.sql` is the optimised version |
| [`10_reset_baseline.sql`](10_reset_baseline.sql) | Removes all the optimisations (the baseline state) |
| [`20_optimise.sql`](20_optimise.sql) | Applies all the optimisations, with a comment explaining each one |
| [`30_benchmark.sh`](30_benchmark.sh) | Runs everything before and after the optimisations and writes `results/` |
| [`results/`](results/) | Full `EXPLAIN (ANALYZE, BUFFERS)` plans for every query, plus `summary.md` |

### How to run

```bash
bash portfolio-2-query-optimisation/00_load_large_data.sh
```

```bash
bash portfolio-2-query-optimisation/30_benchmark.sh
```

This replaces the small Portfolio 1 data with the large data set. To return to the small data, run the Portfolio 1 scripts again.

### Data volume (scale 25)

| Table | Rows |
|---|---:|
| taxpayer | 50,000 (37,500 individuals, 12,500 companies) |
| tax_return | 460,181 |
| assessment | 476,947 |
| payment | 494,999 |
| penalty | 109,167 |
| refund | 9,170 |

---

## 1. How PostgreSQL processes a query

```
 SQL text ─► Parser ─► Rewriter ─► Planner / Optimiser ─► Executor ─► rows
             (syntax,   (expands     (generates candidate   (runs the plan
              names)     views)       plans, estimates       tree, node by
                                      cost, picks cheapest)  node)
```

1. **Parser.** Checks the syntax and turns the SQL into a parse tree. It also checks that every table and column exists.
2. **Rewriter.** Applies rules. The main one here is that a **view** reference, such as `v_taxpayer_balance` in Q6, is replaced by the view's full query.
3. **Planner/optimiser.** A **cost-based optimiser**. For each table it considers the possible *access paths*: sequential scan, index scan, bitmap scan and index-only scan. For each join it considers the *join methods*: nested loop, hash join and merge join, in different join orders. It estimates the cost of each plan and keeps the cheapest. The estimates use **statistics** that `ANALYZE` collects: row counts, distinct values and the most common values of each column.
4. **Executor.** Runs the chosen plan as a tree of nodes. Each node pulls rows from the nodes below it.

`EXPLAIN` shows the chosen plan with *estimated* costs. `EXPLAIN (ANALYZE, BUFFERS)` also **runs** the query and shows the *actual* time, the actual number of rows and the pages read for every node. All measurements in this portfolio use `EXPLAIN (ANALYZE, BUFFERS)`.

> **Tip for pgAdmin:** open a query in the Query Tool and press **F7**, or click *Explain*, to see the same plan drawn as a diagram.

### Method
- Each query runs **once to warm the cache, then 7 times**. The **median** "Execution Time" is reported. Both phases run with a warm cache, so the comparison is fair.
- **Baseline** = the Portfolio 1 design. Primary keys, unique constraints and foreign-key indexes already exist.
- The optimisations are added, `VACUUM ANALYZE` refreshes the statistics, and the same measurement is repeated.

---

## 2. Results summary

| Query | Business purpose | Before (ms) | After (ms) | Speed-up | Technique |
|---|---|---:|---:|---:|---|
| Q1 | Find an individual by name | 5.57 | 0.25 | **22×** | Composite B-tree index |
| Q2 | Portal log-in by e-mail (any case) | 60.26 | 0.07 | **899×** | Expression index on `lower(email)` |
| Q3 | Late VAT returns in Dec 2025 | 54.84 | 5.70 | **9.6×** | Query rewrite (sargable) + composite index |
| Q4 | Monthly revenue by state | 208.32 | 169.16 | **1.2×** | Covering index (limited effect, see §3) |
| Q5 | Officer review queue (oldest 50) | 49.43 | 0.34 | **145×** | Partial index |
| Q6 | Top 10 debtors | 2,849.51 | 0.14 | **20,649×** | Materialized view |

Timings vary by a few percent each time the benchmark runs. The pattern stays the same.

---

## 3. Query-by-query analysis

### Q1. Find an individual taxpayer by name
```sql
SELECT ... FROM individual_taxpayer WHERE last_name = 'Okafor' AND first_name = 'Ngozi';
```
- **Before.** `Seq Scan on individual_taxpayer`. All 37,500 rows are read to return 32 matches. Nothing indexes the name columns.
- **Fix.** `CREATE INDEX idx_individual_name ON individual_taxpayer (last_name, first_name);`
- **After.** `Bitmap Index Scan` on the new index, then a `Bitmap Heap Scan` that fetches only the matching pages. **22× faster.**
- **Why this column order?** A composite B-tree can be used for searches on its *leading* column. With `last_name` first, the same index also serves a surname-only search. An index on `(first_name, last_name)` could not do that.

### Q2. Case-insensitive e-mail look-up (portal log-in)
```sql
SELECT ... FROM taxpayer WHERE lower(email) = lower('Taxpayer31337@mail.example');
```
- **Before.** `Seq Scan on taxpayer`, about 60 ms to find **one** row. Even if a normal index on `email` existed, the planner could not use it. The index stores the original values, and the condition is on `lower(email)`, which is a different value.
- **Fix.** An **expression (functional) index**: `CREATE INDEX idx_taxpayer_email_lower ON taxpayer (lower(email));`
- **After.** `Index Scan using idx_taxpayer_email_lower`, 0.07 ms, **about 900× faster.** This query has the highest selectivity in the set (1 row out of 50,000), so an index gives the biggest gain here.

### Q3. Late VAT returns filed in December 2025: a query rewrite
```sql
-- before                                         -- after
AND EXTRACT(YEAR  FROM filing_date) = 2025        AND filing_date >= DATE '2025-12-01'
AND EXTRACT(MONTH FROM filing_date) = 12          AND filing_date <  DATE '2026-01-01'
```
- **Before.** `Parallel Seq Scan on tax_return`. 152,607 rows are removed by the filter in each of 3 workers, about 55 ms.
- **The problem.** Wrapping a column in a function, as in `EXTRACT(... FROM filing_date)`, makes the condition **non-sargable**: it cannot be answered from an index on `filing_date`.
- **Fix.** Two changes:
  1. Rewrite the condition as a plain **date range**, which is logically identical.
  2. Add `CREATE INDEX idx_return_type_filing ON tax_return (tax_type_id, filing_date);`. The equality column goes first and the range column second.
- **After.** `Bitmap Index Scan on idx_return_type_filing`, 5.7 ms, **9.6× faster.**
- **Experiment.** With the new index in place but the **old** SQL, the query still took **52.7 ms** and still did a `Parallel Seq Scan`. See `results/q3_index_not_rewritten_plan.txt`. **An index alone does not help a non-sargable query; you need both the rewrite and the index.**

### Q4. Monthly revenue by state: when an index is not enough
```sql
SELECT s.geo_zone, s.state_name, count(*), sum(p.amount)
FROM payment p JOIN assessment a ... JOIN tax_return r ... JOIN taxpayer t ...
     JOIN tax_office o ... JOIN state s ...
WHERE p.payment_date >= DATE '2026-10-01' AND p.payment_date < DATE '2026-11-01'
GROUP BY ...;
```
- **Before.** About 208 ms. The plan joins six tables with **hash joins**, and the payment table is read with a `Parallel Seq Scan`.
- **Fix.** A **covering index**: `CREATE INDEX idx_payment_date_cover ON payment (payment_date) INCLUDE (assessment_id, amount);`
- **After.** The payment step became a `Parallel Index Only Scan` with **0 heap fetches**. Every column the query needs is in the index, so the table itself is never read. That step fell from **about 44 ms to about 2.5 ms**. Even so, the whole query only went from 208 ms to 169 ms (**1.2×**).
- **Why so little?** Reading the plan node by node shows the time is now spent on the **joins**. Each of the 17,657 October payments still has to be joined through `assessment` (477,000 rows, read by a parallel sequential scan to build a hash table), then `tax_return` and `taxpayer`, to find its state. The index fixed the part of the query that was no longer the main cost.
- **What else was tried.** Forcing the alternative plan (nested-loop index look-ups into `assessment`, with `random_page_cost = 1.1` for SSD storage) gave about 136 ms. The optimiser's choice was close to the best available. It did not choose that plan consistently, because it depends on the statistics sample.
- **Real-world fix.** For a report that runs once a month, the right answer is the same as Q6. Pre-aggregate the revenue per office per month into a summary table or materialized view, refreshed nightly. **Lesson: measure first. Indexes speed up *finding* rows, not *joining* many of them.**

### Q5. Officer work queue: oldest 50 returns under review
```sql
SELECT ... FROM tax_return WHERE status = 'UNDER_REVIEW' ORDER BY filing_date LIMIT 50;
```
- **Before.** `Parallel Seq Scan` of all 460,000 returns to find the 31,000 under review, then a `top-N heapsort`. About 49 ms and 9,482 pages touched.
- **Fix.** A **partial index**, which indexes only the rows the queue cares about: `CREATE INDEX idx_return_review_queue ON tax_return (filing_date) WHERE status = 'UNDER_REVIEW';`
- **After.** `Index Scan using idx_return_review_queue`. The index is already sorted by `filing_date`, so PostgreSQL reads the first 50 entries and **stops**, with **no sort step** and only **48 pages** touched. 0.34 ms, **145× faster.**
- **Bonus.** The partial index is only **240 kB**, compared with about 3 MB for a full index on `filing_date`. Returns that are already ACCEPTED, which is most of them, never enter it.

### Q6. Top 10 debtors: a materialized view
```sql
SELECT tin, taxpayer_name, balance_owed FROM v_taxpayer_balance ORDER BY balance_owed DESC LIMIT 10;
```
- **Before.** About **2.85 seconds**. The rewriter expands the view, so every run aggregates all assessments, penalties, payments and refunds (about 1.5 million rows) for all 50,000 taxpayers, only to show 10 of them. The plan also shows `temp read/written`: the hash aggregates did not fit in `work_mem` (4 MB) and **spilled to disk**.
- **Fix.** A **materialized view**, which stores the result of the view as a real table, plus an index on `balance_owed DESC`.
  ```sql
  CREATE MATERIALIZED VIEW mv_taxpayer_balance AS SELECT * FROM v_taxpayer_balance;
  CREATE INDEX idx_mv_balance_owed ON mv_taxpayer_balance (balance_owed DESC);
  ```
- **After.** `Index Scan using idx_mv_balance_owed`: read 10 entries and stop. 0.14 ms (12 pages), about **20,000× faster.**
- **Trade-off.** The materialized view is a **snapshot**. It does not change when a payment is recorded. It has to be refreshed, for example nightly:
  `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_taxpayer_balance;`
  `CONCURRENTLY` lets users keep reading during the refresh, and needs the unique index `idx_mv_balance_id`. This suits a **management dashboard**, where yesterday's figures are acceptable. It does **not** suit a taxpayer checking their own balance after paying. That case keeps using the live view `v_taxpayer_balance` for one TIN, which is fast because it is filtered.

---

## 4. Costs of the optimisations

Indexes are not free. They use disk space and slow down every `INSERT`, `UPDATE` and `DELETE` on the table, because each index must be updated too.

**Write cost.** 50,000 payments were inserted inside a transaction that was rolled back afterwards:

| State | Time |
|---|---:|
| Baseline (3 indexes on `payment`) | 1,602 ms |
| + `idx_payment_date_cover` (4 indexes) | 1,746 ms (**+9%**) |

**Storage:**

| Object | Size |
|---|---:|
| idx_payment_date_cover | 27 MB |
| mv_taxpayer_balance | 5.0 MB |
| idx_return_type_filing | 3.2 MB |
| idx_taxpayer_email_lower | 2.4 MB |
| idx_mv_balance_owed | 1.3 MB |
| idx_mv_balance_id | 1.1 MB |
| idx_individual_name | 320 kB |
| idx_return_review_queue | 240 kB |

The covering index is the largest, because it copies two extra columns. Given that Q4 improved only 1.2×, it is the **weakest** optimisation in this set. In production it would be kept only if the October-style report ran often. The NRS workload reads far more often than it writes, since returns are filed once and then read many times. So the read gains of Q1, Q2, Q3, Q5 and Q6 easily justify a small write penalty.

---

## 5. Conclusions

1. **Read the plan before optimising.** Every fix here came from a specific node in `EXPLAIN ANALYZE`, such as a `Seq Scan` with many "Rows Removed by Filter", a `Sort`, or a `temp written` spill.
2. **Indexes work best for selective queries.** The biggest wins were Q2 (1 row) and Q5 (`LIMIT 50` on a sorted index). The benefit falls as the fraction of rows returned grows.
3. **How a query is written matters.** A function wrapped around an indexed column (Q3) blocks the index. Rewriting it as a range was required.
4. **Choose the right kind of index:** composite (Q1), expression (Q2), composite with equality-then-range order (Q3), covering/`INCLUDE` (Q4), partial (Q5).
5. **Not every slow query is an indexing problem.** Q4 is limited by its joins. Pre-aggregation (Q6-style) is the appropriate fix.
6. **Every optimisation has a cost:** extra storage, slower writes (+9% here), and stale data for materialized views. The choice depends on the workload.

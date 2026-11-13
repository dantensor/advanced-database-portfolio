# Portfolio 3 – Transactions and Concurrency

**Case study:** NRS Tax Administration Database (from Portfolio 1)
**DBMS:** PostgreSQL 16 in Docker

This portfolio shows, with small runnable demos, how a database keeps data correct:
- when something goes wrong in the middle of a task (**transactions and ACID**), and
- when two people change the same data at the same time (**concurrency control**).

## Files in this folder

| File | What it does |
|---|---|
| [`01_setup.sql`](01_setup.sql) | Creates one small demo table, `tax_credit` |
| [`02_acid_demo.sql`](02_acid_demo.sql) | Atomicity, consistency and savepoints, in one session |
| [`03_concurrency_demos.sh`](03_concurrency_demos.sh) | Two sessions running at the same time: lost update, locking, isolation levels, deadlock, durability |
| [`results/`](results/) | The saved output of every demo |

### How to run

From the main project folder, with the database running:

```bash
docker exec -i nrs_postgres psql -U nrs_admin -d nrs_tax_db < portfolio-3-transactions-concurrency/01_setup.sql
```

```bash
docker exec -i nrs_postgres psql -U nrs_admin -d nrs_tax_db < portfolio-3-transactions-concurrency/02_acid_demo.sql
```

```bash
bash portfolio-3-transactions-concurrency/03_concurrency_demos.sh
```

The demos work with either the small (Portfolio 1) or the large (Portfolio 2) data. The last demo briefly stops and restarts the database, so pgAdmin may lose its connection for a few seconds.

### The demo table

When a taxpayer overpays, the NRS can keep the extra money as a **tax credit** and use it to pay future tax. The demos use one small table for this:

```sql
CREATE TABLE tax_credit (
    taxpayer_id  INT PRIMARY KEY REFERENCES taxpayer(taxpayer_id),
    balance      NUMERIC(15,2) NOT NULL CHECK (balance >= 0)   -- can never go negative
);
-- taxpayers 1, 2 and 3 each start with N100,000
```

In Portfolio 1 the taxpayer's *tax balance* is calculated, not stored. The credit is different. It is a running amount that officers draw from, which is exactly the kind of value that goes wrong when two people update it at once.

---

## 1. What is a transaction?

A **transaction** is a group of SQL statements that the database treats as **one single unit of work**:

```sql
BEGIN;                 -- start
  ... several INSERT / UPDATE / DELETE statements ...
COMMIT;                -- save everything   (or ROLLBACK; to undo everything)
```

For example, registering a taxpayer means inserting into `taxpayer` **and** into `individual_taxpayer`. The two must happen together or not at all.

Transactions guarantee the four **ACID** properties:

| Property | Meaning | Demo |
|---|---|---|
| **A**tomicity | All statements succeed, or none of them do | 2A |
| **C**onsistency | The data always obeys the rules: keys, CHECKs and foreign keys | 2B |
| **I**solation | Transactions running at the same time do not wrongly affect each other | 3, 4, 5 |
| **D**urability | Once committed, data survives a crash | 7 |

---

## 2. ACID in one session ([`02_acid_demo.sql`](02_acid_demo.sql))

Output: [`results/acid_demo.txt`](results/acid_demo.txt)

### 2A. Atomicity: all or nothing
A new taxpayer is registered with two inserts. The **second insert fails**, because the NIN is already used by another person:

```
ERROR:  duplicate key value violates unique constraint "individual_taxpayer_nin_key"
```

The first insert (the `taxpayer` row) had already succeeded. Because both were in one transaction, PostgreSQL **rolled back both**, and a search for the new TIN returns **0 rows**. Without a transaction, the database would be left with a "half-registered" taxpayer who has a TIN but no personal details.

### 2B. Consistency: rules are never broken
Trying to use ₦150,000 from a credit of ₦100,000:

```
ERROR:  new row for relation "tax_credit" violates check constraint "tax_credit_balance_check"
DETAIL:  Failing row contains (1, -50000.00).
```

The balance stays at ₦100,000. The `CHECK (balance >= 0)` rule protects the data even when the application has a bug.

### 2C. Savepoints: undo only part of a transaction
```sql
BEGIN;
UPDATE ... balance - 20000 ...;          -- good step
SAVEPOINT before_mistake;
UPDATE ... balance - 5000000 ...;        -- mistake -> ERROR
ROLLBACK TO SAVEPOINT before_mistake;    -- undo only the mistake
COMMIT;                                  -- the good step is kept
```
Result: the balance is **₦80,000**. The good ₦20,000 step was saved and the mistake was thrown away.

---

## 3. Concurrency problem: the lost update

Output: [`results/demo1_lost_update.txt`](results/demo1_lost_update.txt)

Two officers, A and B, each want to use **₦60,000** of the same taxpayer's ₦100,000 credit at the same moment. Each one first **reads** the balance, checks there is enough, then **writes** the new balance. This is how a typical application works.

| Time | Officer A | Officer B |
|---|---|---|
| 0s | reads balance = 100,000 | |
| 1s | | reads balance = 100,000 (A has not saved yet) |
| 2s | 100,000 ≥ 60,000, so writes **40,000** and commits | |
| 3s | | 100,000 ≥ 60,000, so writes **40,000** and commits |

**Final balance: ₦40,000.** But ₦120,000 was handed out from a ₦100,000 credit. Officer A's update was simply **overwritten** by B. This is the **lost update** problem. Note that the CHECK constraint could not catch it, because 40,000 is a valid number. The problem is the *timing*, not the value.

## 4. The fix: locking with `SELECT ... FOR UPDATE`

Output: [`results/demo2_fixed_with_for_update.txt`](results/demo2_fixed_with_for_update.txt)

The only change is that each officer reads the balance with `FOR UPDATE`:

```sql
SELECT balance FROM tax_credit WHERE taxpayer_id = 1 FOR UPDATE;
```

This puts a **row lock** on the taxpayer's credit. Anyone else asking for the same row with `FOR UPDATE` must **wait** until the first transaction finishes.

| Time | Officer A | Officer B |
|---|---|---|
| 0s | reads 100,000 **and locks the row** | |
| 1s | | asks for the row, **has to wait** |
| 2s | writes 40,000 and commits, which releases the lock | lock granted, reads **40,000** |
| | | 40,000 < 60,000, so the **request is refused** |

**Final balance: ₦40,000, and only ₦60,000 was handed out.** Correct.

This is **pessimistic locking**: lock first, then work. Locks are held until `COMMIT` or `ROLLBACK`, which is how **two-phase locking (2PL)** works. A transaction gains locks while it works and releases them all at the end.

> Another fix is to do the check and the change in **one** statement:
> `UPDATE tax_credit SET balance = balance - 60000 WHERE taxpayer_id = 1 AND balance >= 60000;`
> PostgreSQL locks the row while it runs the statement, so no other session can change it between the check and the write.

---

## 5. Isolation levels

Output: [`results/demo3_read_committed.txt`](results/demo3_read_committed.txt), [`results/demo3_repeatable_read.txt`](results/demo3_repeatable_read.txt)

The **isolation level** decides how much a transaction can see of other people's changes while it is running. A manager (A) reads the same balance **twice** in one transaction. In between, officer B uses ₦30,000 and commits.

| Isolation level | A's 1st read | A's 2nd read | What happened |
|---|---:|---:|---|
| **READ COMMITTED** (PostgreSQL default) | 100,000 | **70,000** | **Non-repeatable read**: the same query gave two different answers |
| **REPEATABLE READ** | 100,000 | **100,000** | A works on a fixed **snapshot** taken at the start of its transaction |

PostgreSQL gives every transaction a **snapshot** of the data, so it never has to block readers. This is called **MVCC** (Multi-Version Concurrency Control). Writers create new versions of a row while readers keep seeing the old version. **Readers never block writers, and writers never block readers.**

The standard concurrency problems and which levels prevent them in PostgreSQL:

| Problem | READ COMMITTED | REPEATABLE READ | SERIALIZABLE |
|---|:-:|:-:|:-:|
| Dirty read (seeing uncommitted data) | prevented | prevented | prevented |
| Non-repeatable read | **possible** | prevented | prevented |
| Phantom read (new rows appear) | **possible** | prevented* | prevented |
| Lost update / write skew | **possible** | lost update prevented** | prevented |

\* PostgreSQL's REPEATABLE READ is stricter than the SQL standard and also prevents phantoms.
\** In REPEATABLE READ, a second writer gets an error *"could not serialize access due to concurrent update"* and must retry.

**When to use which:** READ COMMITTED with `FOR UPDATE` where needed suits normal day-to-day work. REPEATABLE READ suits reports that must be consistent from start to finish, such as an end-of-month revenue report. SERIALIZABLE suits the most sensitive money operations, provided the application can retry.

---

## 6. Deadlock

Output: [`results/demo4_deadlock.txt`](results/demo4_deadlock.txt)

| Time | Officer A | Officer B |
|---|---|---|
| 0s | locks taxpayer **1** | |
| 1s | | locks taxpayer **2** |
| 2s | wants taxpayer 2, **waits for B** | |
| 4s | | wants taxpayer 1, **waits for A** |

Each is waiting for the other, so without help they would wait forever. That is a **deadlock**. PostgreSQL checks for this after waiting one second (`deadlock_timeout`). It finds the cycle and **cancels one transaction**, the "victim":

```
ERROR:  deadlock detected
DETAIL:  Process ... waits for ShareLock on transaction ...; blocked by process ...
         Process ... waits for ShareLock on transaction ...; blocked by process ...
```

B was cancelled and rolled back, and A then finished normally. Taxpayer 1's balance is ₦99,000: only A's ₦1,000 was applied.

**How to avoid deadlocks:** always lock rows in the **same order**, for example lowest `taxpayer_id` first. Keep transactions short. Have the application **retry** a transaction that was cancelled.

---

## 7. Durability: surviving a crash

Output: [`results/demo5_durability.txt`](results/demo5_durability.txt)

1. Taxpayer 3's balance was set to **12,345** and committed.
2. The database server was **killed** with `docker kill --signal=KILL`, like pulling the power plug, with no clean shutdown.
3. The server was started again. Its log shows it repairing itself:
   ```
   LOG:  database system was not properly shut down; automatic recovery in progress
   LOG:  redo starts at ...
   LOG:  redo done at ...
   ```
4. Taxpayer 3's balance was read again: **12,345**. The committed data survived.

**How this works:** before `COMMIT` returns, PostgreSQL writes the change to the **Write-Ahead Log (WAL)** on disk. After a crash it **replays ("redoes")** the WAL to rebuild every committed change. Changes that were never committed are not replayed, so they disappear. That also covers atomicity after a crash.

---

## 8. Summary

| Problem | Cause | Solution shown |
|---|---|---|
| Half-finished work | An error in the middle of a task | Transactions: `BEGIN` / `COMMIT` / `ROLLBACK` |
| Invalid data | Bugs or bad input | Constraints (`CHECK`, `UNIQUE`, `FOREIGN KEY`) |
| Lost update | Read, then write, while someone else does the same | `SELECT ... FOR UPDATE` (row locking) |
| Non-repeatable read | Another transaction commits between two reads | `REPEATABLE READ` isolation (snapshot) |
| Deadlock | Two transactions lock rows in opposite order | Detected automatically; avoid by locking in a fixed order |
| Lost data after a crash | Power failure or crash | Write-Ahead Log replay (durability) |

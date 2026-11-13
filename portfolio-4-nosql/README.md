# Portfolio 4 – NoSQL and Advanced Data Models

**Case study:** NRS Tax Administration Database (from Portfolio 1)
**NoSQL database:** MongoDB 7.0, a **document database**, running in Docker

This portfolio takes the same 2,000 NRS taxpayers from the PostgreSQL database in Portfolio 1 and stores them in MongoDB, where **each taxpayer becomes one document**. It then runs similar queries in MongoDB and compares the two approaches. Both strengths and weaknesses are covered.

## Files in this folder

| File | What it does |
|---|---|
| [`01_build_documents.sql`](01_build_documents.sql) | A PostgreSQL query that turns relational rows into one JSON document per taxpayer |
| [`02_load_mongo.sh`](02_load_mongo.sh) | Runs that query and loads the documents into MongoDB |
| [`03_queries.js`](03_queries.js) | Six MongoDB queries (Q1–Q6) |
| [`results/queries_output.txt`](results/queries_output.txt) | The output of the queries |

### How to run

From the main project folder. Start the containers (MongoDB is now in `docker-compose.yml`):

```bash
docker compose up -d
```

Load the taxpayers into MongoDB. The small Portfolio 1 data must be loaded in PostgreSQL first:

```bash
bash portfolio-4-nosql/02_load_mongo.sh
```

Run the queries:

```bash
docker exec -i nrs_mongo sh -c 'cat > /tmp/q.js && mongosh nrs --quiet /tmp/q.js' < portfolio-4-nosql/03_queries.js
```

**To browse the data**, open **http://localhost:8081** and log in with `admin` / `admin`. This is mongo-express, a web viewer for MongoDB that works like pgAdmin. Click the **nrs** database, then **taxpayers**, then any document.

---

## 1. What is NoSQL?

"NoSQL" ("not only SQL") covers databases that do **not** store data in tables of rows and columns. The four main types:

| Type | How data is stored | Example product | Good for |
|---|---|---|---|
| **Document** | JSON-like documents | **MongoDB** (used here) | Records with nested details that are read as a whole |
| Key-value | A key and an opaque value | Redis | Caching, sessions |
| Column-family | Rows with flexible column groups | Cassandra | Very large write-heavy data |
| Graph | Nodes and relationships | Neo4j | Networks, such as fraud rings between companies |

A **document database** fits this case study well. A taxpayer "file" is naturally one thing: the taxpayer's details plus all their returns and payments.

### Key MongoDB terms

| Relational (PostgreSQL) | MongoDB |
|---|---|
| Database | Database (`nrs`) |
| Table | **Collection** (`taxpayers`) |
| Row | **Document** |
| Column | **Field** |
| Primary key | `_id` |
| JOIN | **Embedding** (nesting), or `$lookup` |
| SQL | MongoDB Query API + **aggregation pipeline** |

---

## 2. From tables to documents

In Portfolio 1, one taxpayer's information is spread over **9 tables**: `taxpayer`, `individual_taxpayer` or `company_taxpayer`, `tax_office`, `state`, `tax_return`, `tax_type`, `assessment`, `payment` and `penalty`. In MongoDB it is **one document**. Here is taxpayer 1, shortened to one return:

```js
{
  _id: 1,
  tin: '1000004271',
  type: 'INDIVIDUAL',
  name: 'Fatima Okafor',
  status: 'DORMANT',
  registered_on: ISODate('2022-10-07'),
  contact: { email: 'taxpayer1@mail.example', phone: '08010000037', address: '1 Market Road' },
  office:  { code: 'TO033', name: 'NRS Lagos Tax Office', state: 'Lagos', zone: 'South West' },
  person:  { first_name: 'Fatima', last_name: 'Okafor', date_of_birth: ISODate('1978-04-15'),
             nin: '30000001013', occupation: 'Teacher' },
  returns: [
    { return_id: 1, tax: 'PIT',
      period_start: ISODate('2023-01-01'), period_end: ISODate('2023-12-31'),
      due_date: ISODate('2024-03-31'), filed_on: ISODate('2024-03-28'),
      declared_amount: 1890229.17, status: 'ACCEPTED',
      assessments: [
        { type: 'ORIGINAL', amount_due: 283534.38, date: ISODate('2024-04-03'),
          payments: [ { ref: 'NRS202404140000675', amount: 168595.47,
                        date: ISODate('2024-04-14'), method: 'REMITA' } ] }
      ],
      penalties: [] }
    // ... more returns
  ]
}
```

### Design decisions

| Decision | Choice | Reason |
|---|---|---|
| Returns, assessments, payments, penalties | **Embedded** (nested arrays) | They belong to one taxpayer only and are usually read together with the taxpayer |
| Office and state | **Copied in** (denormalised) | Avoids a join on every read. Offices rarely change |
| Individual vs company details | Optional `person` **or** `company` section | No subtype tables and no empty (NULL) fields |
| Officers | **Left out** | They are shared by many taxpayers. They would be a separate collection referenced by ID |
| Refunds | Left out | Kept out to make the example simpler |

**Size check.** The average document is about **4 KB** and the largest is about **18 KB**, well below MongoDB's 16 MB limit per document. A big company files 45 returns over the period. Over many years the arrays would keep growing. A real system would then move returns into their own collection, which is the **referencing** pattern.

---

## 3. Queries and results

Full output: [`results/queries_output.txt`](results/queries_output.txt)

### Q1. A taxpayer's full profile by TIN (with and without an index)
```js
db.taxpayers.find({ tin: "1000004271" })
```
| | Plan stage | Documents examined |
|---|---|---:|
| No index | `COLLSCAN` (reads the whole collection) | 2,000 |
| After `createIndex({ tin: 1 }, { unique: true })` | `IXSCAN` (index scan) | **1** |

This works the same way as indexes in Portfolio 2: `COLLSCAN` is MongoDB's "Seq Scan". The difference is that the result is the **whole taxpayer file** (details, office, 3 returns, assessments and payments) from **one read with no joins**. In SQL the same result needs joins across about 9 tables.

### Q2. Flexible schema
```js
db.taxpayers.find({ "company.sector": "Health", "office.state": "Lagos" })
```
1,500 individuals and 500 companies sit in **one collection**, even though they have different fields. **Dot notation** (`"office.state"`) queries inside nested objects. The relational design needed two subtype tables to achieve the same thing without NULLs.

### Q3. Revenue in 2025 by state (aggregation pipeline)
```js
db.taxpayers.aggregate([
  { $unwind: "$returns" },                          // one row per return
  { $unwind: "$returns.assessments" },              // ... per assessment
  { $unwind: "$returns.assessments.payments" },     // ... per payment
  { $match: { "returns.assessments.payments.date": { $gte: ISODate("2025-01-01"), $lt: ISODate("2026-01-01") } } },
  { $group: { _id: "$office.state", revenue: { $sum: "$returns.assessments.payments.amount" } } },
  { $sort: { revenue: -1 } }, { $limit: 5 }
])
```

| State | MongoDB result (₦) | Portfolio 1 SQL report 7a (₦) |
|---|---:|---:|
| Lagos | 42,511,957,396.36 | 42,511,957,396.36 |
| FCT Abuja | 12,708,135,820.63 | 12,708,135,820.63 |
| Abia | 2,602,469,123.37 | 2,602,469,123.37 |

The figures are **identical**, which shows that the conversion to documents lost no data. The **aggregation pipeline** is a series of stages, each passing its result to the next, much like the steps of an SQL query plan. `$unwind` "opens up" an array so each element becomes its own record.

### Q4. Taxpayers with the most late returns
```js
{ $match: { $expr: { $gt: ["$returns.filed_on", "$returns.due_date"] } } }
```
`$expr` compares two fields of the same record, like `WHERE filing_date > due_date` in SQL. The top result was *Pinnacle Agro Allied Holdings Ltd*, with **18 late returns**.

### Q5. Add a payment inside the nested document
```js
db.taxpayers.updateOne(
  { tin: "1000004271" },
  { $push: { "returns.$[r].assessments.$[a].payments": { ref: "DEMO-MONGO-001", amount: 50000, ... } } },
  { arrayFilters: [ { "r.return_id": 1 }, { "a.type": "ORIGINAL" } ] })
```
The payments on return 1 went from **1 to 2**. A change to a single document is **atomic** in MongoDB, so all of it happens or none of it does. Because the whole taxpayer file is one document, many updates are safe without a multi-statement transaction. The demo was undone afterwards.

### Q6. The cost of copying data: renaming a tax office
| | Records to update |
|---|---:|
| PostgreSQL: `UPDATE tax_office SET office_name = ...` | **1 row** |
| MongoDB: the office name is copied into every taxpayer document | **166 documents** |

This is the **update anomaly** that normalisation (Portfolio 1) is designed to prevent. Embedding makes reads fast, but it puts the duplication back. If one of the 166 updates failed, the data would be inconsistent. The demo was undone afterwards.

---

## 4. Relational vs document: comparison

| | PostgreSQL (relational) | MongoDB (document) |
|---|---|---|
| Structure | Fixed schema, defined in advance | Flexible. Documents in one collection can differ |
| Reading one taxpayer's full file | Joins across about 9 tables | **One document read** |
| Reports across all taxpayers | **Simple SQL** with `GROUP BY` | Possible (`$unwind` + `$group`) but longer |
| Duplication | **None** (normalised to 3NF/BCNF) | Office data copied 166 times (Q6) |
| Data rules | Strong: foreign keys, CHECK, UNIQUE (Portfolio 1) | Weaker. Optional JSON Schema validation, no foreign keys |
| Transactions | Full ACID across many tables (Portfolio 3) | Atomic per document. Multi-document transactions exist but are slower |
| Scaling | Mainly scale up (a bigger server) | Built to scale out (**sharding** across servers) |

### CAP theorem and BASE
In a **distributed** database, network failures between servers (**P**artitions) will happen. The **CAP theorem** says that during a partition, a system must choose between:
- **C**onsistency: every read sees the latest write, or
- **A**vailability: every request gets an answer, even if it may be out of date.

Traditional relational databases favour **ACID** and consistency. Many NoSQL systems follow **BASE** (*Basically Available, Soft state, Eventually consistent*): they stay available, and the copies become consistent a short time later. MongoDB, with default settings, favours **consistency**, because writes go to one primary server. Portfolio 5 looks at distribution in more detail.

### Recommendation for the NRS
- **Keep PostgreSQL as the system of record** for assessments, payments and refunds. This is money, so strong rules, no duplication and full ACID transactions matter most.
- **MongoDB suits read-heavy, document-shaped features**, for example a **taxpayer self-service portal** that shows a taxpayer's whole file in one fast read. It could be refreshed from PostgreSQL, the same way this portfolio loads it.

Using the right database for each job, side by side, is called **polyglot persistence**.

# Portfolio 5 – Distributed and Cloud Database

**Case study:** NRS Tax Administration Database (from Portfolio 1)
**Setup:** two PostgreSQL 16 servers in Docker (a primary and a replica) on one laptop, standing in for servers in different locations

The NRS serves taxpayers in all 36 states and the FCT. A single database server is a risk: if it fails, nobody can file or pay. This portfolio shows how a database can be spread over **more than one server**. It also covers how that could be run **in the cloud**.

## Files in this folder

| File | What it does |
|---|---|
| [`docker-compose.yml`](docker-compose.yml) | Defines the two servers: `nrs_pg_primary` (port 5433) and `nrs_pg_replica` (port 5434) |
| [`primary-init.sh`](primary-init.sh) | Creates the replication user on the primary |
| [`01_start_cluster.sh`](01_start_cluster.sh) | Starts both servers fresh and loads the Portfolio 1 data into the **primary only** |
| [`02_replication_demo.sh`](02_replication_demo.sh) | Replication, the read-only replica, and failover |
| [`03_partitioning.sql`](03_partitioning.sql) | Splitting a table into pieces (fragmentation) |
| [`results/`](results/) | Saved output of both demos |

### How to run

From the main project folder:

```bash
bash portfolio-5-distributed-cloud/01_start_cluster.sh
```

```bash
bash portfolio-5-distributed-cloud/02_replication_demo.sh
```

```bash
docker exec -i nrs_postgres psql -U nrs_admin -d nrs_tax_db < portfolio-5-distributed-cloud/03_partitioning.sql
```

When finished, stop the two demo servers. Your main database is not affected:

```bash
docker compose -f portfolio-5-distributed-cloud/docker-compose.yml down -v
```

---

## 1. What is a distributed database?

A **distributed database** stores data on **several servers (nodes)** that work together and appear to the user as **one database**. The two main techniques:

| Technique | What it means | Main benefit |
|---|---|---|
| **Replication** | Keep **copies** of the same data on several servers | Availability (survives a server failure) and spreading the read load |
| **Fragmentation / partitioning** | **Split** the data into pieces, each stored in a different place | Scale (no single server holds everything) and keeping data near its users |

Both are demonstrated below.

---

## 2. Replication: primary + replica

```
   Officers & taxpayers
      |  writes + reads             reads only (reports, portal)
      v                                  |
 ┌──────────────┐   streams changes   ┌──────────────┐
 │  pg_primary  │ ──────────────────► │  pg_replica  │
 │ read + write │   (WAL records)     │  read-only   │
 └──────────────┘                     └──────────────┘
```

PostgreSQL **streaming replication** sends every change, as **Write-Ahead Log (WAL)** records, from the primary to the replica as it happens. These are the same WAL records that gave durability in Portfolio 3. The replica replays them and so stays an up-to-date copy.

**How the replica was created** (`docker-compose.yml`): `pg_basebackup` copies the whole primary once. The `-R` option then configures the copy as a **standby** that keeps receiving changes.

Output: [`results/replication_demo.txt`](results/replication_demo.txt)

### Demo 1: replication status
The data was loaded into the **primary only**, yet the replica also had all **2,000 taxpayers** within seconds. The primary reports its replica like this:

```
 client_addr |   state   | sync_state | replay_lag
 172.20.0.3  | streaming | async      |
```

- `state = streaming`: the replica is connected and receiving changes.
- `sync_state = async`: **asynchronous** replication (explained below).
- `replay_lag` is blank because nothing was waiting to be copied at that moment. Demo 2 measures it right after a change.
- `pg_is_in_recovery()` returns `f` on the primary and `t` on the replica. That is how you tell them apart.

### Demo 2: write on the primary, read on the replica
A new taxpayer (TIN 2000000002) was registered on the **primary**. One second later, the **replica** already returned the record. The measured **replication lag** was about **1 millisecond** (`replay_lag = 00:00:00.001`).

### Demo 3: the replica is read-only
```
[REPLICA] UPDATE nrs.taxpayer SET status = 'CLOSED' ...
ERROR:  cannot execute UPDATE in a read-only transaction
```
Only the primary accepts changes. This avoids two servers changing the same row in different ways. The replica is still useful: heavy **reports** and the **taxpayer portal** can read from it, which takes load off the primary.

### Demo 4: failover
| Step | What happened |
|---|---|
| 1 | The primary was **killed**, simulating a crash |
| 2 | The replica **still answered reads**: 2,001 taxpayers |
| 3 | Writes were refused, because there was no primary any more |
| 4 | `SELECT pg_promote();` was run on the replica, which **promoted** it |
| 5 | `pg_is_in_recovery()` changed to `f`: it is now the primary |
| 6 | Writes worked again, and the demo taxpayer was updated |

The new taxpayer registered in Demo 2 was still there after failover, so **no committed data was lost**. In this demo the promotion was done by hand. Production systems use tools such as Patroni, or a cloud provider's managed service, to detect the failure and promote a replica automatically within seconds.

> **Split brain:** if the old primary came back and also accepted writes, there would be **two** primaries with different data. Failover tools prevent this by "fencing" the old primary so it can only rejoin as a replica.

### Synchronous vs asynchronous replication

| | Asynchronous (used here, PostgreSQL default) | Synchronous |
|---|---|---|
| When does `COMMIT` return? | As soon as the **primary** has saved the change | Only when the **replica** has confirmed it too |
| Speed | Faster | Slower: every commit waits for the network |
| Risk | If the primary dies, the last few milliseconds of commits may not have reached the replica | **No data loss** on failover |
| Good for | Most workloads, reporting replicas | Money: payments and refunds |

For the NRS, **synchronous** replication would suit at least one replica, because losing a recorded tax payment is not acceptable. It is enabled with the `synchronous_standby_names` setting.

### Link to the CAP theorem (Portfolio 4)
Imagine the network between the primary and the replica breaks (a **P**artition):
- The **replica keeps answering reads** (**A**vailability), but the answers may be slightly out of date.
- **Writes only happen on one server**, so the data never splits into two different versions (**C**onsistency of writes).

With synchronous replication, the primary would **stop accepting commits** rather than risk losing data. That choice picks **consistency over availability**.

---

## 3. Fragmentation (partitioning)

Output: [`results/partitioning_demo.txt`](results/partitioning_demo.txt)

**Horizontal fragmentation** splits a table by **rows**. The demo splits the `payment` table into one piece per **year**:

```sql
CREATE TABLE payment_by_year (LIKE payment) PARTITION BY RANGE (payment_date);
CREATE TABLE payment_y2024 PARTITION OF payment_by_year FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE payment_y2025 PARTITION OF payment_by_year FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
CREATE TABLE payment_y2026 PARTITION OF payment_by_year FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
```

| Partition (fragment) | Payments |
|---|---:|
| payment_y2024 | 1,991 |
| payment_y2025 | 8,489 |
| payment_y2026 | 9,306 |

**Partition pruning.** A query for 2025 revenue reads **only** the 2025 piece:

```
 Aggregate
   ->  Seq Scan on payment_y2025 payment_by_year
```

The total was **₦86,839,691,563.38**, identical to the same query on the normal table. Users still query one table and do not need to know it is split. This property is called **fragmentation transparency**.

### From partitions to a distributed database
In this demo all the pieces sit on one server. In a distributed database each piece can live on a **different server**, which is called **sharding**. For the NRS, a natural design is to fragment **by geopolitical zone**:

```
 South West shard (Lagos)    North Central shard (Abuja)    ... one per zone
   taxpayers in SW states      taxpayers in NC states
```

Each zone's data sits on a server near that zone. Most work happens on one shard, but a national report must **combine** results from all of them. Extensions such as **Citus** add this to PostgreSQL. MongoDB (Portfolio 4) has sharding built in.

| Type | Splits by | NRS example |
|---|---|---|
| **Horizontal** | Rows | Payments per year (demo), or taxpayers per zone |
| **Vertical** | Columns | Contact details (email, phone) kept apart from tax data, with stricter access |
| **Hybrid** | Both | Zone shards, each with sensitive columns separated |

---

## 4. Cloud deployment for the NRS

The same design can run in the cloud as a **managed database service** (**DBaaS**: Database-as-a-Service), such as Amazon RDS / Aurora for PostgreSQL, Azure Database for PostgreSQL or Google Cloud SQL. The provider runs the servers. The NRS chooses the size and the settings.

### What the cloud provider handles
| Task | On our own servers (like this portfolio) | Managed cloud database |
|---|---|---|
| Creating replicas | Write scripts (`pg_basebackup`, `primary-init.sh`) | A few clicks or one setting |
| Failover | Manual `pg_promote()` | Automatic, usually within a minute or two |
| Backups | Do it yourself | Automatic daily backups + point-in-time recovery |
| Software updates and patching | Do it yourself | Done by the provider |
| Scaling | Buy a bigger server | Change the instance size; add read replicas |

### A suggested NRS cloud design
```
                     ┌───────────── Cloud region (in or near Nigeria) ─────────────┐
 Taxpayer portal ───►│  Zone A: PRIMARY  ◄── synchronous ──►  Zone B: STANDBY      │
 Officers' system    │      │                                  (automatic failover)│
                     │      └── asynchronous ──► READ REPLICA (reports, portal)     │
                     └──────────────────────────────────────────────────────────────┘
                                 │ backups copied to a second region (disaster recovery)
```

1. **Primary + synchronous standby** in two separate data centres (availability zones) of one region. No payment is lost if a data centre fails.
2. **Asynchronous read replica** for reports and the self-service portal.
3. **Automatic backups**, copied to a second region in case of a disaster affecting a whole region.

### Things the NRS must consider
| Concern | Why it matters | What to do |
|---|---|---|
| **Data protection law** | Taxpayer data is personal data under the **Nigeria Data Protection Act 2023** | Choose where data is stored carefully (data residency); encrypt it; control access |
| **Security** | Tax data is a target for attackers | Encryption at rest and in transit (TLS), private networks, strong authentication, audit logs |
| **Cost** | Cloud is pay-as-you-go | Use read replicas and the right instance sizes; archive old years (partitions make this easy) |
| **Vendor lock-in** | Hard to move away from one provider | Plain PostgreSQL runs on every major cloud and on-premises |
| **Connectivity** | Offices across 36 states need reliable access | Choose a region with low latency to Nigeria; keep offline/retry handling in applications |

---

## 5. Summary

| Concept | Shown by | Result |
|---|---|---|
| Replication | Load into the primary only, read from the replica | All 2,000 taxpayers copied automatically |
| Replication lag | `pg_stat_replication.replay_lag` | About 1 ms (asynchronous) |
| Read-only replica | `UPDATE` on the replica | Refused; reads still work |
| Failover / high availability | Kill the primary, `pg_promote()` | Replica became the primary, with no committed data lost |
| Horizontal fragmentation | Payments partitioned by year | Partition pruning: only the needed piece is read; same answer |
| Cloud | Managed PostgreSQL design | Automatic failover, backups and scaling, with data-protection duties |

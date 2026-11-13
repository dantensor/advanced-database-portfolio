// =====================================================================
// MIT 8103 Portfolio 4: MongoDB queries on the NRS taxpayer documents
//
// Run (after 02_load_mongo.sh), from the main project folder:
//   docker exec -i nrs_mongo sh -c 'cat > /tmp/q.js && mongosh nrs --quiet /tmp/q.js' < portfolio-4-nosql/03_queries.js
//
// Each query has a SQL equivalent in the README so the two can be compared.
// Any data changed here is put back at the end.
// =====================================================================

function title(t) { print("\n=== " + t + " ==="); }

// ---------------------------------------------------------------------
title("Q1. Get a taxpayer's full profile by TIN");
// In SQL this needs joins across about 9 tables. Here it is ONE document read.
// ---------------------------------------------------------------------
db.taxpayers.dropIndexes();   // start without our index

let plan = db.taxpayers.find({ tin: "1000004271" }).explain("executionStats");
print("Without an index:", plan.queryPlanner.winningPlan.stage,
      "- documents examined:", plan.executionStats.totalDocsExamined);

db.taxpayers.createIndex({ tin: 1 }, { unique: true });

plan = db.taxpayers.find({ tin: "1000004271" }).explain("executionStats");
print("With an index:   ", plan.queryPlanner.winningPlan.inputStage.stage,
      "- documents examined:", plan.executionStats.totalDocsExamined);

const tp = db.taxpayers.findOne({ tin: "1000004271" });
print("Found:", tp.name, "|", tp.type, "|", tp.office.name,
      "|", tp.returns.length, "returns, all in the same document");

// ---------------------------------------------------------------------
title("Q2. Flexible schema: individuals and companies in one collection");
// Individuals have a 'person' section, companies a 'company' section.
// No empty (NULL) columns, no separate subtype tables.
// ---------------------------------------------------------------------
print("Individuals:", db.taxpayers.countDocuments({ type: "INDIVIDUAL" }),
      "| Companies:", db.taxpayers.countDocuments({ type: "COMPANY" }));
print("Health-sector companies registered in Lagos (dot notation into nested fields):");
db.taxpayers.find(
  { "company.sector": "Health", "office.state": "Lagos" },
  { _id: 0, tin: 1, name: 1, "office.code": 1 }
).sort({ name: 1 }).limit(5).forEach(d => printjson(d));

// ---------------------------------------------------------------------
title("Q3. Revenue collected in 2025 by state (aggregation pipeline)");
// $unwind opens up the nested arrays (like a JOIN), $group sums them.
// The answer matches Portfolio 1 SQL report 7a.
// ---------------------------------------------------------------------
db.taxpayers.aggregate([
  { $unwind: "$returns" },
  { $unwind: "$returns.assessments" },
  { $unwind: "$returns.assessments.payments" },
  { $match: { "returns.assessments.payments.date": {
        $gte: ISODate("2025-01-01"), $lt: ISODate("2026-01-01") } } },
  { $group: { _id: "$office.state",
              paying_taxpayers: { $addToSet: "$_id" },
              revenue: { $sum: "$returns.assessments.payments.amount" } } },
  { $project: { _id: 0, state: "$_id",
                paying_taxpayers: { $size: "$paying_taxpayers" },
                revenue: { $round: ["$revenue", 2] } } },
  { $sort: { revenue: -1 } },
  { $limit: 5 }
]).forEach(d => printjson(d));

// ---------------------------------------------------------------------
title("Q4. Taxpayers with the most LATE returns");
// $expr lets us compare two fields of the same document.
// ---------------------------------------------------------------------
db.taxpayers.aggregate([
  { $unwind: "$returns" },
  { $match: { $expr: { $gt: ["$returns.filed_on", "$returns.due_date"] } } },
  { $group: { _id: { tin: "$tin", name: "$name" }, late_returns: { $sum: 1 } } },
  { $sort: { late_returns: -1, "_id.tin": 1 } },
  { $limit: 5 },
  { $project: { _id: 0, tin: "$_id.tin", name: "$_id.name", late_returns: 1 } }
]).forEach(d => printjson(d));

// ---------------------------------------------------------------------
title("Q5. Record a new payment INSIDE the nested document");
// arrayFilters picks the right return; $push adds to its payments list.
// ---------------------------------------------------------------------
const before = db.taxpayers.findOne({ tin: "1000004271" }).returns[0].assessments[0].payments.length;
let res = db.taxpayers.updateOne(
  { tin: "1000004271" },
  { $push: { "returns.$[r].assessments.$[a].payments":
      { ref: "DEMO-MONGO-001", amount: 50000, date: ISODate("2026-11-13"), method: "REMITA" } } },
  { arrayFilters: [ { "r.return_id": 1 }, { "a.type": "ORIGINAL" } ] }
);
const after = db.taxpayers.findOne({ tin: "1000004271" }).returns[0].assessments[0].payments.length;
print("Documents modified:", res.modifiedCount, "| payments on return 1:", before, "->", after);
// undo the demo
db.taxpayers.updateOne(
  { tin: "1000004271" },
  { $pull: { "returns.$[r].assessments.$[a].payments": { ref: "DEMO-MONGO-001" } } },
  { arrayFilters: [ { "r.return_id": 1 }, { "a.type": "ORIGINAL" } ] }
);

// ---------------------------------------------------------------------
title("Q6. The cost of copying data: rename one tax office");
// In SQL: UPDATE tax_office ... changes ONE row.
// Here the office name is copied into every taxpayer of that office,
// so EVERY one of those documents must be changed.
// ---------------------------------------------------------------------
res = db.taxpayers.updateMany(
  { "office.code": "LG-IKJ" },
  { $set: { "office.name": "NRS Ikeja Main Tax Office" } }
);
print("SQL rows to update: 1 | MongoDB documents updated:", res.modifiedCount);
// undo the demo
db.taxpayers.updateMany(
  { "office.code": "LG-IKJ" },
  { $set: { "office.name": "NRS Ikeja Tax Office" } }
);

print("\nDone.");

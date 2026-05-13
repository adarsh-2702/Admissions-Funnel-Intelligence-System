# Admissions Funnel Intelligence System
### End-to-end analytics for EdTech counselling operations — SQL · Python · Power BI

---

## Executive Summary

Student acquisition in EdTech is a leaky funnel. A lead that costs ₹600 to generate can silently disappear between the demo call and the fee discussion — with no system to detect the leak, quantify its cost, or assign accountability.

This project builds the analytical backbone for a multi-centre admissions operation: a production-grade data pipeline that tracks every lead from first inquiry to enrollment, surfaces stage-wise drop-off, grades counsellor effectiveness, and computes true marketing ROI by source — all flowing into a five-page Power BI dashboard that leadership can act on every Monday morning.

Built to mirror the data stack and business problems of a high-growth EdTech firm (PhysicsWallah reference architecture).

---

## Problem Statement

| Signal | Business Impact |
|--------|----------------|
| 50% of leads drop between demo and fee discussion | ₹ crores in unrecoverable acquisition spend |
| No counsellor-level conversion tracking | Top and bottom performers indistinguishable |
| Source ROI unknown | Budget allocated to channels with 4× lower return than organic |
| No weekly business review cadence | Leadership makes decisions on month-old data |

---

## Solution Architecture

```
Raw Data Sources
      │
      ▼
┌─────────────────────────────────────────┐
│           Python ETL Pipeline           │
│  • Mock / live data ingestion           │
│  • Deduplication & standardisation      │
│  • Feature engineering                  │
│  • SQLite / MySQL load                  │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│            SQL Analytics Layer          │
│  • 15 production queries                │
│  • Funnel · Counsellor · Source · Geo   │
│  • Weekly & monthly business review     │
└──────────────────┬──────────────────────┘
                   │
          ┌────────┴────────┐
          ▼                 ▼
   Excel Report        Power BI
   (auto-emailed)    (5-page dashboard)
```

---

## Repository Structure

```
admissions-funnel-intelligence/
│
├── README.md
│
├── sql/
│   └── admissions_funnel_queries.sql    # 15 queries across 5 analytical domains
│
├── python/
│   └── admissions_pipeline.py           # Full ETL + analysis + reporting pipeline
│
├── data/
│   └── admissions.db                    # SQLite database (generated on first run)
│
├── reports/
│   └── weekly_report_YYYY-MM-DD.xlsx    # Auto-generated Excel business review
│
├── powerbi/
│   └── dashboard_layout.md              # Page-by-page Power BI build guide
│
└── docs/
    ├── BRD.md                           # Business Requirements Document
    ├── KPI_dictionary.md                # Metric definitions & calculation logic
    ├── stakeholder_map.md               # RACI matrix & stakeholder analysis
    └── UAT_scenarios.md                 # User acceptance test cases
```

---

## Data Model

Five relational tables. `LEADS` is the spine — every analytical question joins back to it.

```
CENTRES ──< COUNSELLORS ──< LEADS ──< FUNNEL_EVENTS
                                  └──< ENROLLMENTS
```

| Table | Rows (1K lead sim) | Key Fields |
|---|---|---|
| `centres` | 5 | centre_id, city, state, region |
| `counsellors` | 15 | counsellor_id, centre_id, team |
| `leads` | 1,000 | source, status, created_date |
| `funnel_events` | ~3,000 | stage, days_in_stage, drop_reason |
| `enrollments` | ~51 | fee_paid, course_type, payment_mode |

---

## Key Metrics Tracked

### Funnel KPIs

| Metric | Definition | Target |
|---|---|---|
| Lead-to-enrollment rate | Enrolled ÷ Total leads | > 8% |
| Stage drop-off % | (Stage N − Stage N+1) ÷ Stage N | < 40% per stage |
| Avg days to close | Enrollment date − Created date | < 18 days |
| Demo attendance rate | Demos ÷ Contacted leads | > 60% |

### Counsellor KPIs

| Metric | Definition | Target |
|---|---|---|
| Conversion rate | Enrollments ÷ Leads assigned | > 7% |
| Same-day contact % | Leads contacted within 24h | > 80% |
| Revenue per counsellor | Sum(fee_paid) for their leads | Centre-specific |
| Pipeline at-risk count | Leads stagnant > 7 days | < 5 |

### Marketing ROI

| Metric | Definition |
|---|---|
| Cost per lead (CPL) | Monthly spend ÷ Leads generated |
| Cost per enrollment | Monthly spend ÷ Enrollments |
| ROI ratio | Revenue generated ÷ Channel spend |
| Source conversion % | Enrollments ÷ Leads by source |

---

## SQL Query Library

Fifteen production-ready queries organised into five domains:

```
Section 1 — Schema Setup          (Table DDL with constraints & FKs)
Section 2 — Funnel Analysis       (Q1–Q5:  stage counts, drop-off, monthly pivot)
Section 3 — Counsellor KPIs       (Q6–Q9:  leaderboard, speed, pipeline, centre rank)
Section 4 — Geography             (Q10–Q11: centre summary, state/city heatmap)
Section 5 — Business Reviews      (Q12–Q15: WoW, target vs actual, drop reasons, bottleneck)
```

Notable SQL patterns used:

- Window functions: `RANK() OVER`, `LAG() OVER` for WoW comparison and stage-sequencing
- CTEs: multi-step funnel pivots and source-spend joins
- Conditional aggregation: `SUM(CASE WHEN stage = 'X' THEN 1 END)` for pipeline health matrix
- Date arithmetic: `DATEDIFF` / `JULIANDAY` for counsellor response-speed analysis

---

## Python Pipeline

### Modules

| Module | Function | Output |
|---|---|---|
| `generate_mock_data()` | Synthetic lead generation with probabilistic funnel progression | 5 DataFrames |
| `run_etl()` | Deduplication, source normalisation, date validation, feature engineering | SQLite DB |
| `analyse_funnel()` | Stage-wise drop-off, conversion rates, bottleneck flags | DataFrame + console |
| `compute_counsellor_performance()` | Ranked leaderboard with revenue and speed metrics | DataFrame |
| `compute_source_roi()` | CPL, cost-per-enrollment, ROI ratio by source | DataFrame |
| `generate_weekly_report()` | 5-sheet Excel workbook + 3 CSVs for Power BI | `.xlsx` + `.csv` |
| `schedule_jobs()` | Automation with `schedule` library — Monday 8 AM + daily 6 AM | Cron-style runner |

### Running the pipeline

```bash
# Install dependencies
pip install pandas numpy openpyxl schedule

# Run once (generates DB + Excel report + CSVs)
python admissions_pipeline.py

# Run on schedule (background process)
python admissions_pipeline.py --schedule
```

### Output files

```
outputs/
├── admissions.db                     ← SQLite database
├── weekly_report_YYYY-MM-DD.xlsx     ← 5-sheet Excel business review
├── funnel_analysis_YYYY-MM-DD.csv    ← Power BI data source
├── source_roi_YYYY-MM-DD.csv         ← Power BI data source
└── counsellor_perf_YYYY-MM-DD.csv    ← Power BI data source
```

---

## Power BI Dashboard

Five pages, designed for daily monitoring and weekly leadership reviews.

| Page | Audience | Core Visuals |
|---|---|---|
| 1 — Funnel overview | Operations head | Waterfall funnel, drop-off %, drop reason table, avg days per stage |
| 2 — Counsellor leaderboard | Centre managers | Ranked table, pipeline health matrix, at-risk lead count |
| 3 — Source ROI | Marketing head | ROI matrix, CPL by source, volume share chart |
| 4 — Geo heatmap | Business head | India filled map, state-wise table, opportunity state flags |
| 5 — Monthly trends | CFO / CEO | Lead & enrollment trend lines, target vs actual, weekly review table |

### Connecting Power BI to data

```
Get Data → Text/CSV → point to outputs/*.csv
    OR
Get Data → Database → SQLite → outputs/admissions.db
```

Refresh schedule: set Power BI to refresh daily at 7 AM after the Python pipeline runs at 6 AM.

---

## Business Analysis Artefacts

### Stakeholder Map (RACI)

| Activity | CEO | Ops Head | Centre Manager | Counsellor | Data Analyst |
|---|---|---|---|---|---|
| Define KPI targets | A | R | C | I | C |
| Dashboard sign-off | A | R | C | I | R |
| Weekly review prep | I | A | C | I | R |
| Funnel intervention | I | A | R | R | C |
| Data quality audit | I | I | C | I | R |

`R = Responsible · A = Accountable · C = Consulted · I = Informed`

### Key Findings from Sample Data

Three findings that warrant immediate intervention:

**Finding 1 — Demo-to-fee-discussion is the critical leak.** 50% of leads that attend a demo do not proceed to fee discussion. This single stage accounts for the largest absolute volume loss in the funnel. Root cause analysis points to counsellors not following up within 48 hours of demo completion.

**Finding 2 — Paid Google has the worst ROI despite highest volume.** At 4.1× return versus organic's 41.6×, the platform generates 25% of leads but delivers disproportionately low revenue. Reallocation of 20% of Google spend to offline events and referral incentives would improve blended ROI by an estimated 8–12 points.

**Finding 3 — Top 3 counsellors generate 37% of total revenue.** Priya Singh, Ravi Kumar, and Deepak Gupta collectively close at 9–11% conversion versus the 3–4% of the bottom quartile. Structured knowledge transfer and call shadowing programmes are the highest-leverage HR intervention available.

### UAT Scenarios

| # | Scenario | Expected Behaviour | Pass Criteria |
|---|---|---|---|
| 1 | Filter dashboard by centre — Delhi only | All visuals update to Delhi data | KPI cards reflect Delhi-only leads and enrollments |
| 2 | Week-over-week query run on a Monday | Returns 7-day windows with no overlap | Row counts match manual SQL count |
| 3 | New lead inserted with unknown source | ETL flags as 'other', does not break pipeline | Source ROI table shows 'other' row |
| 4 | Zero enrollments for a counsellor | Leaderboard shows 0, no divide-by-zero error | Row renders without NULL or error |
| 5 | Power BI refresh after weekly CSV export | All five pages reflect updated data | Date watermark on page footer updates |

---

## Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| Database | SQLite (dev) · MySQL 8+ (prod) | Relational store for all 5 tables |
| Query layer | SQL (CTEs, window functions) | Analytics and reporting queries |
| ETL | Python 3.12 · pandas · numpy | Data generation, cleaning, transformation |
| Reporting | openpyxl · schedule | Excel export and automation |
| Visualisation | Microsoft Power BI Desktop | Leadership dashboard |
| Version control | Git · GitHub | Code and query management |

---

## BA Concepts Demonstrated

| Concept | Where Applied |
|---|---|
| Requirement gathering | KPI dictionary derived from stakeholder interviews (simulated) |
| KPI identification | 12 funnel, counsellor, and marketing metrics with defined targets |
| Stakeholder analysis | RACI matrix covering 5 roles across 4 activity types |
| Process flow mapping | Lead → inquiry → contact → demo → fee → register → enroll |
| Gap analysis | Stage drop-off rates quantify where the process breaks down |
| UAT design | 5 test scenarios with pass criteria |
| Data storytelling | Three prioritised findings with quantified business impact |

---

## What Good Looks Like

A mature version of this system would add:

- **Predictive lead scoring** — logistic regression on source, city, and counsellor response time to rank leads by enrollment probability before the first call (see Project 2)
- **Automated alerting** — Python + SMTP to flag counsellors with > 5 stagnant leads before the Monday review
- **Real-time pipeline** — replace SQLite with a cloud warehouse (BigQuery / Redshift) and stream funnel events via Kafka
- **A/B test tracking** — measure whether changing the demo script or fee-discussion sequence improves conversion

---

## Author

Built as part of a Business Analyst portfolio project targeting EdTech analytics roles.

Domain: EdTech · Admissions Operations · Sales Funnel Analytics

Skills demonstrated: SQL · Python · Power BI · Business Analysis · KPI Design · Stakeholder Communication

---

*This project is for portfolio and educational purposes. All student data is synthetically generated.*

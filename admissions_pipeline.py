"""
admissions_pipeline.py
======================
End-to-End Admissions Funnel Intelligence System
PhysicsWallah-Style EdTech Project

Modules:
  1. Mock data generator   — creates realistic synthetic data
  2. ETL & preprocessing   — cleans and loads to SQLite
  3. Funnel drop-off analysis — stage-wise analysis
  4. Counsellor performance   — leaderboard computation
  5. Source ROI analysis      — marketing effectiveness
  6. Weekly report generator  — exports Excel + summary CSV
  7. Scheduler stub           — shows how to automate with schedule

Dependencies:
  pip install pandas numpy faker sqlalchemy openpyxl schedule
"""

import pandas as pd
import numpy as np
import sqlite3
import os
from datetime import datetime, timedelta
from pathlib import Path

# ── reproducibility ──────────────────────────────────────────
np.random.seed(42)
OUTPUT_DIR = Path("outputs")
OUTPUT_DIR.mkdir(exist_ok=True)
DB_PATH    = OUTPUT_DIR / "admissions.db"


# ============================================================
# MODULE 1: MOCK DATA GENERATOR
# ============================================================

def generate_mock_data(n_leads: int = 1000) -> dict[str, pd.DataFrame]:
    """Generate realistic EdTech admissions mock data."""

    # ── reference data ────────────────────────────────────────
    centres_data = {
        "centre_id":   [1, 2, 3, 4, 5],
        "centre_name": ["Delhi Pitampura", "Mumbai Andheri", "Patna Kankarbagh",
                        "Jaipur Gopalpura", "Lucknow Hazratganj"],
        "city":        ["Delhi", "Mumbai", "Patna", "Jaipur", "Lucknow"],
        "state":       ["Delhi", "Maharashtra", "Bihar", "Rajasthan", "Uttar Pradesh"],
        "region":      ["North", "West", "East", "North", "North"],
    }

    counsellor_names = [
        "Ravi Kumar", "Priya Singh", "Aakash Mehta", "Neha Sharma", "Rohit Yadav",
        "Sunita Patel", "Amit Verma", "Kavya Joshi", "Deepak Gupta", "Pooja Tiwari",
        "Manish Srivastava", "Anjali Rao", "Vikram Chauhan", "Shruti Agarwal", "Nikhil Das",
    ]
    counsellors_data = {
        "counsellor_id":   list(range(1, 16)),
        "counsellor_name": counsellor_names,
        "centre_id":       [1,1,1,2,2,2,3,3,4,4,4,5,5,5,5],
        "team":            (["JEE Team","NEET Team","Foundation"] * 5)[:15],
        "joining_date":    pd.date_range("2022-01-01", periods=15, freq="45D").strftime("%Y-%m-%d").tolist(),
    }

    sources      = ["organic","paid_google","paid_meta","referral","walk_in","offline_event"]
    source_probs = [0.20, 0.25, 0.20, 0.15, 0.12, 0.08]
    courses      = ["JEE Mains","JEE Advanced","NEET","Foundation 10th","Repeater Batch"]
    drop_reasons = [
        "Fee too high","Joined competitor","Not interested anymore",
        "Moved city","No response","Scholarship denied","Family decision",
    ]
    stages       = ["inquiry","contacted","demo_attended","fee_discussed","registered","enrolled"]

    # conversion probability per stage (realistic drop-off)
    stage_conv = {
        "inquiry"      : 1.00,
        "contacted"    : 0.72,
        "demo_attended": 0.50,
        "fee_discussed": 0.35,
        "registered"   : 0.22,
        "enrolled"     : 0.16,
    }

    # ── leads ─────────────────────────────────────────────────
    base_date = datetime.today() - timedelta(days=180)
    lead_dates_raw = [base_date + timedelta(days=int(x)) for x in np.random.exponential(0.5, n_leads * 2).cumsum()]
    lead_dates = [d for d in lead_dates_raw if d <= datetime.today()][:n_leads]
    # ensure we always have exactly n_leads entries
    while len(lead_dates) < n_leads:
        lead_dates.append(datetime.today() - timedelta(days=np.random.randint(1, 10)))

    rng_centre    = np.random.choice(centres_data["centre_id"], size=n_leads)
    rng_counsel   = [np.random.choice(
                        [c for c,cid in zip(counsellors_data["counsellor_id"],
                                            counsellors_data["centre_id"]) if cid == ct]
                     ) for ct in rng_centre]
    rng_source    = np.random.choice(sources, size=n_leads, p=source_probs)

    leads = pd.DataFrame({
        "lead_id"      : range(1, n_leads + 1),
        "name"         : [f"Student_{i}" for i in range(1, n_leads + 1)],
        "phone"        : [f"9{np.random.randint(100000000,999999999)}" for _ in range(n_leads)],
        "email"        : [f"student{i}@example.com" for i in range(1, n_leads + 1)],
        "city"         : [centres_data["city"][ct-1] for ct in rng_centre],
        "state"        : [centres_data["state"][ct-1] for ct in rng_centre],
        "source"       : rng_source,
        "centre_id"    : rng_centre,
        "counsellor_id": rng_counsel,
        "created_date" : [d.strftime("%Y-%m-%d") for d in lead_dates],
    })

    # ── funnel events ─────────────────────────────────────────
    events_rows = []
    enrollment_rows = []
    lead_statuses = []

    for _, lead in leads.iterrows():
        lead_date = datetime.strptime(lead["created_date"], "%Y-%m-%d")
        current_date = lead_date
        reached_stage = "inquiry"
        events_rows.append({
            "lead_id"     : lead["lead_id"],
            "stage"       : "inquiry",
            "event_date"  : current_date.strftime("%Y-%m-%d"),
            "days_in_stage": 0,
            "drop_reason" : None,
        })

        for i, stage in enumerate(stages[1:], start=1):
            # does this lead proceed to next stage?
            if np.random.random() > stage_conv[stage] / stage_conv[stages[i-1]]:
                # dropped
                events_rows.append({
                    "lead_id"     : lead["lead_id"],
                    "stage"       : "dropped",
                    "event_date"  : (current_date + timedelta(days=np.random.randint(1,10))).strftime("%Y-%m-%d"),
                    "days_in_stage": None,
                    "drop_reason" : np.random.choice(drop_reasons),
                })
                break

            days_spent = max(1, int(np.random.normal(
                [0,2,4,3,5,7][i], [0,1,2,2,3,4][i]
            )))
            current_date += timedelta(days=days_spent)
            if current_date > datetime.today():
                break
            events_rows.append({
                "lead_id"     : lead["lead_id"],
                "stage"       : stage,
                "event_date"  : current_date.strftime("%Y-%m-%d"),
                "days_in_stage": days_spent,
                "drop_reason" : None,
            })
            reached_stage = stage

        lead_statuses.append(reached_stage)

        if reached_stage == "enrolled":
            enrollment_rows.append({
                "lead_id"        : lead["lead_id"],
                "counsellor_id"  : lead["counsellor_id"],
                "course_name"    : np.random.choice(courses),
                "course_type"    : np.random.choice(["JEE","NEET","Foundation","Repeater"]),
                "fee_paid"       : round(np.random.choice([35000,50000,70000,90000,120000]) *
                                         np.random.uniform(0.8, 1.0), -2),
                "enrollment_date": current_date.strftime("%Y-%m-%d"),
                "payment_mode"   : np.random.choice(["full","emi","scholarship"],p=[0.4,0.45,0.15]),
            })

    leads["status"] = lead_statuses
    funnel_events  = pd.DataFrame(events_rows).reset_index(drop=True)
    funnel_events.insert(0, "event_id", range(1, len(funnel_events)+1))
    enrollments    = pd.DataFrame(enrollment_rows).reset_index(drop=True)
    enrollments.insert(0, "enrollment_id", range(1, len(enrollments)+1))

    centres    = pd.DataFrame(centres_data)
    counsellors = pd.DataFrame(counsellors_data)

    print(f"[DATA GEN] Leads: {len(leads)} | Events: {len(funnel_events)} | Enrollments: {len(enrollments)}")
    return {
        "centres"      : centres,
        "counsellors"  : counsellors,
        "leads"        : leads,
        "funnel_events": funnel_events,
        "enrollments"  : enrollments,
    }


# ============================================================
# MODULE 2: ETL & PREPROCESSING
# ============================================================

def run_etl(data: dict[str, pd.DataFrame]) -> sqlite3.Connection:
    """Clean data and load into SQLite database."""

    print("\n[ETL] Starting preprocessing...")

    leads = data["leads"].copy()

    # 1. Deduplicate on phone number (keep latest)
    before = len(leads)
    leads = leads.sort_values("created_date").drop_duplicates(subset="phone", keep="last")
    print(f"  Deduplication: removed {before - len(leads)} duplicate phone records")

    # 2. Standardise source names
    source_map = {"google":"paid_google","meta":"paid_meta","facebook":"paid_meta",
                  "instagram":"paid_meta","seo":"organic"}
    leads["source"] = leads["source"].str.lower().replace(source_map)

    # 3. Fill missing counsellor assignments (edge case)
    missing_mask = leads["counsellor_id"].isna()
    if missing_mask.any():
        leads.loc[missing_mask, "counsellor_id"] = 1
        print(f"  Filled {missing_mask.sum()} missing counsellor_id values with default")

    # 4. Date validation
    leads["created_date"] = pd.to_datetime(leads["created_date"], errors="coerce")
    invalid_dates = leads["created_date"].isna().sum()
    if invalid_dates:
        print(f"  Warning: {invalid_dates} invalid dates dropped")
        leads = leads.dropna(subset=["created_date"])
    leads["created_date"] = leads["created_date"].dt.strftime("%Y-%m-%d")

    # 5. Feature engineering
    leads["month"]       = pd.to_datetime(leads["created_date"]).dt.to_period("M").astype(str)
    leads["week_number"] = pd.to_datetime(leads["created_date"]).dt.isocalendar().week.astype(int)

    data["leads"] = leads

    # Load to SQLite
    conn = sqlite3.connect(DB_PATH)
    for table_name, df in data.items():
        df.to_sql(table_name, conn, if_exists="replace", index=False)
        print(f"  Loaded table '{table_name}' → {len(df)} rows")

    conn.commit()
    print(f"[ETL] Database saved to {DB_PATH}")
    return conn


# ============================================================
# MODULE 3: FUNNEL DROP-OFF ANALYSIS
# ============================================================

def analyse_funnel(conn: sqlite3.Connection) -> pd.DataFrame:
    """Compute stage-wise funnel metrics."""

    print("\n[ANALYSIS] Running funnel drop-off analysis...")

    stage_order = ["inquiry","contacted","demo_attended","fee_discussed","registered","enrolled"]

    query = """
        SELECT stage, COUNT(DISTINCT lead_id) AS count
        FROM funnel_events
        WHERE stage != 'dropped'
        GROUP BY stage
    """
    df = pd.read_sql(query, conn)
    df["stage_order"] = df["stage"].map({s:i for i,s in enumerate(stage_order)})
    df = df.sort_values("stage_order").reset_index(drop=True)

    df["drop_off"]     = df["count"].shift(1) - df["count"]
    df["drop_off_pct"] = (df["drop_off"] / df["count"].shift(1) * 100).round(1)
    df["conversion_to_end"] = (df["count"] / df["count"].iloc[0] * 100).round(1)

    print(df[["stage","count","drop_off_pct","conversion_to_end"]].to_string(index=False))
    return df


# ============================================================
# MODULE 4: COUNSELLOR PERFORMANCE
# ============================================================

def compute_counsellor_performance(conn: sqlite3.Connection) -> pd.DataFrame:
    """Build counsellor leaderboard."""

    print("\n[ANALYSIS] Computing counsellor leaderboard...")

    query = """
        SELECT
            c.counsellor_name,
            ct.centre_name,
            COUNT(DISTINCT l.lead_id)                   AS leads_assigned,
            COUNT(DISTINCT e.enrollment_id)             AS enrollments,
            ROUND(SUM(e.fee_paid), 0)                   AS revenue,
            ROUND(AVG(JULIANDAY(e.enrollment_date) -
                      JULIANDAY(l.created_date)), 1)    AS avg_days_to_close
        FROM counsellors c
        JOIN centres ct ON c.centre_id = ct.centre_id
        JOIN leads l    ON c.counsellor_id = l.counsellor_id
        LEFT JOIN enrollments e ON l.lead_id = e.lead_id
        GROUP BY c.counsellor_id, c.counsellor_name, ct.centre_name
    """
    df = pd.read_sql(query, conn)
    df["conversion_pct"] = (df["enrollments"] / df["leads_assigned"] * 100).round(1)
    df = df.sort_values("conversion_pct", ascending=False).reset_index(drop=True)
    df.index += 1  # rank starts at 1
    df.index.name = "rank"

    print(df[["counsellor_name","centre_name","leads_assigned","enrollments",
              "conversion_pct","revenue"]].head(10).to_string())
    return df


# ============================================================
# MODULE 5: SOURCE ROI ANALYSIS
# ============================================================

def compute_source_roi(conn: sqlite3.Connection) -> pd.DataFrame:
    """Calculate marketing ROI per lead source."""

    monthly_spend = {
        "paid_google": 150000, "paid_meta": 120000, "organic": 20000,
        "referral"   : 30000,  "walk_in"  : 10000,  "offline_event": 60000,
    }

    query = """
        SELECT
            l.source,
            COUNT(DISTINCT l.lead_id)       AS leads,
            COUNT(DISTINCT e.enrollment_id) AS enrollments,
            ROUND(SUM(e.fee_paid), 0)       AS revenue
        FROM leads l
        LEFT JOIN enrollments e ON l.lead_id = e.lead_id
        GROUP BY l.source
    """
    df = pd.read_sql(query, conn)
    df["spend"]               = df["source"].map(monthly_spend).fillna(0)
    df["conversion_pct"]      = (df["enrollments"] / df["leads"] * 100).round(1)
    df["cost_per_lead"]       = (df["spend"] / df["leads"]).round(0)
    df["cost_per_enrollment"] = (df["spend"] / df["enrollments"].replace(0, np.nan)).round(0)
    df["roi_ratio"]           = (df["revenue"] / df["spend"].replace(0, np.nan)).round(2)
    df = df.sort_values("roi_ratio", ascending=False).reset_index(drop=True)

    print("\n[ANALYSIS] Source ROI:")
    print(df[["source","leads","enrollments","conversion_pct","cost_per_lead","roi_ratio"]].to_string(index=False))
    return df


# ============================================================
# MODULE 6: WEEKLY REPORT GENERATOR
# ============================================================

def generate_weekly_report(
    funnel_df: pd.DataFrame,
    counsellor_df: pd.DataFrame,
    source_df: pd.DataFrame,
    conn: sqlite3.Connection,
) -> str:
    """Export Excel weekly report + summary CSV."""

    today       = datetime.today().strftime("%Y-%m-%d")
    report_path = OUTPUT_DIR / f"weekly_report_{today}.xlsx"

    # Monthly trend from DB
    trend_df = pd.read_sql("""
        SELECT
            strftime('%Y-%m', l.created_date)   AS month,
            COUNT(DISTINCT l.lead_id)            AS new_leads,
            COUNT(DISTINCT e.enrollment_id)      AS enrollments,
            ROUND(SUM(e.fee_paid), 0)            AS revenue
        FROM leads l
        LEFT JOIN enrollments e ON l.lead_id = e.lead_id
        GROUP BY 1
        ORDER BY 1
    """, conn)

    with pd.ExcelWriter(report_path, engine="openpyxl") as writer:
        # Sheet 1: Funnel summary
        funnel_df.to_excel(writer, sheet_name="Funnel Summary", index=False)

        # Sheet 2: Counsellor leaderboard
        counsellor_df.reset_index().to_excel(writer, sheet_name="Counsellor Leaderboard", index=False)

        # Sheet 3: Source ROI
        source_df.to_excel(writer, sheet_name="Source ROI", index=False)

        # Sheet 4: Monthly trend
        trend_df.to_excel(writer, sheet_name="Monthly Trend", index=False)

        # Sheet 5: KPI summary card
        total_leads       = int(pd.read_sql("SELECT COUNT(*) AS n FROM leads", conn)["n"].iloc[0])
        total_enrollments = int(pd.read_sql("SELECT COUNT(*) AS n FROM enrollments", conn)["n"].iloc[0])
        total_revenue     = float(pd.read_sql("SELECT COALESCE(SUM(fee_paid),0) AS n FROM enrollments", conn)["n"].iloc[0])
        kpi_df = pd.DataFrame({
            "KPI"  : ["Total leads","Total enrollments","Overall conversion %","Total revenue (₹)"],
            "Value": [total_leads, total_enrollments,
                      round(total_enrollments / total_leads * 100, 1) if total_leads else 0,
                      f"₹{total_revenue:,.0f}"],
        })
        kpi_df.to_excel(writer, sheet_name="KPI Summary", index=False)

    # Also export a lightweight CSV for Power BI direct connection
    funnel_df.to_csv(OUTPUT_DIR / f"funnel_analysis_{today}.csv", index=False)
    source_df.to_csv(OUTPUT_DIR / f"source_roi_{today}.csv",    index=False)
    counsellor_df.reset_index().to_csv(OUTPUT_DIR / f"counsellor_perf_{today}.csv", index=False)

    print(f"\n[REPORT] Weekly Excel report → {report_path}")
    print(f"[REPORT] CSVs exported to {OUTPUT_DIR}/")
    return str(report_path)


# ============================================================
# MODULE 7: SCHEDULER STUB
# ============================================================

def schedule_jobs():
    """
    Automate the pipeline with the `schedule` library.
    Run this as a standalone process or inside a cron job.

    Example usage:
        python admissions_pipeline.py --schedule
    """
    import schedule
    import time

    def run_pipeline():
        print(f"\n{'='*50}")
        print(f"[SCHEDULER] Running pipeline at {datetime.now():%Y-%m-%d %H:%M}")
        data = generate_mock_data(1000)   # replace with DB pull in production
        conn = run_etl(data)
        fd   = analyse_funnel(conn)
        cd   = compute_counsellor_performance(conn)
        sd   = compute_source_roi(conn)
        generate_weekly_report(fd, cd, sd, conn)
        conn.close()
        print("[SCHEDULER] Done.")

    # Run every Monday at 8:00 AM
    schedule.every().monday.at("08:00").do(run_pipeline)
    # Also run a quick daily refresh at 6 AM
    schedule.every().day.at("06:00").do(run_pipeline)

    print("[SCHEDULER] Jobs scheduled. Waiting...")
    while True:
        schedule.run_pending()
        time.sleep(60)


# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":
    import sys

    if "--schedule" in sys.argv:
        schedule_jobs()
    else:
        # Run full pipeline once
        print("=" * 55)
        print("  ADMISSIONS FUNNEL INTELLIGENCE SYSTEM")
        print("  PhysicsWallah-Style EdTech Project")
        print("=" * 55)

        data         = generate_mock_data(n_leads=1000)
        conn         = run_etl(data)
        funnel_df    = analyse_funnel(conn)
        counsellor_df = compute_counsellor_performance(conn)
        source_df    = compute_source_roi(conn)
        report_path  = generate_weekly_report(funnel_df, counsellor_df, source_df, conn)
        conn.close()

        print("\n[DONE] All outputs written to ./outputs/")
        print("  - admissions.db          ← SQLite database")
        print("  - weekly_report_*.xlsx   ← Excel business review")
        print("  - funnel_analysis_*.csv  ← Power BI source")
        print("  - source_roi_*.csv       ← Power BI source")
        print("  - counsellor_perf_*.csv  ← Power BI source")

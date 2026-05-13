-- ============================================================
--  ADMISSIONS FUNNEL INTELLIGENCE SYSTEM
--  PhysicsWallah-Style EdTech SQL Query Library
--  Database: MySQL 8+ / PostgreSQL 14+
-- ============================================================

-- ============================================================
-- SECTION 1: SCHEMA SETUP
-- ============================================================

CREATE TABLE centres (
    centre_id     INT PRIMARY KEY AUTO_INCREMENT,
    centre_name   VARCHAR(100),
    city          VARCHAR(60),
    state         VARCHAR(60),
    region        VARCHAR(40)
);

CREATE TABLE counsellors (
    counsellor_id   INT PRIMARY KEY AUTO_INCREMENT,
    counsellor_name VARCHAR(100),
    centre_id       INT,
    team            VARCHAR(40),
    joining_date    DATE,
    FOREIGN KEY (centre_id) REFERENCES centres(centre_id)
);

CREATE TABLE leads (
    lead_id         INT PRIMARY KEY AUTO_INCREMENT,
    name            VARCHAR(100),
    phone           VARCHAR(15),
    email           VARCHAR(100),
    city            VARCHAR(60),
    state           VARCHAR(60),
    source          VARCHAR(40),   -- 'organic','paid_google','paid_meta','referral','walk_in','offline_event'
    centre_id       INT,
    counsellor_id   INT,
    created_date    DATE,
    status          VARCHAR(30),   -- 'new','contacted','qualified','registered','enrolled','dropped'
    FOREIGN KEY (centre_id)      REFERENCES centres(centre_id),
    FOREIGN KEY (counsellor_id)  REFERENCES counsellors(counsellor_id)
);

CREATE TABLE funnel_events (
    event_id        INT PRIMARY KEY AUTO_INCREMENT,
    lead_id         INT,
    stage           VARCHAR(30),   -- 'inquiry','contacted','demo_attended','fee_discussed','registered','enrolled','dropped'
    event_date      DATE,
    days_in_stage   INT,
    drop_reason     VARCHAR(100),  -- NULL unless dropped
    FOREIGN KEY (lead_id) REFERENCES leads(lead_id)
);

CREATE TABLE enrollments (
    enrollment_id   INT PRIMARY KEY AUTO_INCREMENT,
    lead_id         INT,
    counsellor_id   INT,
    course_name     VARCHAR(100),
    course_type     VARCHAR(40),   -- 'JEE','NEET','Foundation','Repeater'
    fee_paid        DECIMAL(10,2),
    enrollment_date DATE,
    payment_mode    VARCHAR(20),   -- 'full','emi','scholarship'
    FOREIGN KEY (lead_id)        REFERENCES leads(lead_id),
    FOREIGN KEY (counsellor_id)  REFERENCES counsellors(counsellor_id)
);


-- ============================================================
-- SECTION 2: FUNNEL ANALYSIS QUERIES
-- ============================================================

-- Q1: Overall funnel stage counts and conversion rates (month-wise)
-- Shows: how many leads pass through each stage each month
WITH stage_counts AS (
    SELECT
        DATE_FORMAT(event_date, '%Y-%m')    AS month,
        stage,
        COUNT(DISTINCT lead_id)             AS lead_count
    FROM funnel_events
    GROUP BY 1, 2
)
SELECT
    month,
    MAX(CASE WHEN stage = 'inquiry'       THEN lead_count END) AS inquiry,
    MAX(CASE WHEN stage = 'contacted'     THEN lead_count END) AS contacted,
    MAX(CASE WHEN stage = 'demo_attended' THEN lead_count END) AS demo_attended,
    MAX(CASE WHEN stage = 'fee_discussed' THEN lead_count END) AS fee_discussed,
    MAX(CASE WHEN stage = 'registered'    THEN lead_count END) AS registered,
    MAX(CASE WHEN stage = 'enrolled'      THEN lead_count END) AS enrolled,
    ROUND(
        MAX(CASE WHEN stage = 'enrolled' THEN lead_count END) * 100.0 /
        NULLIF(MAX(CASE WHEN stage = 'inquiry' THEN lead_count END), 0),
    2) AS overall_conversion_pct
FROM stage_counts
GROUP BY month
ORDER BY month;


-- Q2: Stage-wise drop-off rates
-- Shows: where in the funnel leads are being lost
WITH ordered_stages AS (
    SELECT
        stage,
        COUNT(DISTINCT lead_id)                       AS entered,
        LAG(COUNT(DISTINCT lead_id)) OVER (ORDER BY
            CASE stage
                WHEN 'inquiry'       THEN 1
                WHEN 'contacted'     THEN 2
                WHEN 'demo_attended' THEN 3
                WHEN 'fee_discussed' THEN 4
                WHEN 'registered'    THEN 5
                WHEN 'enrolled'      THEN 6
            END
        )                                             AS prev_stage_count
    FROM funnel_events
    WHERE event_date >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
    GROUP BY stage
)
SELECT
    stage,
    entered,
    prev_stage_count,
    ROUND((prev_stage_count - entered) * 100.0 / NULLIF(prev_stage_count, 0), 2) AS drop_off_pct
FROM ordered_stages
ORDER BY
    CASE stage
        WHEN 'inquiry'       THEN 1
        WHEN 'contacted'     THEN 2
        WHEN 'demo_attended' THEN 3
        WHEN 'fee_discussed' THEN 4
        WHEN 'registered'    THEN 5
        WHEN 'enrolled'      THEN 6
    END;


-- Q3: Lead-to-enrollment conversion by source
-- Shows: which lead source drives the best quality leads
SELECT
    l.source,
    COUNT(DISTINCT l.lead_id)                                    AS total_leads,
    COUNT(DISTINCT e.enrollment_id)                              AS total_enrollments,
    ROUND(COUNT(DISTINCT e.enrollment_id) * 100.0 /
          NULLIF(COUNT(DISTINCT l.lead_id), 0), 2)               AS conversion_pct,
    ROUND(SUM(e.fee_paid) / NULLIF(COUNT(DISTINCT e.enrollment_id),0), 0) AS avg_fee_per_enrollment
FROM leads l
LEFT JOIN enrollments e ON l.lead_id = e.lead_id
GROUP BY l.source
ORDER BY conversion_pct DESC;


-- Q4: Source-wise ROI (cost per lead and cost per enrollment)
-- Requires a marketing_spend table or enter spend manually
-- Using a CTE for assumed monthly spends (replace with actual table)
WITH source_spend AS (
    SELECT 'paid_google' AS source, 150000 AS monthly_spend UNION ALL
    SELECT 'paid_meta',             120000                   UNION ALL
    SELECT 'organic',               20000                    UNION ALL
    SELECT 'referral',              30000                    UNION ALL
    SELECT 'walk_in',               10000                    UNION ALL
    SELECT 'offline_event',         60000
),
lead_enroll AS (
    SELECT
        l.source,
        COUNT(DISTINCT l.lead_id)       AS leads,
        COUNT(DISTINCT e.enrollment_id) AS enrollments,
        SUM(e.fee_paid)                 AS revenue
    FROM leads l
    LEFT JOIN enrollments e ON l.lead_id = e.lead_id
    WHERE l.created_date >= DATE_FORMAT(CURDATE(),'%Y-%m-01')
    GROUP BY l.source
)
SELECT
    le.source,
    le.leads,
    le.enrollments,
    le.revenue,
    ss.monthly_spend,
    ROUND(ss.monthly_spend / NULLIF(le.leads, 0), 0)        AS cost_per_lead,
    ROUND(ss.monthly_spend / NULLIF(le.enrollments, 0), 0)  AS cost_per_enrollment,
    ROUND(le.revenue / NULLIF(ss.monthly_spend, 0), 2)      AS roi_ratio
FROM lead_enroll le
JOIN source_spend ss ON le.source = ss.source
ORDER BY roi_ratio DESC;


-- Q5: Monthly lead volume trend (last 12 months)
SELECT
    DATE_FORMAT(created_date, '%Y-%m')      AS month,
    l.source,
    COUNT(*)                                AS new_leads,
    COUNT(DISTINCT e.enrollment_id)         AS enrollments
FROM leads l
LEFT JOIN enrollments e ON l.lead_id = e.lead_id
    AND DATE_FORMAT(e.enrollment_date, '%Y-%m') = DATE_FORMAT(l.created_date, '%Y-%m')
WHERE l.created_date >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
GROUP BY 1, 2
ORDER BY 1, 2;


-- ============================================================
-- SECTION 3: COUNSELLOR PERFORMANCE QUERIES
-- ============================================================

-- Q6: Counsellor leaderboard (conversion + revenue + speed)
SELECT
    c.counsellor_name,
    ct.centre_name,
    COUNT(DISTINCT l.lead_id)                               AS leads_assigned,
    COUNT(DISTINCT e.enrollment_id)                         AS enrollments,
    ROUND(COUNT(DISTINCT e.enrollment_id) * 100.0 /
          NULLIF(COUNT(DISTINCT l.lead_id), 0), 1)          AS conversion_pct,
    ROUND(SUM(e.fee_paid), 0)                               AS total_revenue,
    ROUND(AVG(DATEDIFF(e.enrollment_date, l.created_date)), 1) AS avg_days_to_close,
    RANK() OVER (ORDER BY COUNT(DISTINCT e.enrollment_id) DESC) AS revenue_rank
FROM counsellors c
JOIN centres ct      ON c.centre_id = ct.centre_id
JOIN leads l         ON c.counsellor_id = l.counsellor_id
LEFT JOIN enrollments e ON l.lead_id = e.lead_id
    AND e.counsellor_id = c.counsellor_id
WHERE l.created_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY c.counsellor_id, c.counsellor_name, ct.centre_name
ORDER BY conversion_pct DESC;


-- Q7: Counsellor follow-up effectiveness
-- Checks how quickly counsellors contact a new lead (speed matters for conversion)
SELECT
    c.counsellor_name,
    COUNT(DISTINCT l.lead_id)                            AS total_leads,
    AVG(DATEDIFF(fe.event_date, l.created_date))         AS avg_response_days,
    SUM(CASE WHEN DATEDIFF(fe.event_date, l.created_date) <= 1 THEN 1 ELSE 0 END) AS same_day_contact,
    ROUND(SUM(CASE WHEN DATEDIFF(fe.event_date, l.created_date) <= 1 THEN 1 ELSE 0 END) * 100.0 /
          NULLIF(COUNT(DISTINCT l.lead_id), 0), 1)        AS same_day_contact_pct
FROM counsellors c
JOIN leads l ON c.counsellor_id = l.counsellor_id
JOIN funnel_events fe ON l.lead_id = fe.lead_id AND fe.stage = 'contacted'
WHERE l.created_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY c.counsellor_id, c.counsellor_name
ORDER BY same_day_contact_pct DESC;


-- Q8: Counsellor pipeline health (active leads in each stage right now)
SELECT
    c.counsellor_name,
    SUM(CASE WHEN l.status = 'new'          THEN 1 ELSE 0 END) AS new_leads,
    SUM(CASE WHEN l.status = 'contacted'    THEN 1 ELSE 0 END) AS contacted,
    SUM(CASE WHEN l.status = 'qualified'    THEN 1 ELSE 0 END) AS qualified,
    SUM(CASE WHEN l.status = 'registered'   THEN 1 ELSE 0 END) AS registered,
    SUM(CASE WHEN l.status = 'enrolled'     THEN 1 ELSE 0 END) AS enrolled,
    SUM(CASE WHEN l.status = 'dropped'      THEN 1 ELSE 0 END) AS dropped,
    COUNT(*)                                                    AS total_active
FROM counsellors c
JOIN leads l ON c.counsellor_id = l.counsellor_id
WHERE l.status NOT IN ('enrolled','dropped')
   OR l.created_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY c.counsellor_id, c.counsellor_name
ORDER BY total_active DESC;


-- Q9: Top-performing counsellors by centre (for centre-level leaderboard)
WITH ranked AS (
    SELECT
        ct.centre_name,
        c.counsellor_name,
        COUNT(DISTINCT e.enrollment_id)                          AS enrollments,
        ROUND(SUM(e.fee_paid), 0)                                AS revenue,
        RANK() OVER (PARTITION BY ct.centre_id
                     ORDER BY COUNT(DISTINCT e.enrollment_id) DESC) AS rank_in_centre
    FROM counsellors c
    JOIN centres ct ON c.centre_id = ct.centre_id
    JOIN leads l    ON c.counsellor_id = l.counsellor_id
    JOIN enrollments e ON l.lead_id = e.lead_id
    WHERE e.enrollment_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
    GROUP BY ct.centre_id, ct.centre_name, c.counsellor_id, c.counsellor_name
)
SELECT centre_name, counsellor_name, enrollments, revenue, rank_in_centre
FROM ranked
WHERE rank_in_centre <= 3
ORDER BY centre_name, rank_in_centre;


-- ============================================================
-- SECTION 4: CENTRE & GEOGRAPHY QUERIES
-- ============================================================

-- Q10: Centre-wise performance summary
SELECT
    ct.centre_name,
    ct.city,
    ct.state,
    COUNT(DISTINCT l.lead_id)               AS total_leads,
    COUNT(DISTINCT e.enrollment_id)         AS enrollments,
    ROUND(COUNT(DISTINCT e.enrollment_id) * 100.0 /
          NULLIF(COUNT(DISTINCT l.lead_id), 0), 1) AS conversion_pct,
    ROUND(SUM(e.fee_paid), 0)               AS total_revenue,
    COUNT(DISTINCT l.counsellor_id)         AS active_counsellors
FROM centres ct
LEFT JOIN leads l ON ct.centre_id = l.centre_id
LEFT JOIN enrollments e ON l.lead_id = e.lead_id
WHERE l.created_date >= DATE_FORMAT(CURDATE(),'%Y-%m-01')
GROUP BY ct.centre_id, ct.centre_name, ct.city, ct.state
ORDER BY total_revenue DESC;


-- Q11: State-wise enrollment heatmap data (for Power BI map visual)
SELECT
    l.state,
    l.city,
    COUNT(DISTINCT l.lead_id)               AS total_leads,
    COUNT(DISTINCT e.enrollment_id)         AS enrollments,
    ROUND(SUM(e.fee_paid), 0)               AS revenue
FROM leads l
LEFT JOIN enrollments e ON l.lead_id = e.lead_id
WHERE l.created_date >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
GROUP BY l.state, l.city
ORDER BY enrollments DESC;


-- ============================================================
-- SECTION 5: BUSINESS REVIEW QUERIES (WEEKLY / MONTHLY)
-- ============================================================

-- Q12: Weekly performance vs prior week (for Monday morning review)
WITH current_week AS (
    SELECT
        COUNT(DISTINCT l.lead_id)       AS leads,
        COUNT(DISTINCT e.enrollment_id) AS enrollments,
        SUM(e.fee_paid)                 AS revenue
    FROM leads l
    LEFT JOIN enrollments e ON l.lead_id = e.lead_id
    WHERE l.created_date BETWEEN DATE_SUB(CURDATE(), INTERVAL 7 DAY) AND CURDATE()
),
prior_week AS (
    SELECT
        COUNT(DISTINCT l.lead_id)       AS leads,
        COUNT(DISTINCT e.enrollment_id) AS enrollments,
        SUM(e.fee_paid)                 AS revenue
    FROM leads l
    LEFT JOIN enrollments e ON l.lead_id = e.lead_id
    WHERE l.created_date BETWEEN DATE_SUB(CURDATE(), INTERVAL 14 DAY)
                             AND DATE_SUB(CURDATE(), INTERVAL 7 DAY)
)
SELECT
    cw.leads                                                    AS this_week_leads,
    pw.leads                                                    AS last_week_leads,
    ROUND((cw.leads - pw.leads) * 100.0 / NULLIF(pw.leads,0),1) AS leads_wow_pct,
    cw.enrollments                                              AS this_week_enrollments,
    pw.enrollments                                              AS last_week_enrollments,
    ROUND((cw.enrollments - pw.enrollments) * 100.0 / NULLIF(pw.enrollments,0),1) AS enrollment_wow_pct,
    ROUND(cw.revenue, 0)                                        AS this_week_revenue,
    ROUND(pw.revenue, 0)                                        AS last_week_revenue
FROM current_week cw, prior_week pw;


-- Q13: Monthly target vs actuals (requires a targets table)
-- Stub target table for demonstration
WITH targets AS (
    SELECT DATE_FORMAT(CURDATE(),'%Y-%m') AS month, 500 AS lead_target, 80 AS enrollment_target, 4000000 AS revenue_target
),
actuals AS (
    SELECT
        DATE_FORMAT(l.created_date,'%Y-%m') AS month,
        COUNT(DISTINCT l.lead_id)            AS leads_actual,
        COUNT(DISTINCT e.enrollment_id)      AS enrollments_actual,
        ROUND(SUM(e.fee_paid),0)             AS revenue_actual
    FROM leads l
    LEFT JOIN enrollments e ON l.lead_id = e.lead_id
    WHERE DATE_FORMAT(l.created_date,'%Y-%m') = DATE_FORMAT(CURDATE(),'%Y-%m')
    GROUP BY 1
)
SELECT
    a.month,
    t.lead_target,       a.leads_actual,
    ROUND(a.leads_actual * 100.0 / t.lead_target, 1)          AS lead_attainment_pct,
    t.enrollment_target, a.enrollments_actual,
    ROUND(a.enrollments_actual * 100.0 / t.enrollment_target, 1) AS enrollment_attainment_pct,
    t.revenue_target,    a.revenue_actual,
    ROUND(a.revenue_actual * 100.0 / t.revenue_target, 1)     AS revenue_attainment_pct
FROM actuals a
JOIN targets t ON a.month = t.month;


-- Q14: Drop reason analysis (why are leads not converting?)
SELECT
    fe.drop_reason,
    COUNT(*)                                        AS count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct_of_drops,
    l.source,
    c.centre_name
FROM funnel_events fe
JOIN leads l    ON fe.lead_id = l.lead_id
JOIN centres c  ON l.centre_id = c.centre_id
WHERE fe.stage = 'dropped'
  AND fe.event_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
  AND fe.drop_reason IS NOT NULL
GROUP BY fe.drop_reason, l.source, c.centre_name
ORDER BY count DESC;


-- Q15: Average time spent per funnel stage (bottleneck detection)
SELECT
    stage,
    ROUND(AVG(days_in_stage), 1)       AS avg_days,
    ROUND(MIN(days_in_stage), 1)       AS min_days,
    ROUND(MAX(days_in_stage), 1)       AS max_days,
    ROUND(STDDEV(days_in_stage), 1)    AS stddev_days,
    COUNT(*)                           AS sample_size
FROM funnel_events
WHERE event_date >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
  AND days_in_stage IS NOT NULL
GROUP BY stage
ORDER BY
    CASE stage
        WHEN 'inquiry'       THEN 1
        WHEN 'contacted'     THEN 2
        WHEN 'demo_attended' THEN 3
        WHEN 'fee_discussed' THEN 4
        WHEN 'registered'    THEN 5
        WHEN 'enrolled'      THEN 6
    END;


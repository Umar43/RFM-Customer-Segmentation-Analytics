# Customer Segmentation & RFM Analytics

Analyzed ~542,000 transactions from a UK-based online retailer to segment customers by purchasing behavior (Recency, Frequency, Monetary value), identify real data quality issues, statistically validate findings, and build an interactive Power BI dashboard.

**Tools used:** Excel · PostgreSQL (SQL) · Python (pandas, scipy) · Power BI

---

## Business Question

Which customers are most valuable, which are at risk of churning, and is the difference in spending between segments statistically meaningful — or just noise?

## Data Source

[Online Retail II](https://archive.ics.uci.edu/dataset/502/online+retail+ii) — UCI Machine Learning Repository. Real transactional data from a UK-based online retailer, 2010–2011 (2010–2011 sheet used: 541,910 rows).

---

## Process

### 1. Exploratory Analysis (Excel)
Built pivot tables for revenue by country, revenue by month, and top 10 products by quantity. Found and fixed a pivot table range error (header row excluded), and discovered that a calculated field inside a pivot table multiplies column *totals* rather than computing row-by-row — fixed by adding a true per-row `Revenue` column to the raw data instead.

**Finding:** the dataset's last recorded date is December 9, 2011 — December figures reflect a partial month only and aren't directly comparable to full months.

### 2. Data Cleaning & Investigation (SQL — PostgreSQL)
Identified and handled three real data quality issues, each investigated rather than assumed:

| Issue | Rows affected | Decision |
|---|---|---|
| Missing `customer_id` | 135,080 (25%) | Excluded from customer-level analysis only; kept for product/country-level analysis |
| Cancelled orders (`invoice_no` starting with 'C') | 9,288 | Excluded from RFM — not real purchases |
| Internal stock adjustments (negative quantity, zero price, no customer/description) | 1,336 | Confirmed pattern via zero-price check; excluded from RFM |

**Cancelled-then-rebought orders:** found that simple invoice-prefix filtering misses the *original* order when it's later cancelled (only the cancellation record itself gets filtered). Built a self-join to detect these — an initial version over-matched unrelated repeat purchases of the same product/quantity; refined it with a time constraint (cancellation must occur within 1 day of the original order) to correctly isolate genuine cancel-then-rebuy pairs without penalizing loyal repeat customers.

### 3. RFM Segmentation (SQL)
Calculated Recency, Frequency, and Monetary value per customer, then scored each dimension into quartiles (`NTILE(4)`) and assigned customers to one of four segments:

| Segment | Customers | Avg Recency (days) | Avg Frequency | Avg Spend |
|---|---|---|---|---|
| Champions | 1,358 (31%) | 16.6 | 9.0 | $4,744 |
| At Risk | 858 (20%) | 123.3 | 3.5 | $1,534 |
| New / Promising | 806 (19%) | 23.8 | 1.8 | $416 |
| Lost | 1,306 (30%) | 192.2 | 1.2 | $288 |

### 4. Statistical Validation (Python)
Ran a Welch's t-test comparing average spend between the Champions and At Risk segments:

- **t-statistic:** 8.15
- **p-value:** 7.7 × 10⁻¹⁶ (p < 0.001)

The difference in spend between Champions and At Risk is statistically significant — not random variation — confirming Champions are a genuinely higher-value segment.

### 5. Dashboard (Power BI)
Interactive dashboard with segment breakdown (donut chart), average spend/recency/frequency by segment (bar charts), KPI cards, and a slicer for filtering.

![Dashboard](assets/Dashboard.png)

---

## Key Insights
- **Champions** (31% of customers) generate the highest average spend ($4.7K) — nearly 3x more than At Risk, and this gap is statistically confirmed (p < 0.001).
- **At Risk** customers haven't purchased in ~123 days on average despite meaningful historical spend — a strong candidate segment for win-back campaigns.
- **Lost** segment (30% of customers) shows minimal recent activity and the lowest order frequency — low priority for retention spend.

## Repository Structure
```
rfm-customer-segmentation/
├── data/
│   ├── online_retail_II_2010_2011.csv      # Raw dataset (UCI)
│   ├── online_retail_pivot_analysis.xlsx   # Excel exploratory analysis
│   └── customer_segments_final.csv         # Final RFM + segment labels
├── notebooks/
│   └── rfm_statistical_analysis.ipynb      # Python t-test (Champions vs At Risk)
├── power_bi/
│   └── rfm_dashboard.pbix                  # Power BI dashboard file
├── assets/
│   └── dashboard_overview.png              # Dashboard screenshot
├── 01_data_cleaning_rfm_segmentation.sql   # Full SQL cleaning & RFM script
└── README.md
```

## Limitations & Notes
- Time-constrained self-join for detecting cancel-then-rebuy pairs uses a 1-day window; this is a reasonable heuristic but not a guaranteed match in every edge case, since the dataset has no direct link from a cancellation to its specific original invoice.
- Dataset contains some duplicate rows (a known characteristic of this specific dataset, not an import error).
- Dashboard built on a static data export rather than a live database connection.

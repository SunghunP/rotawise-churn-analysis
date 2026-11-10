# Rotawise Customer Churn Analysis

This project builds an end-to-end ETL pipeline to analyze customer churn for Rotawise, a fictional B2B SaaS company that sells employee scheduling software. Raw data is extracted from Google Sheets via API, cleaned with Python and pandas, and loaded into SQL Server. SQL analysis finds who churns, when, and the early warning signs, and a risk score sorts every active account into green, yellow and red tiers with an action for each. Findings are shown in a Tableau dashboard.

**Dashboard:** [Tableau Public](https://public.tableau.com/app/profile/joe.park2461/viz/RotawiseChurnDashboard/3Action)

## Key Findings

- Last year, Pro was 37% of churned accounts but 55% of lost MRR. Starter was 61% of churned accounts but only 18% of lost MRR.
- 18% of monthly accounts churn by month 6.
- High-risk accounts (score 16–20) churn at 61–73% vs 15% or less for low-risk (0–8).
- $1.58M of MRR expected lost in the next 12 months. Red and yellow accounts are 27% of active accounts but hold $923K (59%) of it.

## Recommendations

1. **Red (16–20), 1,188 accounts, $242K at risk:** one-on-one calls within 30 days, highest expected loss first.
2. **Yellow (9–15), 7,875 accounts, $682K at risk:** group training, webinars and reminder emails for whatever sign they have.
3. **Green (0–8):** no extra outreach. Rescore monthly and move accounts up when they cross 9.

## Limitations

- The risk score only uses things we can change, not company size or industry.

## Data Cleaning

52,968 raw rows → 51,831 clean. Removed 1,137 duplicates, fixed labels (`PRO`/`Pro`, `EU`/`Europe`, `Y`/`TRUE`/`Yes`), set impossible values to missing (NPS of 15, 99999 employees), parsed two date formats, and filled missing MRR from pricing.

## Files

- `extract.py`, `transform.py`, `load.py`: the ETL pipeline (`python load.py` runs all three)
- `churn_analysis.sql`: SQL analysis
- `rotawise_churn_dashboard.twb`: Tableau workbook
- `data/`: raw data, clean data, and the scored active accounts

## Tools

Python (pandas, gspread, SQLAlchemy), SQL Server, Tableau

## How to run

1. `pip install -r requirements.txt`
2. Add a `.env` with `SPREADSHEET_NAME`, `GOOGLE_KEY_PATH`, `SQL_SERVER`, `SQL_DATABASE`
3. `python load.py`

# Rotawise Customer Churn Analysis

This project builds an end-to-end ETL pipeline to analyze customer churn for Rotawise, a fictional B2B SaaS company that sells employee scheduling software. Raw data is extracted from Google Sheets via API, cleaned with Python and pandas, and loaded into SQL Server. SQL analysis finds who churns, when, and the early warning signs, and a risk score turns that into a call list for the Customer Success team. Findings are shown in a Tableau dashboard.

**Dashboard:** [Tableau Public](https://public.tableau.com/app/profile/joe.park2461/viz/RotawiseChurnDashboard/3Action)

## Key Findings

- Last year, Pro was 37% of churned accounts but 55% of lost MRR. Starter was 61% of churned accounts but only 18% of lost MRR.
- 18% of monthly accounts churn by month 6.
- High-risk accounts (score 16–20) churn at 61–73% vs 15% or less for low-risk (0–8).
- $1.58M of MRR expected lost in the next 12 months. The top 640 accounts by expected loss hold $414K of it.

## Recommendations

1. **Enterprise + riskiest Pro:** CSMs call the 640 accounts within 30 days, highest expected loss first.
2. **Rest of Pro:** group training and webinars for accounts with no training or low seat use.
3. **Starter:** build onboarding into setup with reminder emails. Starter accounts that skip onboarding churn at 38% vs 13%.

## Limitations

- The risk score only uses things we can change, not company size or industry.
- The 640 limit (8 CSMs × 80 accounts) is an assumption. The data doesn't say which CSM has which account.

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

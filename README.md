# Customer Churn Analysis: Getting At-Risk Accounts Under 25% Churn

Churn analysis for Rotawise, a fictional business-to-business company that sells employee scheduling software by subscription. Python pulls the data from Google Sheets, cleans it and loads it into SQL Server. SQL finds the warning signs, and a Tableau dashboard shows the results.

**Business question:** How do we get churn for our riskiest accounts down to 25%?

Accounts with a risk score of 11 or more churned at 44% last year. Every score of 10 or under stayed under 25%.

**Dashboard:** [Tableau Public](https://public.tableau.com/app/profile/joe.park2461/viz/RotawiseChurnDashboard/3Action)

MRR (monthly recurring revenue) = what a customer pays each month.

## Findings

**How is the risk score calculated?**\
Each warning sign adds points. 0 = healthy, 20 = every sign.

| Warning sign | Points |
|---|---|
| Onboarding not completed | 4 |
| No training | 3 |
| Seat use under 60% | 3 |
| 31+ days to go live | 3 |
| 0 or 1 integrations | 2 |
| Feature adoption under 50% | 2 |
| Survey score 0–6 or no answer | 2 |
| 1+ escalated tickets | 1 |

**Does a higher risk score mean more churn?**\
Yes. 4 in 10 at-risk accounts (score 11+) left last year, vs. 1 in 10 low-risk (0–10).\
Next step: fix their warning signs to get them under 11.

**Which plan loses the most money?**\
Pro: $762K of MRR lost last year, more than Starter and Enterprise combined.\
Next step: rank accounts by money at risk.

**What's the strongest warning sign?**\
Skipping onboarding: 3–4x more churn on every plan.\
Next step: remind accounts to finish onboarding.

**When do customers leave?**\
Early: 18% of monthly-contract accounts are gone by month 6.\
Next step: rescore accounts every month.

## What to do

We expect to lose $1.58M of MRR in the next 12 months. At-risk accounts are 14% of active accounts but hold $565K (36%) of it.

1. **At risk (score 11+), 4,576 accounts:** call the ones with the most money at risk within 30 days. Training and reminder emails for the rest.
2. **Start with onboarding:** it's the biggest warning sign, worth 4 points.
3. **Low risk (score 0–10), 29,012 accounts:** rescore every month.

## Data Cleaning

52,968 raw rows → 51,831 clean. Removed 1,137 duplicates, fixed labels (`PRO`/`Pro`, `EU`/`Europe`, `Y`/`TRUE`/`Yes`), set impossible values to missing (a survey score of 15, 99999 employees), parsed two date formats, and filled missing MRR from pricing.

## Limitations

The risk score only uses things we can change, not company size or industry.

## Files

- `extract.py`, `transform.py`, `load.py`: the pipeline (`python load.py` runs all three)
- `churn_analysis.sql`: SQL analysis
- `rotawise_churn_dashboard.twb`: Tableau workbook
- `data/`: raw data, clean data, and the scored active accounts

## Tools

Python (pandas, gspread, SQLAlchemy), SQL Server, Tableau

## How to run

1. `pip install -r requirements.txt`
2. Add a `.env` with `SPREADSHEET_NAME`, `GOOGLE_KEY_PATH`, `SQL_SERVER`, `SQL_DATABASE`
3. `python load.py`

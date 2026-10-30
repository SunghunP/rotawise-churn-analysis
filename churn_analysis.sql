-- Rotawise churn analysis (SQL Server)
-- Runs on dbo.rotawise_accounts_etl, loaded by load.py
USE CustomerChurn;
GO

-- Yes/No columns as 1/0 so they can be summed
CREATE OR ALTER VIEW dbo.vw_Accounts AS
SELECT
    AccountID, SignupDate, ChurnDate, Industry, EmployeeCount, Region, AcquisitionChannel,
    [Plan], ContractType, TenureMonths, SeatsPurchased, ActiveSeats, SeatUtilizationPct,
    MRR, DiscountPct,
    CASE WHEN OnboardingCompleted = 'Yes' THEN 1 ELSE 0 END AS OnboardingCompleted,
    DaysToGoLive, TrainingSessions,
    CASE WHEN CSMAssigned = 'Yes' THEN 1 ELSE 0 END AS CSMAssigned,
    DaysSinceCSMContact, IntegrationsConnected, FeatureAdoptionPct, SupportTickets90d,
    EscalatedTickets90d, NPS, LatePayments,
    CASE WHEN Churned = 'Yes' THEN 1 ELSE 0 END AS Churned,
    ChurnReason
FROM dbo.rotawise_accounts_etl;
GO


-- Phase 1: EDA

-- Total accounts
SELECT COUNT(*)
FROM dbo.vw_Accounts;

-- Lifetime churn rate %
SELECT (100.0*SUM(CASE WHEN Churned = 1 Then 1 Else 0 END))/(COUNT(Churned))
FROM dbo.vw_Accounts;

-- Annual logo churn % (2025-09-30 to 2026-09-30)
-- Annual logo churn: share of accounts active on 2025-09-30 that churned by 2026-09-30
-- Starting base: signed up on or before the window start and not yet churned (excludes signups during the timeframe)
WITH StartingBase AS (
  SELECT COUNT(*) AS StartingAccounts
  FROM dbo.vw_Accounts
  WHERE SignupDate <= '2025-09-30'
    AND (ChurnDate IS NULL OR ChurnDate > '2025-09-30')
),
-- Churned in window: same base, churn date inside the window (SignupDate filter repeated so numerator is a subset of the base)
ChurnedInWindow AS (
  SELECT COUNT(*) AS ChurnedAccounts
  FROM dbo.vw_Accounts
  WHERE SignupDate <= '2025-09-30'
    AND ChurnDate > '2025-09-30'
    AND ChurnDate <= '2026-09-30'
)
-- Each CTE is one row, so CROSS JOIN gives both counts side by side; 100.0 avoids integer division
SELECT
  StartingAccounts,
  ChurnedAccounts,
  100.0 * ChurnedAccounts / StartingAccounts AS AnnualLogoChurnPct
FROM StartingBase
CROSS JOIN ChurnedInWindow;

-- Annual revenue churn %
WITH StartingBase AS (
  -- lets start by finding the total revenue.
  SELECT SUM(MRR) AS TotalRevenue
  FROM dbo.vw_Accounts
  WHERE SignupDate <= '2025-09-30'
  AND (ChurnDate IS NULL OR ChurnDate > '2025-09-30')
), MRRSum AS (
  -- need to get the sum of the lost revenue
  SELECT SUM(MRR) AS LostRevenue
  FROM dbo.vw_Accounts
  WHERE SignupDate <= '2025-09-30'
  AND ChurnDate > '2025-09-30'
  AND ChurnDate <= '2026-09-30'
)
SELECT 
  TotalRevenue,
  LostRevenue,
  100.0 * LostRevenue / TotalRevenue AS RevenueLostPct
FROM StartingBase
CROSS JOIN MRRSum;


-- Phase 2: Who churns?

-- Starting base view: accounts active on 2025-09-30, flagged if they churned in the next 12 months
GO
CREATE OR ALTER VIEW dbo.vw_StartingBase AS
SELECT *,
  CASE WHEN ChurnDate > '2025-09-30' AND ChurnDate <= '2026-09-30'
       THEN 1 ELSE 0 END AS ChurnedInWindow
FROM dbo.vw_Accounts
WHERE SignupDate <= '2025-09-30'
  AND (ChurnDate IS NULL OR ChurnDate > '2025-09-30');
GO

-- Churn rate % by group for every factor, vs the baseline
WITH Baseline AS (
  -- overall churn rate for the whole starting base
	SELECT 100.0 * SUM(ChurnedInWindow) / COUNT(*) AS BaselinePct
	FROM vw_StartingBase
), GroupChurn AS (
  -- each factor is listed below; this gives account count and churn rate for every group in it
	SELECT f.Factor, f.GroupName,
		COUNT(*) AS Accounts,
		100.0 * SUM(ChurnedInWindow) / COUNT(*) AS ChurnPct
	FROM dbo.vw_StartingBase
	CROSS APPLY (VALUES
		('Plan', [Plan]),
		('ContractType', ContractType),
		('Region', Region),
		('AcquisitionChannel', AcquisitionChannel),
		('Industry', Industry),
		-- company size ranges (blank = Unknown)
		('CompanySize', CASE 
			WHEN EmployeeCount IS NULL THEN 'h: Unknown'
			WHEN EmployeeCount < 10 THEN 'a: under 10'
			WHEN EmployeeCount < 50 THEN 'c: 10-49'
			WHEN EmployeeCount < 100 THEN 'd: 50-99'
			WHEN EmployeeCount < 250 THEN 'e: 100-249'
			WHEN EmployeeCount < 500 THEN 'f: 250-499'
			ELSE 'g: 500+' END),
		-- discount ranges (no discount is its own group)
		('Discount', CASE
			WHEN DiscountPct = 0 THEN 'a: none'
			WHEN DiscountPct <= 10 THEN 'b: 1-10'
			WHEN DiscountPct <= 20 THEN 'c: 11-20'
			WHEN DiscountPct <= 30 THEN 'd: 21-30'
			ELSE 'e: 31+' END)
	) AS f(Factor, GroupName)
	GROUP BY f.Factor, f.GroupName
), GroupVsBaseline AS (
  -- add the overall churn rate to every group row so we can compare
	SELECT 
		Factor,
		GroupName,
		Accounts,
		ChurnPct,
		BaselinePct
	FROM GroupChurn
	CROSS JOIN Baseline
)
-- DiffPp = group churn rate minus overall rate, in percentage points
-- HighestChurn = the highest group rate within the same factor
SELECT
	Factor,
	GroupName,
	Accounts,
	ChurnPct,
	ChurnPct - BaselinePct AS DiffPp,
	MAX(ChurnPct) OVER (PARTITION BY Factor) AS HighestChurn
FROM GroupVsBaseline
WHERE Accounts >= 500
ORDER BY Factor, ChurnPct DESC, GroupName;

-- Factors ranked by spread (which one matters most)
WITH GroupChurn AS (
  -- each factor is listed below; this gives account count and churn rate for every group in it
	SELECT f.Factor, f.GroupName,
		COUNT(*) AS Accounts,
		100.0 * SUM(ChurnedInWindow) / COUNT(*) AS ChurnPct
	FROM dbo.vw_StartingBase
	CROSS APPLY (VALUES
		('Plan', [Plan]),
		('ContractType', ContractType),
		('Region', Region),
		('AcquisitionChannel', AcquisitionChannel),
		('Industry', Industry),
		-- company size ranges (blank = Unknown)
		('CompanySize', CASE 
			WHEN EmployeeCount IS NULL THEN 'h: Unknown'
			WHEN EmployeeCount < 10 THEN 'a: under 10'
			WHEN EmployeeCount < 50 THEN 'c: 10-49'
			WHEN EmployeeCount < 100 THEN 'd: 50-99'
			WHEN EmployeeCount < 250 THEN 'e: 100-249'
			WHEN EmployeeCount < 500 THEN 'f: 250-499'
			ELSE 'g: 500+' END),
		-- discount ranges (no discount is its own group)
		('Discount', CASE
			WHEN DiscountPct = 0 THEN 'a: none'
			WHEN DiscountPct <= 10 THEN 'b: 1-10'
			WHEN DiscountPct <= 20 THEN 'c: 11-20'
			WHEN DiscountPct <= 30 THEN 'd: 21-30'
			ELSE 'e: 31+' END)
	) AS f(Factor, GroupName)
	GROUP BY f.Factor, f.GroupName
), RankedChurn AS (
  SELECT
		Factor,
		GroupName,
		Accounts,
		ChurnPct
	FROM GroupChurn
  -- keep only groups with 500+ accounts, since churn rates of smaller groups swing too much
  WHERE Accounts >= 500
)
SELECT
	Factor,
	COUNT(*) AS Groups,
	MAX(ChurnPct) AS HighestPct,
	MIN(ChurnPct) AS LowestPct,
	MAX(ChurnPct) - MIN(ChurnPct) AS SpreadPp
FROM RankedChurn
GROUP BY Factor
ORDER BY SpreadPp DESC;

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


-- Phase 3: What are the warning signs?

-- Churn rate % and gap for each warning sign
WITH GroupChurn AS (
	-- each factor is listed below; this gives account count, churned count and churn rate for every group in it
	SELECT f.Factor, f.GroupName,
		COUNT(*) AS Accounts,
		SUM(ChurnedInWindow) AS Churned,
		100.0 * SUM(ChurnedInWindow) / COUNT(*) AS ChurnPct
	FROM dbo.vw_StartingBase
	-- turns each column into rows of (Factor, GroupName) so one query covers all nine factors
	CROSS APPLY (VALUES
		('OnboardingCompleted', CAST(OnboardingCompleted AS VARCHAR(10))),
		-- Seat utilization in groups of 10
		('SeatUsedPct', CASE
			WHEN SeatUtilizationPct < 10 THEN '0-9'
			WHEN SeatUtilizationPct < 20 THEN '10-19'
			WHEN SeatUtilizationPct < 30 THEN '20-29'
			WHEN SeatUtilizationPct < 40 THEN '30-39'
			WHEN SeatUtilizationPct < 50 THEN '40-49'
			WHEN SeatUtilizationPct < 60 THEN '50-59'
			WHEN SeatUtilizationPct < 70 THEN '60-69'
			WHEN SeatUtilizationPct < 80 THEN '70-79'
			WHEN SeatUtilizationPct < 90 THEN '80-89'
			ELSE '90-100' END),
		-- NPS survey score (0-10); blank means they didn't answer
		('NPS', CASE
			WHEN NPS IS NULL THEN 'a: No Answer'
			WHEN NPS <= 6 THEN 'b: Detractor'
			WHEN NPS IN (7,8) THEN 'c: Passive'
			WHEN NPS IN (9,10) THEN 'd: Promoter'
			ELSE 'a: No Answer' END),
		-- letter prefixes keep the groups in order when they sort as text
		('FeatureAdoptionPct', CASE
			WHEN FeatureAdoptionPct < 10 THEN 'a: 0-9'
			WHEN FeatureAdoptionPct < 20 THEN 'b: 10-19'
			WHEN FeatureAdoptionPct < 30 THEN 'c: 20-29'
			WHEN FeatureAdoptionPct < 40 THEN 'd: 30-39'
			WHEN FeatureAdoptionPct < 50 THEN 'e: 40-49'
			WHEN FeatureAdoptionPct < 60 THEN 'f: 50-59'
			WHEN FeatureAdoptionPct < 70 THEN 'g: 60-69'
			WHEN FeatureAdoptionPct < 80 THEN 'h: 70-79'
			WHEN FeatureAdoptionPct < 90 THEN 'i: 80-89'
			ELSE 'j: 90-100' END),
		-- 5+ grouped because every group above 5 has too few accounts
		('TrainingSessions', CASE
			WHEN TrainingSessions = 0 THEN '0'
			WHEN TrainingSessions = 1 THEN '1'
			WHEN TrainingSessions = 2 THEN '2'
			WHEN TrainingSessions = 3 THEN '3'
			WHEN TrainingSessions = 4 THEN '4'
			ELSE '5+' END),
		-- edge at 31 because churn jumps between day 30 and day 31
		('DaysToGoLive', CASE
			WHEN DaysToGoLive < 15 THEN 'a: 1-14'
			WHEN DaysToGoLive < 31 THEN 'b: 15-30'
			WHEN DaysToGoLive < 45 THEN 'c: 31-44'
			WHEN DaysToGoLive < 60 THEN 'd: 45-59'
			ELSE 'e: 60+' END),
		-- 6+ grouped because 6, 7 and 8 have only 545, 226 and 128 accounts
		('IntegrationsConnected', CASE
			WHEN IntegrationsConnected = 0 THEN '0'
			WHEN IntegrationsConnected = 1 THEN '1'
			WHEN IntegrationsConnected = 2 THEN '2'
			WHEN IntegrationsConnected = 3 THEN '3'
			WHEN IntegrationsConnected = 4 THEN '4'
			WHEN IntegrationsConnected = 5 THEN '5'
			ELSE '6+' END),
		-- 2+ grouped because 3 and 4 have only 27 and 6 accounts
		('EscalatedTickets90d', CASE
			WHEN EscalatedTickets90d >= 2 THEN '2+'
			ELSE CAST(EscalatedTickets90d AS VARCHAR(10)) END),
		('CSMAssigned', CAST(CSMAssigned AS VARCHAR(10)))
	) AS f(Factor, GroupName)
	GROUP BY f.Factor, f.GroupName
), WindowBaseline AS (
	SELECT
		Factor,
		GroupName,
		Accounts,
		ChurnPct,
		-- each factor's groups add back up to the whole base, so this gives the baseline
		100.0 * SUM(Churned) OVER (PARTITION BY Factor)
			/ SUM(Accounts) OVER (PARTITION BY Factor) AS BaselinePct
	FROM GroupChurn
), GroupVsBaseline AS (
	SELECT
		Factor,
		GroupName,
		Accounts,
		ChurnPct,
		BaselinePct,
		ChurnPct - BaselinePct AS DiffPp
	FROM WindowBaseline
)

SELECT
	Factor,
	GroupName,
	Accounts,
	ChurnPct,
	BaselinePct,
	DiffPp
FROM GroupVsBaseline
ORDER BY Factor, GroupName;


-- Phase 4: When do they churn?

-- Churn rate % by tenure month, monthly contracts
-- count accounts and leavers for each month.
WITH ByMonth AS (
	SELECT
		TenureMonths,
		-- every monthly account at this tenure
		COUNT(*) AS Accounts,
		-- Sum 1 for churned and 0 for not churned
		SUM(CASE WHEN Churned = 1 THEN 1 ELSE 0 END) AS Churned
	-- using every account ever, not just the one year window
	FROM dbo.vw_Accounts
	WHERE ContractType = 'Monthly'
	GROUP BY TenureMonths
), ActiveCounts AS (
	-- work out how many were still around at the start of each month (running total backwards).
	SELECT
		TenureMonths,
		Accounts,
		Churned,
		-- Window function with nothing in the brackets adds up the accounts from all rows
		-- we need this number for a later calculation
		SUM(Accounts) OVER () AS TotalAccounts,
		-- ordering by DESC means it starts summing at month 57 and works backwards adding each rows accounts by month from 57, 56 ... etc
		SUM(Accounts) OVER (ORDER BY TenureMonths DESC) AS ActiveAtStartOfMonth
	FROM ByMonth
), Rates AS (
	-- turn the counts into two percentages.
	SELECT
		TenureMonths,
		Churned,
		TotalAccounts,
		ActiveAtStartOfMonth,
		-- Calculates the Churn percentage from churned acc / accounts still around at the start of the month
		100.0 * Churned / ActiveAtStartOfMonth AS ChurnRatePct,
		-- calculates the Churn percentage from churned acc / total accounts
		100.0 * Churned / TotalAccounts AS PctOfAllMonthly
	FROM ActiveCounts
)
-- add how much has been lost so far (running total forwards).
SELECT
	TenureMonths,
	Churned,
	ActiveAtStartOfMonth,
	ChurnRatePct,
	PctOfAllMonthly,
	-- cumulative churn % adding over month by month
	100.0 * SUM(Churned) OVER (ORDER BY TenureMonths) / TotalAccounts AS CumulativePctLost
FROM Rates
ORDER BY TenureMonths;


-- Phase 5: Is it real?

-- CSM coverage % by plan
WITH PlanCSM AS (
  SELECT
    [Plan],
    -- use a case to count the CSMs
    SUM(CASE WHEN CSMAssigned = 1 THEN 1 ELSE 0 END) AS NumOfCSM,
    COUNT([Plan]) AS NumOfAccounts
  FROM vw_StartingBase
  GROUP BY [Plan]
)
SELECT
  [Plan],
  NumOfCSM,
  NumOfAccounts,
  100.0 * NumOfCSM / NumOfAccounts AS PctAccountsWithCSM
FROM PlanCSM
ORDER BY NumOfCSM;

-- Churn rate % with and without a CSM, by plan
WITH ChurnByCSMAndPlan AS (
  SELECT
    [Plan],
    CSMAssigned,
    COUNT([Plan]) AS TotalAccounts,
    SUM(CASE WHEN ChurnedInWindow = 1 THEN 1 ELSE 0 END) AS ChurnedAccounts
  FROM vw_StartingBase
  GROUP BY [Plan], CSMAssigned
)
SELECT
  [Plan],
  CSMAssigned,
  TotalAccounts,
  ChurnedAccounts,
  100.0 * ChurnedAccounts / TotalAccounts AS ChurnPct
FROM ChurnByCSMAndPlan
ORDER BY [Plan], CSMAssigned;

-- Churn rate % with and without onboarding, by plan
WITH ChurnOnboarding AS (
  SELECT
    [Plan],
    OnboardingCompleted,
    COUNT([Plan]) AS TotalAccounts,
    SUM(CASE WHEN ChurnedInWindow = 1 THEN 1 ELSE 0 END) AS ChurnedAccounts
  FROM vw_StartingBase
  GROUP BY [Plan], OnboardingCompleted
)
SELECT
  [Plan],
  OnboardingCompleted,
  TotalAccounts,
  ChurnedAccounts,
  100.0 * ChurnedAccounts / TotalAccounts AS ChurnPct
FROM ChurnOnboarding
ORDER BY [Plan], OnboardingCompleted;

-- Share of accounts lost vs share of MRR lost, by plan
WITH ByPlan AS (
  SELECT
    [Plan],
    -- how many accounts churned in this plan
    COUNT(*) AS ChurnedAccounts,
    -- total monthly revenue those churned accounts were paying
    SUM(MRR) AS LostMRR
  FROM vw_StartingBase
  WHERE ChurnedInWindow = 1
  GROUP BY [Plan]
)
SELECT
  [Plan],
  ChurnedAccounts,
  -- this plan's churned accounts / all churned accounts
  100.0 * ChurnedAccounts / SUM(ChurnedAccounts) OVER () AS PctOfChurnedAccounts,
  LostMRR,
  -- this plan's lost MRR / all lost MRR
  100.0 * LostMRR / SUM(LostMRR) OVER () AS PctOfLostMRR
FROM ByPlan
ORDER BY PctOfLostMRR DESC;


-- Phase 6: Risk score and expected loss

-- Churn gap for each warning sign (sets the points)
WITH Signs AS (
  SELECT
    f.Sign,
    f.AtRisk,
    ChurnedInWindow
  FROM vw_StartingBase
  CROSS APPLY (VALUES
    ('OnboardingCompleted',   CASE WHEN OnboardingCompleted = 0 THEN 1 ELSE 0 END),
    ('TrainingSessions',      CASE WHEN TrainingSessions = 0 THEN 1 ELSE 0 END),
    ('DaysToGoLive',          CASE WHEN DaysToGoLive >= 31 THEN 1 ELSE 0 END),
    ('IntegrationsConnected', CASE WHEN IntegrationsConnected <= 1 THEN 1 ELSE 0 END),
    ('SeatUtilizationPct',    CASE WHEN SeatUtilizationPct < 60 THEN 1 ELSE 0 END),
    ('FeatureAdoptionPct',    CASE WHEN FeatureAdoptionPct < 50 THEN 1 ELSE 0 END),
    -- detractor (0-6) or didnt answer
    ('NPS',                   CASE WHEN NPS <= 6 OR NPS IS NULL THEN 1 ELSE 0 END),
    ('EscalatedTickets90d',   CASE WHEN EscalatedTickets90d >= 1 THEN 1 ELSE 0 END)
  ) AS f(Sign, AtRisk)
)
SELECT
  Sign,
  AtRisk,
  COUNT(*) AS Accounts,
  100.0 * SUM(ChurnedInWindow) / COUNT(*) AS ChurnPct
FROM Signs
GROUP BY Sign, AtRisk
ORDER BY Sign, AtRisk;

-- Churn rate % by risk score
WITH Scored AS (
  SELECT
    ChurnedInWindow,
    -- add up the points for every warning sign the account has (0 = healthy, 20 = every sign)
    CASE WHEN OnboardingCompleted = 0 THEN 4 ELSE 0 END
    + CASE WHEN TrainingSessions = 0 THEN 3 ELSE 0 END
    + CASE WHEN SeatUtilizationPct < 60 THEN 3 ELSE 0 END
    + CASE WHEN DaysToGoLive >= 31 THEN 3 ELSE 0 END
    + CASE WHEN IntegrationsConnected <= 1 THEN 2 ELSE 0 END
    + CASE WHEN FeatureAdoptionPct < 50 THEN 2 ELSE 0 END
    + CASE WHEN (NPS <= 6 OR NPS IS NULL) THEN 2 ELSE 0 END
    + CASE WHEN EscalatedTickets90d >= 1 THEN 1 ELSE 0 END AS RiskScore
  FROM vw_StartingBase
)
SELECT
  RiskScore,
  COUNT(*) AS Accounts,
  100.0 * SUM(ChurnedInWindow) / COUNT(*) AS ChurnPct
FROM Scored
GROUP BY RiskScore
ORDER BY RiskScore;

-- Churn rate % by risk tier, last year
-- 11+ is where churn first goes over the 25% goal (score 10 = 21.5%, score 11 = 28.2%)
WITH Scored AS (
  SELECT
    ChurnedInWindow,
    CASE WHEN OnboardingCompleted = 0 THEN 4 ELSE 0 END
    + CASE WHEN TrainingSessions = 0 THEN 3 ELSE 0 END
    + CASE WHEN SeatUtilizationPct < 60 THEN 3 ELSE 0 END
    + CASE WHEN DaysToGoLive >= 31 THEN 3 ELSE 0 END
    + CASE WHEN IntegrationsConnected <= 1 THEN 2 ELSE 0 END
    + CASE WHEN FeatureAdoptionPct < 50 THEN 2 ELSE 0 END
    + CASE WHEN (NPS <= 6 OR NPS IS NULL) THEN 2 ELSE 0 END
    + CASE WHEN EscalatedTickets90d >= 1 THEN 1 ELSE 0 END AS RiskScore
  FROM vw_StartingBase
), Tiered AS (
  SELECT
    ChurnedInWindow,
    CASE
      WHEN RiskScore >= 11 THEN 'At risk'
      ELSE 'Low risk'
    END AS Tier
  FROM Scored
)
SELECT
  Tier,
  COUNT(*) AS Accounts,
  SUM(ChurnedInWindow) AS Churned,
  100.0 * SUM(ChurnedInWindow) / COUNT(*) AS ChurnPct
FROM Tiered
GROUP BY Tier
ORDER BY ChurnPct DESC;

-- Expected loss by risk tier
WITH ScoredLastYear AS (
  -- last year's starting accounts, each with its plan and risk score
  SELECT
    [Plan],
    ChurnedInWindow,
    CASE WHEN OnboardingCompleted = 0 THEN 4 ELSE 0 END
    + CASE WHEN TrainingSessions = 0 THEN 3 ELSE 0 END
    + CASE WHEN SeatUtilizationPct < 60 THEN 3 ELSE 0 END
    + CASE WHEN DaysToGoLive >= 31 THEN 3 ELSE 0 END
    + CASE WHEN IntegrationsConnected <= 1 THEN 2 ELSE 0 END
    + CASE WHEN FeatureAdoptionPct < 50 THEN 2 ELSE 0 END
    + CASE WHEN (NPS <= 6 OR NPS IS NULL) THEN 2 ELSE 0 END
    + CASE WHEN EscalatedTickets90d >= 1 THEN 1 ELSE 0 END AS RiskScore
  FROM vw_startingBase
), Lookup AS (
  -- churn chance (0 to 1) for each plan and score, from all of last year's starting accounts
  -- grouped by plan too, because Enterprise churns about half as much as the mix at the same score
  -- 1.0 * stops integer division from rounding everything to 0
  -- Accounts shows how many accounts each chance is based on (small = unreliable)
  SELECT
    [Plan],
    RiskScore,
    COUNT(*) AS Accounts,
    1.0 * SUM(ChurnedInWindow) / COUNT(*) AS ChurnChance
  FROM ScoredLastYear
  GROUP BY [Plan], RiskScore
), Active AS (
  -- today's customers with their score (same 8 CASE WHENs as above, keep them in sync)
  -- 33,588 rows
  SELECT
    AccountID,
    [Plan],
    MRR,
    CASE WHEN OnboardingCompleted = 0 THEN 4 ELSE 0 END
    + CASE WHEN TrainingSessions = 0 THEN 3 ELSE 0 END
    + CASE WHEN SeatUtilizationPct < 60 THEN 3 ELSE 0 END
    + CASE WHEN DaysToGoLive >= 31 THEN 3 ELSE 0 END
    + CASE WHEN IntegrationsConnected <= 1 THEN 2 ELSE 0 END
    + CASE WHEN FeatureAdoptionPct < 50 THEN 2 ELSE 0 END
    + CASE WHEN (NPS <= 6 OR NPS IS NULL) THEN 2 ELSE 0 END
    + CASE WHEN EscalatedTickets90d >= 1 THEN 1 ELSE 0 END AS RiskScore
  FROM dbo.vw_Accounts
  -- keep accounts that have not churned
  WHERE Churned = 0
), Scored AS (
  -- every active account with its tier and expected loss
  -- each account gets the churn chance for its own plan and score
  -- (joining on score only would match every account to all 3 plans)
  SELECT
    AccountID,
    MRR,
    -- 11+ is where last year's churn first goes over 25% (score 10 = 21.5%, score 11 = 28.2%)
    CASE
      WHEN a.RiskScore >= 11 THEN 'At risk'
      ELSE 'Low risk'
    END AS Tier,
    (MRR * ChurnChance) AS ExpectedLoss
  FROM Active a
  INNER JOIN Lookup l
    ON a.RiskScore = l.RiskScore
    AND a.[Plan] = l.[Plan]
)

-- each tier's share of the total expected loss
-- SUM() OVER () adds up all tiers while keeping one row per tier
SELECT
  Tier,
  COUNT(*) AS Accounts,
  SUM(MRR) AS TotalMRR,
  SUM(ExpectedLoss) AS TotalExpectedLoss,
  100.0 * SUM(ExpectedLoss) / SUM(SUM(ExpectedLoss)) OVER () AS PctOfExpectedLoss
FROM Scored
GROUP BY Tier
ORDER BY TotalExpectedLoss DESC;

-- Every active account with its expected loss (exported for Tableau, which filters the call list to at risk)
WITH ScoredLastYear AS (
  -- last year's starting accounts, each with its plan and risk score
  SELECT
    [Plan],
    ChurnedInWindow,
    CASE WHEN OnboardingCompleted = 0 THEN 4 ELSE 0 END
    + CASE WHEN TrainingSessions = 0 THEN 3 ELSE 0 END
    + CASE WHEN SeatUtilizationPct < 60 THEN 3 ELSE 0 END
    + CASE WHEN DaysToGoLive >= 31 THEN 3 ELSE 0 END
    + CASE WHEN IntegrationsConnected <= 1 THEN 2 ELSE 0 END
    + CASE WHEN FeatureAdoptionPct < 50 THEN 2 ELSE 0 END
    + CASE WHEN (NPS <= 6 OR NPS IS NULL) THEN 2 ELSE 0 END
    + CASE WHEN EscalatedTickets90d >= 1 THEN 1 ELSE 0 END AS RiskScore
  FROM vw_startingBase
), Lookup AS (
  -- churn chance (0 to 1) for each plan and score, from all of last year's starting accounts
  -- 1.0 * stops integer division from rounding everything to 0
  SELECT
    [Plan],
    RiskScore,
    COUNT(*) AS Accounts,
    1.0 * SUM(ChurnedInWindow) / COUNT(*) AS ChurnChance
  FROM ScoredLastYear
  GROUP BY [Plan], RiskScore
), Active AS (
  -- today's customers with their score (same 8 CASE WHENs as above, keep them in sync)
  -- plus CSMAssigned and the 8 drivers for the dashboard tooltip
  -- 33,588 rows
  SELECT
    AccountID,
    [Plan],
    MRR,
    CSMAssigned,
    OnboardingCompleted,
    TrainingSessions,
    SeatUtilizationPct,
    DaysToGoLive,
    IntegrationsConnected,
    FeatureAdoptionPct,
    NPS,
    EscalatedTickets90d,
    CASE WHEN OnboardingCompleted = 0 THEN 4 ELSE 0 END
    + CASE WHEN TrainingSessions = 0 THEN 3 ELSE 0 END
    + CASE WHEN SeatUtilizationPct < 60 THEN 3 ELSE 0 END
    + CASE WHEN DaysToGoLive >= 31 THEN 3 ELSE 0 END
    + CASE WHEN IntegrationsConnected <= 1 THEN 2 ELSE 0 END
    + CASE WHEN FeatureAdoptionPct < 50 THEN 2 ELSE 0 END
    + CASE WHEN (NPS <= 6 OR NPS IS NULL) THEN 2 ELSE 0 END
    + CASE WHEN EscalatedTickets90d >= 1 THEN 1 ELSE 0 END AS RiskScore
  FROM dbo.vw_Accounts
  -- keep accounts that have not churned
  WHERE Churned = 0
), Scored AS (
  -- every active account with its expected loss
  -- each account gets the churn chance for its own plan and score
  -- (joining on score only would match every account to all 3 plans)
  SELECT
    AccountID,
    a.[Plan],
    MRR,
    CSMAssigned,
    OnboardingCompleted,
    TrainingSessions,
    SeatUtilizationPct,
    DaysToGoLive,
    IntegrationsConnected,
    FeatureAdoptionPct,
    NPS,
    EscalatedTickets90d,
    a.RiskScore,
    ChurnChance,
    (MRR * ChurnChance) AS ExpectedLoss
  FROM Active a
  INNER JOIN Lookup l
    ON a.RiskScore = l.RiskScore
    AND a.[Plan] = l.[Plan]
)

-- every active account with its expected loss (for the dashboard)
SELECT *
FROM Scored
ORDER BY ExpectedLoss DESC;

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

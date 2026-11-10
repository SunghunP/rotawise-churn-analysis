import pandas as pd
from extract import extract_sheet_to_dataframe

INT_COLS = ["TenureMonths", "SeatsPurchased", "ActiveSeats", "DiscountPct",
            "DaysToGoLive", "TrainingSessions", "IntegrationsConnected",
            "SupportTickets90d", "EscalatedTickets90d", "LatePayments"]
# Int64 = whole numbers that can have blanks
NULLABLE_INT_COLS = ["EmployeeCount", "DaysSinceCSMContact", "NPS"]
FLOAT_COLS = ["SeatUtilizationPct", "FeatureAdoptionPct"]
DATE_COLS = ["SignupDate", "ChurnDate"]


def transform(df):
    df = df.copy()

    # blanks come in as ''
    df = df.replace("", pd.NA)
    df = df.drop_duplicates()

    df["Industry"] = df["Industry"].str.title().fillna("Unknown")
    df["Plan"] = df["Plan"].str.title()

    # "NA" = North America, not missing
    df["Region"] = df["Region"].replace({
        "NA": "North America",
        "EU": "Europe",
        "Asia-Pacific": "APAC",
        "Latin America": "LATAM",
    })

    # Yes/No to match Tableau
    df["Churned"] = df["Churned"].replace({
        "N": "No",
        "FALSE": "No",
        "Y": "Yes",
        "TRUE": "Yes",
    })

    for col in INT_COLS:
        df[col] = pd.to_numeric(df[col]).astype(int)
    for col in NULLABLE_INT_COLS:
        df[col] = pd.to_numeric(df[col]).astype("Int64")
    for col in FLOAT_COLS:
        df[col] = pd.to_numeric(df[col])

    # impossible values -> missing
    df.loc[(df["EmployeeCount"] <= 0) | (df["EmployeeCount"] == 99999), "EmployeeCount"] = pd.NA
    df.loc[(df["NPS"] < 0) | (df["NPS"] > 10), "NPS"] = pd.NA

    # more active seats than purchased -> cap
    too_many = df["ActiveSeats"] > df["SeatsPurchased"]
    df.loc[too_many, "ActiveSeats"] = df.loc[too_many, "SeatsPurchased"]
    df.loc[too_many, "SeatUtilizationPct"] = 100

    # strip "$" and ",", fill blanks with seats x price per seat x (1 - discount)
    df["MRR"] = pd.to_numeric(df["MRR"].str.replace(r"[$,]", "", regex=True))
    price_per_seat = df["Plan"].map({"Starter": 4, "Pro": 8, "Enterprise": 12})
    calculated_mrr = df["SeatsPurchased"] * price_per_seat * (1 - df["DiscountPct"] / 100)
    df["MRR"] = df["MRR"].fillna(calculated_mrr)

    # two date formats in SignupDate
    for col in DATE_COLS:
        df[col] = pd.to_datetime(df[col], format="mixed")

    return df


if __name__ == "__main__":
    df = transform(extract_sheet_to_dataframe())
    print("Shape:", df.shape)
    print(df.dtypes)

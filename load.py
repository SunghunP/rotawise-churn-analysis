import os
from urllib.parse import quote_plus

from dotenv import load_dotenv
from sqlalchemy import create_engine

from extract import extract_sheet_to_dataframe
from transform import transform

load_dotenv()

SQL_SERVER = os.getenv("SQL_SERVER")
SQL_DATABASE = os.getenv("SQL_DATABASE")
TABLE_NAME = "rotawise_accounts_etl"


def get_engine():
    # Windows login
    driver = quote_plus("ODBC Driver 17 for SQL Server")
    url = f"mssql+pyodbc://@{SQL_SERVER}/{SQL_DATABASE}?driver={driver}&trusted_connection=yes"
    return create_engine(url, fast_executemany=True)


def load(df):
    df.to_sql(
        TABLE_NAME,
        get_engine(),
        if_exists="replace",
        index=False,
        chunksize=1000,
    )
    print(f"Loaded {len(df)} rows into {SQL_DATABASE}.dbo.{TABLE_NAME}")


if __name__ == "__main__":
    raw = extract_sheet_to_dataframe()
    clean = transform(raw)
    load(clean)

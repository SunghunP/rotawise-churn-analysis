import os
import gspread
import pandas as pd
from dotenv import load_dotenv

# load environment variables from .env file
load_dotenv()

SPREADSHEET_NAME = os.getenv("SPREADSHEET_NAME")
GOOGLE_KEY_PATH = os.getenv("GOOGLE_KEY_PATH")


def extract_sheet_to_dataframe():
    gc = gspread.service_account(filename=GOOGLE_KEY_PATH)
    # open the spreadsheet by name
    spreadsheet = gc.open(SPREADSHEET_NAME)
    # pick the first sheet (worksheet) inside it
    wks = spreadsheet.sheet1
    # get every cell as text: a list of lists, first list = header
    values = wks.get_all_values()
    header = values[0]   # first list = column names
    rows = values[1:]    # every list after the first = data rows
    # build the DataFrame with the header as column names
    df = pd.DataFrame(rows, columns=header)

    return df

# Display the DataFrame
if __name__ == "__main__":
    df = extract_sheet_to_dataframe()
    print('dtypes: ', df.dtypes)
    print('Shape: ', df.shape)
    print('Head: ', df.head(5))


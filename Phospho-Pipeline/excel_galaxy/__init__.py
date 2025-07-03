import os
from io import BytesIO
import pandas as pd

def read_excel(file):
    try:
        with open(file, 'rb') as f:
            excel_data = BytesIO(f.read())
        return pd.read_excel(excel_data, engine='openpyxl') 
    except Exception as e:
        print(f"Erreur lors de la lecture du fichier Excel : {e}")
        exit()

def write_excel(df, file):
    if file.endswith('.xlsx'):
        df.to_excel(file, index=False, engine='openpyxl')
    else:
        temp_xlsx_file = file + ".xlsx"
        df.to_excel(temp_xlsx_file, index=False, engine='openpyxl')
        os.rename(temp_xlsx_file, file)

def add_sheet(df, file, sheet_name):
    if file.endswith('.xlsx'):
        with pd.ExcelWriter(file, engine='openpyxl', mode='a') as writer:
            df.to_excel(writer, sheet_name=sheet_name, index=False)
    else:
        temp_xlsx_file = file + ".xlsx"
        os.rename(file, temp_xlsx_file) 
        with pd.ExcelWriter(temp_xlsx_file, engine='openpyxl', mode='a') as writer:
            df.to_excel(writer, sheet_name=sheet_name, index=False)
        os.rename(temp_xlsx_file, file) 
    print(f"Les résultats ont été ajoutés dans '{file}' sous la feuille '{sheet_name}'.")    

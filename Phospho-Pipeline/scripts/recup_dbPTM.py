# -*- coding: utf-8 -*-
"""
Created on Thu Jun  5 13:01:21 2025

@author: Brunel.Leo-Paul
"""

import requests
from bs4 import BeautifulSoup
import pandas as pd
import os
import json
import excel_galaxy

def site_table(input_excel):
    # Charger le fichier Excel contenant la liste des protéines
    df = excel_galaxy.read_excel(input_excel)
    protein_list = list(dict.fromkeys(df['Protein_Name']))  # Éviter les doublons
    
    # Fichier JSON de sauvegarde
    json_path = "dbPTM.json"
    
    # Charger les données déjà existantes si disponibles
    if os.path.exists(json_path):
        with open(json_path, "r", encoding="utf-8") as json_file:
            site_data = json.load(json_file)
            print(f"{len(site_data)} protéines déjà traitées chargées.")
    else:
        site_data = {}
    
    # Set pour suivre les IDs déjà traités
    processed_ids = set(site_data.keys())
    
    # Fonction pour extraire les données des tableaux
    def extract_table_data(table):
        rows = table.find_all('tr')[1:]  # Ignorer l'en-tête
        data = []
        for row in rows:
            cells = row.find_all('td')
            data.append([cell.get_text(strip=True) for cell in cells])
        return data

    # Fonction pour récupérer les informations de dbPTM
    def fetch_data_from_dbptm(uniprot_id):
        url = f"https://biomics.lab.nycu.edu.tw/dbPTM/info.php?id={uniprot_id}"

        # Effectuer une requête GET pour obtenir la page HTML
        response = requests.get(url)
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # Extraire les sections 'upstream' et 'description'
        upstream_section = soup.find('div', id='upstream')
        description_section = soup.find('div', id='description')

        # Extraire les tableaux de chaque section
        upstream_table = upstream_section.find('table') if upstream_section else None
        description_table = description_section.find('table') if description_section else None

        # Extraire les données des tableaux
        upstream_data = extract_table_data(upstream_table) if upstream_table else []
        description_data = extract_table_data(description_table) if description_table else []

        return {
            'upstream': upstream_data,
            'description': description_data
        }

    # Parcours des protéines
    for idx, uniprot_id in enumerate(protein_list):
        if uniprot_id in processed_ids:
            continue  # Sauter si déjà traité
        
        print(f"Récupération des données pour {uniprot_id}...")
        
        # Récupérer les données pour la protéine
        data = fetch_data_from_dbptm(uniprot_id)
        
        # Enregistrer les données dans le dictionnaire
        site_data[uniprot_id] = data
        
        # Sauvegarder le fichier JSON après chaque ajout
        with open(json_path, "w", encoding="utf-8") as json_file:
            json.dump(site_data, json_file, indent=4, ensure_ascii=False)
        
        print(f"Données pour {uniprot_id} enregistrées.")

    print(f"{len(site_data)} protéines traitées et sauvegardées dans '{json_path}'.")



# -*- coding: utf-8 -*-
"""
Created on Tue Apr 22 14:16:23 2025

@author: Brunel.Leo-paul
"""

import requests
from bs4 import BeautifulSoup
import pandas as pd
import json
import time
import os


def downstream(file_path):
    # Charger le fichier Excel
    
    df = pd.read_excel(file_path, engine='openpyxl')
    
    # Liste des IDs de protéines sans doublons, ordre conservé
    protein_list = list(dict.fromkeys(df['sseqid']))
    
    # Fichier de sauvegarde
    json_path = "protein_data_downstream_test.json"
    
    # Charger les données déjà existantes si disponibles
    if os.path.exists(json_path):
        with open(json_path, "r", encoding="utf-8") as json_file:
            downstream_data = json.load(json_file)
            print(f"✅ {len(downstream_data)} protéines déjà traitées chargées.")
    else:
        downstream_data = {}
    
    # Set des IDs déjà traités
    processed_ids = set(downstream_data.keys())
    
    # Traitement
    for idx, uniprot_id in enumerate(protein_list):
        if uniprot_id in processed_ids:
            continue  
    
        print(f"\n🔄 {idx+1}/{len(protein_list)} - Traitement de : {uniprot_id}")
        
        attempt = 0
        while attempt < 5:  
            try:
                url = f"https://www.phosphosite.org/uniprotAccAction?id={uniprot_id}&showAllSites=true"
                response = requests.get(url)
    
                if response.status_code == 429:
                    print(" Erreur HTTP 429 : trop de requêtes. Pause de 2 minutes...")
                    time.sleep(120)  
                    attempt += 1
                    continue  
                elif response.status_code != 200:
                    print(f" Erreur HTTP {response.status_code}")
                    break
    
                soup = BeautifulSoup(response.text, 'html.parser')
                site_link = soup.find('a', href=lambda href: href and href.startswith("../downstream"))
                
                if not site_link:
                    print(" Aucun lien downstream trouvé")
                    downstream_data[uniprot_id] = []
                    break
    
                href_url = site_link['href'].lstrip('../')
                full_url = f"https://www.phosphosite.org/{href_url}"
                response = requests.get(full_url)
    
                if response.status_code == 429:
                    print(" Erreur HTTP 429 (downstream) : pause de 2 minutes...")
                    time.sleep(120)
                    attempt += 1
                    continue
                elif response.status_code != 200:
                    print(f" Erreur HTTP pour la page downstream : {response.status_code}")
                    break
    
                soup = BeautifulSoup(response.text, 'html.parser')
                data = []
                tables = soup.find_all('table')
    
                if not tables:
                    print(" Pas de tableau trouvé")
                    downstream_data[uniprot_id] = []
                    break
    
                for table in tables:
                    tbody = table.find('tbody')
                    if tbody:
                        for tr in tbody.find_all('tr'):
                            td_list = tr.find_all('td')
                            if len(td_list) == 2:
                                downstream_protein = td_list[0].get_text(strip=True)
                                phosphosite = td_list[1].get_text(strip=True).split(',')
                                data.append({
                                    "effect": downstream_protein,
                                    "phosphosite": phosphosite
                                })
    
                downstream_data[uniprot_id] = data
                print(f" Données récupérées pour {uniprot_id} : {len(data)} entrées")
    
                # Sauvegarde automatique après chaque protéine
                with open(json_path, mode="w", encoding="utf-8") as json_file:
                    json.dump(downstream_data, json_file, ensure_ascii=False, indent=4)
    
                # Pause pour éviter les erreurs 429
                time.sleep(5)
                break
    
            except Exception as e:
                print(f" Exception pour {uniprot_id} : {str(e)}")
                break  # Sortir de la boucle en cas d'exception
        else:
            print(f" Trop d'essais pour {uniprot_id}, passage à la protéine suivante.")
    
    print("\n Données sauvegardées dans le fichier JSON.")

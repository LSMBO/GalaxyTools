# -*- coding: utf-8 -*-
"""
Created on Wed Apr 23 13:16:42 2025

@author: Brunel.Leo-paul
"""

import requests
from bs4 import BeautifulSoup
import json
import time
import os
import pandas as pd
import excel_galaxy


def site_table(file_path):
    # Chargement des identifiants de protéines depuis le fichier Excel
    df = excel_galaxy.read_excel(file_path)
    protein_list = list(dict.fromkeys(df['sseqid']))  # Évite les doublons
    
    # Fichier JSON de sauvegarde
    json_path = "site_data.json"
    
    # Charger les données déjà existantes si disponibles
    if os.path.exists(json_path):
        with open(json_path, "r", encoding="utf-8") as json_file:
            site_data = json.load(json_file)
            print(f" {len(site_data)} protéines déjà traitées chargées.")
    else:
        site_data = {}
    
    # Set pour suivre les IDs déjà traités
    processed_ids = set(site_data.keys())
    
    # Parcours des protéines
    for idx, uniprot_id in enumerate(protein_list):
        if uniprot_id in processed_ids:
            continue  # Sauter si déjà traité
    
        print(f"\n {idx+1}/{len(protein_list)} - Traitement de : {uniprot_id}")
        
        attempt = 0
        while attempt < 5:
            try:
                # Accès à la page principale de la protéine
                url = f"https://www.phosphosite.org/uniprotAccAction?id={uniprot_id}&showAllSites=true"
                response = requests.get(url)
    
                if response.status_code == 429:
                    print("  Erreur 429 : trop de requêtes. Pause de 2 minutes...")
                    time.sleep(120)
                    attempt += 1
                    continue
                elif response.status_code != 200:
                    print(f"  Erreur HTTP {response.status_code}")
                    break
    
                soup = BeautifulSoup(response.text, 'html.parser')
                site_link = soup.find('a', href=lambda href: href and 'siteTable' in href)
                
                if not site_link:
                    print(" Aucun lien vers siteTable trouvé.")
                    site_data[uniprot_id] = []
                    break
    
                href_url = site_link['href'].lstrip('../')
                full_url = f"https://www.phosphosite.org/{href_url}"
                response = requests.get(full_url)
    
                if response.status_code == 429:
                    print("  Erreur 429 (siteTable) : pause de 2 minutes...")
                    time.sleep(120)
                    attempt += 1
                    continue
                elif response.status_code != 200:
                    print(f"  Erreur HTTP sur siteTable : {response.status_code}")
                    break
    
                soup = BeautifulSoup(response.text, 'html.parser')
                tables = soup.find_all('table')
    
                site_list = []
                for table in tables:
                    tbody = table.find('tbody')
                    if tbody:
                        for tr in tbody.find_all('tr'):
                            td_list = tr.find_all('td')
                            if len(td_list) >= 2:
                                site = td_list[0].get_text(strip=True)
                                sequences = td_list[1].get_text(strip=True)
                                site_list.append({
                                    "site": site,
                                    "sequences": sequences
                                })
    
                site_data[uniprot_id] = site_list
                print(f"  Données récupérées : {len(site_list)} sites")
    
                # Sauvegarde automatique après chaque protéine
                with open(json_path, "w", encoding="utf-8") as json_file:
                    json.dump(site_data, json_file, ensure_ascii=False, indent=4)
    
                time.sleep(5)  # Pause pour limiter les risques de blocage
                break
    
            except Exception as e:
                print(f"  Exception pour {uniprot_id} : {str(e)}")
                break  # Quitte la boucle de tentative si exception non HTTP
    
        else:
            print(f"  Trop d'échecs pour {uniprot_id}, passage au suivant.")
    
    print("\n Sauvegarde finale terminée.")








import json
def tri_site_table():
    # Charger les données JSON existantes
    with open("site_data.json", "r") as json_file:
        phospho_data = json.load(json_file)
    
    # Nouveau dictionnaire pour stocker les données filtrées
    filtered_phospho_data = {}
    
    # Parcourir chaque protéine dans le fichier JSON
    for uniprot_id, sites in phospho_data.items():
        filtered_sites = []
        
        # Parcourir chaque site associé à la protéine
        for site_info in sites:
            site = site_info.get("site", "")
            sequence = site_info.get("sequences", "")
            
            # Filtrer les sites commençant par 'p', 'y' ou 's' et ne dépassant pas 15 caractères
            if site.lower().startswith(('t', 'y', 's')) and len(site) <= 15 and not any(animal in site.lower() for animal in ['cow', 'human', 'mouse','rat']):
                filtered_sites.append({
                    "site": site,
                    "sequences": sequence
                })
        
        # Si des sites filtrés ont été trouvés, les ajouter dans le dictionnaire final
        if filtered_sites:
            filtered_phospho_data[uniprot_id] = filtered_sites
    
    # Sauvegarde des données filtrées dans un nouveau fichier JSON
    with open("filtered_phospho_data.json", "w") as json_file:
        json.dump(filtered_phospho_data, json_file, indent=4)
    
    print("Filtrage terminé. Les données sont sauvegardées dans 'site_data_test.json'.")
    
   



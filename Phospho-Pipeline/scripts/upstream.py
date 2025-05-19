# -*- coding: utf-8 -*-
"""
Created on Thu Feb 27 09:43:08 2025

@author: Brunel.Leo-paul
"""








# soup = BeautifulSoup(response.text, 'html.parser'), soup est un objet qui permet de naviguer dans le HTML
# 2 méthodes permettent de manipuler soup et de presque tout faire
# soup.find_all(balise) permet de lister toutes balises de type <balise> de l'objet HTML
# soup.get_text(strip=True) permet de récupérer le texte de l'objet HTML




                
# Le HTML est organisé en tableau avec des balises <table>
# Chaque <table> a un <thead> qui contient le titre et parfois une description
# Chaque <table> a aussi un <tbody> qui contient plusieurs <tr>
# Chaque <tr> correspond à une ligne du tableau, on a toujours 2 colonnes (<td>) dans un <tr>
# La première colonne contient le nom de la protéine upstream et la deuxième colonne contient le(s) phosphosite(s)
# Ici dans Upstream on voit les protéines qui phosphoryle la protéines uniprot
# On a aussi Downstream qui est l'inverse, les phosphorylation induise une réponse sur d'autres protéines
                
import requests
from bs4 import BeautifulSoup
import pandas as pd
import json
import time
import os



def upstream(file_path):
    # Charger le fichier Excel
    
    df = pd.read_excel(file_path)
    
    # Liste des IDs de protéines sans doublons, ordre conservé
    protein_list = list(dict.fromkeys(df['sseqid']))
    
    # Fichier de sauvegarde
    json_path = "data/protein_data_upstream_test.json"
    
    # Charger les données déjà existantes si disponibles
    if os.path.exists(json_path):
        with open(json_path, "r", encoding="utf-8") as json_file:
            upstream_data = json.load(json_file)
            print(f"✅ {len(upstream_data)} protéines déjà traitées chargées.")
    else:
        upstream_data = {}
    
    # Set des IDs déjà traités
    processed_ids = set(upstream_data.keys())
    
    # Traitement
    for idx, uniprot_id in enumerate(protein_list):
        if uniprot_id in processed_ids:
            continue  # Déjà traité
    
        print(f"\n🔄 {idx+1}/{len(protein_list)} - Traitement de : {uniprot_id}")
        
        attempt = 0
        while attempt < 5:  # Tentatives max
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
                site_link = soup.find('a', href=lambda href: href and href.startswith("../upstream"))
                
                if not site_link:
                    print(" Aucun lien upstream trouvé")
                    upstream_data[uniprot_id] = []
                    break
    
                href_url = site_link['href'].lstrip('../')
                full_url = f"https://www.phosphosite.org/{href_url}"
                response = requests.get(full_url)
    
                if response.status_code == 429:
                    print(" Erreur HTTP 429 (upstream) : pause de 2 minutes...")
                    time.sleep(120)
                    attempt += 1
                    continue
                elif response.status_code != 200:
                    print(f" Erreur HTTP pour la page upstream : {response.status_code}")
                    break
    
                soup = BeautifulSoup(response.text, 'html.parser')
                data = []
                tables = soup.find_all('table')
    
                if not tables:
                    print(" Pas de tableau trouvé")
                    upstream_data[uniprot_id] = []
                    break
    
                for table in tables:
                    tbody = table.find('tbody')
                    if tbody:
                        for tr in tbody.find_all('tr'):
                            td_list = tr.find_all('td')
                            if len(td_list) == 2:
                                upstream_protein = td_list[0].get_text(strip=True)
                                phosphosite = td_list[1].get_text(strip=True).split(',')
                                data.append({
                                    "effect": upstream_protein,
                                    "phosphosite": phosphosite
                                })
    
                upstream_data[uniprot_id] = data
                print(f" Données récupérées pour {uniprot_id} : {len(data)} entrées")
    
                # Sauvegarde automatique après chaque protéine
                with open(json_path, mode="w", encoding="utf-8") as json_file:
                    json.dump(upstream_data, json_file, ensure_ascii=False, indent=4)
    
                # Pause pour éviter les erreurs 429
                time.sleep(5)
                break
    
            except Exception as e:
                print(f" Exception pour {uniprot_id} : {str(e)}")
                break  # Sortir de la boucle en cas d'exception
        else:
            print(f" Trop d'essais pour {uniprot_id}, passage à la protéine suivante.")
    
    print("\n Données sauvegardées dans le fichier JSON.")
    
    
    
    
    
    

































































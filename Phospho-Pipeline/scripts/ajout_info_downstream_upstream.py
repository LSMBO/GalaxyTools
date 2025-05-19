# -*- coding: utf-8 -*-
"""
Created on Mon Mar 17 09:45:40 2025

@author: Brunel.Leo-paul
"""


import pandas as pd
import json
import re
def ajout_info(blast_results_file,):
    # Charger le fichier Excel
    
    blast_df = pd.read_excel(blast_results_file)
    
    # Charger les fichiers JSON
    with open("data/protein_data_downstream.json", "r") as f:
        downstream_data = json.load(f)
    
    with open("data/protein_data_upstream.json", "r") as f:
        upstream_data = json.load(f)
    
    # Initialiser les colonnes pour les informations à ajouter
    blast_df['downstream_info'] = ""
    blast_df['upstream_info'] = ""
    
    # Fonction pour extraire le numéro de position (ex : "S202-p" ou "S1041" → "202" ou "1041")
    def extract_position(site_str):
        match = re.search(r'\d+', str(site_str))
        return match.group() if match else None
    
    # Parcourir les lignes du fichier Excel
    for idx, row in blast_df.iterrows():
        prot_id = row['sseqid']  # Nom de la protéine dans la colonne 'sseqid'
        matching_site = row['Matching Site']  # Site phospho à rechercher
        site_pos = extract_position(matching_site)  # Extraire la position du site (ex: "202" ou "1041")
        
        # Initialiser les informations downstream et upstream
        relevant_downstream = []
        relevant_upstream = []
        
        # Récupérer les informations DOWNSTREAM pour la bonne protéine et le bon site
        if prot_id in downstream_data:  # Vérifier si la protéine existe dans les données downstream
            for entry in downstream_data[prot_id]:
                for site in entry.get('phosphosite', []):  # Sites associés à cette protéine
                    if extract_position(site) == site_pos:  # Vérifier si le site correspond à la position
                        effect = entry.get('effect', 'N/A')
                        relevant_downstream.append(f"Effect: {effect}, Phosphosite: {site}")
                        break  # On prend une seule entrée par correspondance pour ce site
    
        blast_df.at[idx, 'downstream_info'] = "; ".join(relevant_downstream) if relevant_downstream else "No downstream info"
    
        # Récupérer les informations UPSTREAM pour la bonne protéine et le bon site
        if prot_id in upstream_data:  # Vérifier si la protéine existe dans les données upstream
            for entry in upstream_data[prot_id]:
                for site in entry.get('upstream_phosphosite', []):  # Sites associés à cette protéine
                    if extract_position(site) == site_pos:  # Vérifier si le site correspond à la position
                        protein = entry.get('upstream_protein', 'N/A')
                        relevant_upstream.append(f"Upstream protein: {protein}, Phosphosite: {site}")
                        break  # On prend une seule entrée par correspondance pour ce site
    
        blast_df.at[idx, 'upstream_info'] = "; ".join(relevant_upstream) if relevant_upstream else "No upstream info"
    
    # Sauvegarder dans un nouveau fichier Excel mis à jour
    
    blast_df.to_excel(blast_results_file, index=False)
    
    print(f"✅ Infos downstream/upstream récupérées pour la bonne protéine et site, sauvegardées dans {blast_results_file}")
    






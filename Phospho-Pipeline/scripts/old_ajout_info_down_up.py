# -*- coding: utf-8 -*-
"""
Created on Mon Apr 28 15:49:25 2025

@author: Brunel.Leo-paul
"""

import pandas as pd
import json

# Charger le fichier Excel
blast_results_file = "data/updated_blast_result_final_with_sites.xlsx"
blast_df = pd.read_excel(blast_results_file)

# Charger les fichiers JSON
with open("data/downstream_data.json", "r") as f:
    downstream_data = json.load(f)

with open("data/protein_data_upstream.json", "r") as f:
    upstream_data = json.load(f)

# Initialiser des colonnes vides pour les informations que l'on va ajouter
blast_df['downstream_info'] = ""
blast_df['upstream_info'] = ""

# Parcourir les lignes du fichier Excel
for idx, row in blast_df.iterrows():
    prot_id = row['sseqid']
    
    # Récupérer les informations depuis downstream_data si disponibles
    downstream_info = downstream_data.get(prot_id, [])
    downstream_effects = []
    downstream_phosphosites = []
    
    # Extraire les informations si présentes dans downstream_data
    if downstream_info:
        for entry in downstream_info:
            effect = entry.get('effect', 'N/A')
            phosphosites = ", ".join(entry.get('phosphosite', []))
            downstream_effects.append(f"Effect: {effect}, Phosphosites: {phosphosites}")
    
    # Ajouter l'information dans la colonne 'downstream_info'
    if downstream_effects:
        blast_df.at[idx, 'downstream_info'] = "; ".join(downstream_effects)
    else:
        blast_df.at[idx, 'downstream_info'] = "No downstream info"

    # Récupérer les informations depuis upstream_data si disponibles
    upstream_info = upstream_data.get(prot_id, [])
    upstream_proteins = []
    upstream_phosphosites = []
    
    # Extraire les informations si présentes dans upstream_data
    if upstream_info:
        for entry in upstream_info:
            protein = entry.get('upstream_protein', 'N/A')
            phosphosites = ", ".join(entry.get('upstream_phosphosite', []))
            upstream_proteins.append(f"Upstream protein: {protein}, Phosphosites: {phosphosites}")
    
    # Ajouter l'information dans la colonne 'upstream_info'
    if upstream_proteins:
        blast_df.at[idx, 'upstream_info'] = "; ".join(upstream_proteins)
    else:
        blast_df.at[idx, 'upstream_info'] = "No upstream info"

# Sauvegarder le fichier Excel mis à jour
updated_blast_results_file = "data/updated_blast_result_final_with_sites.xlsx"
blast_df.to_excel(updated_blast_results_file, index=False)

print(f"Résultats mis à jour et sauvegardés dans {updated_blast_results_file}")

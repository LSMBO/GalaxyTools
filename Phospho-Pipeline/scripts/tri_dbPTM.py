# -*- coding: utf-8 -*-
"""
Created on Fri Jun  6 09:52:09 2025

@author: Brunel.Leo-Paul
"""

import pandas as pd
import json

def process_matching_sites(input_excel, output_excel, json_path='dbPTM.json'):
    """
    Fonction pour traiter les sites de phosphorylation dans un fichier Excel et ajouter les résultats dans un fichier Excel existant.
    
    :param input_excel: Chemin du fichier Excel contenant les données de Matching Sites
    :param json_path: Chemin du fichier JSON contenant les informations extraites de dbPTM
    :param output_excel: Chemin du fichier Excel de sortie
    """
    # Charger le fichier Excel contenant les Matching Site
    df = pd.read_excel(input_excel, engine='openpyxl')

    # Charger le fichier JSON contenant les informations extraites de dbPTM
    with open(json_path, 'r', encoding='utf-8') as json_file:
        site_data = json.load(json_file)

    # Fonction pour normaliser le format du site de phosphorylation pour la comparaison
    def normalize_site_format(matching_site):
        """ Normalise le format du site de phosphorylation dans le format 'Sxxx-p' """
        if isinstance(matching_site, float):
            matching_site = str(matching_site) if not pd.isna(matching_site) else ""
        if matching_site == "":
            return None
        aa_pos, modification = matching_site[:-2], matching_site[-2:]
        return f"{aa_pos}{modification}"

    # Fonction pour récupérer les informations des kinases et des descriptions pour un Matching Site donné
    def get_kinase_and_description(protein_name, matching_site):
        kinase_info = []
        description_info = []
        matching_site_normalized = normalize_site_format(matching_site)
        if not matching_site_normalized:
            return kinase_info, description_info

        if protein_name in site_data:
            protein_data = site_data[protein_name]

            # Rechercher dans la section 'upstream' les informations sur les kinases
            if 'upstream' in protein_data:
                for site in protein_data['upstream']:
                    if len(site) >= 7:
                        position, aa_modified, _, _, kinase, kinase_id, source = site[:7]
                        json_site_normalized = f"{aa_modified}{position}-p"
                        if matching_site_normalized == json_site_normalized:
                            kinase_info.append({
                                'Kinase': kinase,
                                'Kinase_ID': kinase_id,
                                'Source': source
                            })

            # Rechercher dans la section 'description' les informations descriptives
            if 'description' in protein_data:
                for i in range(0, len(protein_data['description']), 2):
                    description_data = protein_data['description'][i]
                    if len(description_data) >= 5:
                        effect, aa_modified, modification_type, _, _ = description_data[:5]
                        effect_text = protein_data['description'][i+1][0] if i+1 < len(protein_data['description']) and len(protein_data['description'][i+1]) > 0 else ""
                        json_site_normalized = f"{aa_modified}{description_data[0]}-p"
                        if matching_site_normalized == json_site_normalized:
                            description_info.append({
                                'Effect': effect,
                                'Text': effect_text
                            })

        return kinase_info, description_info

    # Créer des listes pour stocker les résultats
    kinase_results = []
    description_results = []

    # Parcourir chaque ligne du fichier Excel
    for idx, row in df.iterrows():
        matching_site = row['Matching Site']
        protein_name = row['Protein_Name']

        # Récupérer les informations de kinase et description
        kinases, descriptions = get_kinase_and_description(protein_name, matching_site)

        # Ajouter les résultats dans les listes
        if kinases:
            kinase_results.append({
                'Protein_Name': protein_name,
                'Matching_Site': matching_site,
                'Kinases': kinases
            })
        if descriptions:
            description_results.append({
                'Protein_Name': protein_name,
                'Matching_Site': matching_site,
                'Descriptions': descriptions
            })

    # Créer des DataFrames à partir des résultats
    kinase_df = pd.DataFrame(kinase_results)
    description_df = pd.DataFrame(description_results)

    # Ouvrir le fichier Excel existant et ajouter les nouvelles feuilles sans effacer les anciennes
    with pd.ExcelWriter(output_excel, engine='openpyxl', mode='a') as writer:
        # Ajouter les nouvelles feuilles
        kinase_df.to_excel(writer, sheet_name='Kinases', index=False)
        description_df.to_excel(writer, sheet_name='Descriptions', index=False)

    print("Les résultats ont été ajoutés dans '{}'.".format(output_excel))

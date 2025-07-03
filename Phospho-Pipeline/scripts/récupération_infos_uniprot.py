# -*- coding: utf-8 -*-
"""
Created on Tue Jun 24 10:13:01 2025

@author: Brunel.Leo-Paul
"""

import requests
import pandas as pd
import excel_galaxy

def get_post_translational_modifications(protein_ids, input_excel, output_sheet='Infos_uniprot'):
    """
    Utilise l'API REST UniProt pour récupérer les modifications post-traductionnelles (PTM) pour une liste d'identifiants UniProt.
    
    :param protein_ids: Liste des identifiants UniProtKB.
    :param input_excel: Chemin du fichier Excel contenant les données de protéines.
    :param output_sheet: Nom de la feuille Excel dans laquelle les résultats seront ajoutés.
    :return: DataFrame avec les modifications post-traductionnelles.
    """
    base_url = "https://rest.uniprot.org/uniprotkb/"
    results = []

    # Pour chaque identifiant de protéine, effectuer l'appel API
    for protein_id in protein_ids:
        url = f"{base_url}{protein_id}?format=json"
        
        response = requests.get(url)

        if response.status_code == 200:
            data = response.json()

            # Extraire les informations sur les modifications post-traductionnelles (PTM)
            comments = data.get("comments", [])
            ptm_info = []
            for comment in comments:
                if comment.get("commentType", "") == "PTM":
                    for text in comment.get("texts", []):
                        ptm_info.append(text.get("value", ""))  # Ajouter chaque "value" dans ptm_info

            # Ajouter les résultats au tableau
            results.append({
                "Protein Accession": protein_id,
                "Post-translational Modifications": "\n".join(ptm_info) if ptm_info else "Aucune modification post-traductionnelle trouvée."
            })
        else:
            print(f"Erreur lors de l'appel API pour {protein_id}: {response.status_code}")

    # Convertir les résultats en DataFrame pandas
    df = pd.DataFrame(results)

    # Lire le fichier Excel contenant la colonne sseqid
    existing_df = excel_galaxy.read_excel(input_excel)

    # Extraire les identifiants sseqid
    protein_ids_from_excel = existing_df['sseqid'].dropna().unique().tolist()  # Récupérer les IDs de la colonne sseqid

    # Vérifier si on a les mêmes identifiants et ajouter les résultats dans la feuille Excel
    if set(protein_ids) == set(protein_ids_from_excel):
        excel_galaxy.add_sheet(df, input_excel, output_sheet)

    return df

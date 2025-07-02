# -*- coding: utf-8 -*-
"""
Created on Thu Jun  5 14:06:30 2025

@author: Brunel.Leo-Paul
"""

import pandas as pd

def get_protein_name_from_fasta(uniprot_id, fasta_file):
    """
    Extrait le nom de la protéine à partir de l'ID UniProt en utilisant un fichier FASTA.
    
    :param uniprot_id: ID UniProt de la protéine
    :param fasta_file: Chemin du fichier FASTA
    :return: Nom de la protéine ou None si non trouvé
    """
    with open(fasta_file, 'r') as fasta_file:
        for line in fasta_file:
            if uniprot_id in line:
                # Exemple : >sp|A0A087X1C5|CP2D7_HUMAN ...
                parts = line.split('|')
                if len(parts) > 2:
                    protein_name = parts[2]  # Exemple "CP2D7_HUMAN"
                    protein_name = protein_name.split(' ')[0]  # On garde la partie avant l'espace
                    return protein_name
    return None  # Si l'ID UniProt n'est pas trouvé

def add_protein_names_to_excel(input_excel, fasta_file, output_excel):
    """
    Ajoute une nouvelle colonne avec les noms de protéines extraits d'un fichier FASTA à un fichier Excel.
    
    :param input_excel: Chemin du fichier Excel d'entrée contenant les IDs UniProt
    :param fasta_file: Chemin du fichier FASTA pour extraire les noms de protéines
    :param output_excel: Chemin du fichier Excel de sortie
    """
    # Charger le fichier Excel contenant les IDs UniProt
    df = pd.read_excel(input_excel, engine='openpyxl')

    # Créer une nouvelle colonne dans le DataFrame pour les noms de protéines
    df['Protein_Name'] = df['sseqid'].apply(lambda x: get_protein_name_from_fasta(x, fasta_file))

    # Sauvegarder les résultats dans un nouveau fichier Excel
    df.to_excel(output_excel, index=False)

    print(f"Les résultats ont été enregistrés dans '{output_excel}'.")

# Exemple d'appel de la fonction depuis le fichier principal
if __name__ == "__main__":
    # Fichiers d'entrée et de sortie
    input_excel = "data/fichier_final.xlsx"
    fasta_file = "data/prot_humaine.fasta"
    output_excel = "data/résultat_dbPTM.xlsx"

    # Appeler la fonction pour ajouter les noms de protéines au fichier Excel
    add_protein_names_to_excel(input_excel, fasta_file, output_excel)

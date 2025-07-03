# -*- coding: utf-8 -*-
"""
Created on Tue Feb  4 09:43:04 2025

@author: brunel.leo-paul
"""
from Bio import SeqIO
import pandas as pd
import excel_galaxy

# Fonction pour récupérer la séquence d'une protéine à partir de son identifiant dans un fichier FASTA
def fetch_protein_sequence_from_fasta(protein_name, fasta_file):
    try:
        for record in SeqIO.parse(fasta_file, "fasta"):
            fasta_protein_id = record.id.split()[0]  
            if protein_name == fasta_protein_id:
                return str(record.seq)
        return "Protéine non trouvée"
    except Exception as e:
        print(f"Erreur lors de la récupération de la séquence pour {protein_name}: {e}")
        return "Erreur"

# Fonction pour détecter et définir la ligne d'en-tête
def find_column_header(df, column_name):
    for i in range(min(10, len(df))):  
        if column_name in df.iloc[i].values:
            df.columns = df.iloc[i]  
            return df[i+1:] 
    raise ValueError(f"Colonne '{column_name}' non trouvée.")

# Programme principal
def main():
    input_excel = "data/File_phospho_for_leo.xlsx"
    fasta_file = "data/nouveau_sequences_ours.fasta"
    output_csv = "data/protein_sequences.csv"

    df = excel_galaxy.read_excel(input_excel)
    try:
        df = find_column_header(df, "Protein")  
    except Exception as e:
        print(f"Erreur lors de la lecture du fichier Excel : {e}")
        return

   

    
    protein_list = df["Protein"].tolist()

    protein_data = []
    for protein in protein_list:
        sequence = fetch_protein_sequence_from_fasta(protein, fasta_file)
        protein_data.append([protein, sequence])

    # Sauvegarder dans un fichier CSV
    output_df = pd.DataFrame(protein_data, columns=["Identifiant", "Sequence"])
    output_df.to_csv(output_csv, index=False)
    print(f"Les résultats ont été enregistrés dans {output_csv}")

if __name__ == "__main__":
    main()


# -*- coding: utf-8 -*-
"""
Created on Mon Apr 28 14:26:30 2025

@author: Brunel.Leo-paul
"""
import sys
import pandas as pd
import scripts.récupération_séquence as recuperation_sequence
import scripts.blast_local as blast_local
import scripts.site_table as site_table 
import scripts.upstream as upstream
import scripts.downstream as downstream
import scripts.alignement as alignement 
import scripts.ajout_info_downstream_upstream as ajout_info_down_up

input_excel = sys.argv[1]
output_excel = sys.argv[2]
output_csv = sys.argv[3]

if len(sys.argv) > 4:
    fasta_file_bear = sys.argv[4]
else:
    fasta_file_bear = "nouveau_sequences_ours.fasta" 

#input_excel = "data/File_phospho_for_leo_reduit.xlsx"
#output_excel = "data/blast_result_final_test.xlsx"
#output_csv = "data/protein_sequences.csv"


temp_excel = "data/blast_result_temp.xlsx"

try:
    df = pd.read_excel(input_excel) 
except Exception as e:
    print(f"Erreur lors de la lecture du fichier Excel : {e}")
    exit()



protein_list = df["Protein"].tolist()

protein_data = []
for protein in protein_list:
    sequence = recuperation_sequence.fetch_protein_sequence_from_fasta(protein, fasta_file_bear)
    protein_data.append([protein, sequence])

# Sauvegarder dans un fichier CSV
output_df = pd.DataFrame(protein_data, columns=["Identifiant", "Sequence"])
output_df.to_csv(output_csv, index=False)
print(f"Les résultats ont été enregistrés dans {output_csv}")



## Blast local 
fasta_file_humain = "data/prot_humaine.fasta"
blast_local.run_blast_analysis(output_csv, fasta_file_humain, temp_excel)


blast_local.add_sequences_to_blast_results(temp_excel,fasta_file_humain, output_csv)




# Charger les fichiers

blast_df = pd.read_excel(temp_excel)



df = df[["Position", "Peptide sequence"]]

if len(blast_df) != len(df):
    print(f"⚠️ Attention : le nombre de lignes ne correspond pas ({len(blast_df)} vs {len(df)}).")
else:
    # Ajouter les colonnes
    blast_df["Position"] = df["Position"].values
    blast_df["Peptide sequence"] = df["Peptide sequence"].values

    # Sauvegarder le fichier
    blast_df.to_excel(temp_excel, index=False)

    print(f"✅ Colonnes ajoutées et fichier enregistré sous : {temp_excel}")


## site_table
site_table.site_table(temp_excel)
site_table.tri_site_table()

## upstream
upstream.upstream(temp_excel)

## downstream
downstream.downstream(temp_excel)

## alignement 


alignement.align_sequences_and_save_to_json(temp_excel)
alignement.extract_alignment_for_position(temp_excel,output_excel)
alignement.position(output_excel)


ajout_info_down_up.ajout_info(output_excel)


 






# -*- coding: utf-8 -*-
"""
Created on Mon Apr 28 14:26:30 2025

@author: Brunel.Leo-paul
"""
import sys
import pandas as pd
from io import BytesIO
import scripts.récupération_séquence as recuperation_sequence
import scripts.blast_local as blast_local
import scripts.site_table as site_table 
import scripts.upstream as upstream
import scripts.downstream as downstream
import scripts.alignement as alignement 
import scripts.ajout_info_downstream_upstream as ajout_info_down_up
import scripts.recup_nom_prot as  recup_nom
import scripts.recup_dbPTM as recup_dbPTM
import scripts.tri_dbPTM as tri_dbPTM
import scripts.récupération_infos_uniprot as infos_uniprot

print(sys.argv)
input_excel = sys.argv[1]
output_excel = sys.argv[2]
output_csv = sys.argv[3]

fasta_file_bear = sys.argv[4]
fasta_file_humain = sys.argv[5]

#input_excel = "data/File_phospho_for_leo_reduit.xlsx"
#output_excel = "data/blast_result_final_test.xlsx"
#output_csv = "data/protein_sequences.csv"

temp_excel = "blast_result_temp.xlsx"
temp2_excel = "résultat_dbPTM.xlsx"

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
#fasta_file_humain = "data/prot_humaine.fasta"
blast_local.run_blast_analysis(output_csv, fasta_file_humain, temp_excel)


blast_local.add_sequences_to_blast_results(temp_excel,fasta_file_humain, output_csv)




# Charger les fichiers

blast_df = pd.read_excel(temp_excel, engine='openpyxl')



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

## récupération infos dbPTM
recup_nom.add_protein_names_to_excel(output_excel, fasta_file_humain, temp2_excel) 
recup_dbPTM.site_table(temp2_excel)
tri_dbPTM.process_matching_sites(temp2_excel, output_excel)

## récupération uniprot 
df2 = pd.read_excel(output_excel, engine='openpyxl')
protein_ids = df2['sseqid'].dropna().unique().tolist()
infos_uniprot.get_post_translational_modifications(protein_ids, output_excel)






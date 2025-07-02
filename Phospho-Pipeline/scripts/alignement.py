# -*- coding: utf-8 -*-
"""
Created on Mon Mar 24 12:14:46 2025

@author: Brunel.Leo-paul
"""
## Problème pour ligne 1388 qui a 35000 acide aminé pour une seule phosphorylation 
import pandas as pd
from Bio import pairwise2
from Bio.Align import substitution_matrices
import json
import os


def align_sequences_and_save_to_json(input_file, output_json = "data/alignment_results_test.json"):
    # Paramètres d'alignement
    matrix = substitution_matrices.load("BLOSUM62")
    gap_open_penality = -3 
    gap_extend_penality = -1
    # Charger les séquences du fichier Excel
    df = pd.read_excel(input_file, engine='openpyxl')

    # Charger les résultats déjà enregistrés si le fichier existe
    if os.path.exists(output_json):
        with open(output_json, "r", encoding="utf-8") as json_file:
            alignments_results = json.load(json_file)
            print(f"✅ {len(alignments_results)} alignements déjà enregistrés.")
    else:
        alignments_results = []

    # Cache des alignements déjà faits (pour éviter les doublons)
    alignment_cache = {}
    done_pairs = set(
        (entry['qseqid'], entry['sseqid']) for entry in alignments_results
    )

    # Boucle principale
    for index, row in df.iterrows():
        seq1 = row['query_sequence']
        seq2 = row['subject_sequence']
        qseqid = row['qseqid']
        sseqid = row['sseqid']
        sequences_key = (qseqid, sseqid)

        # Vérifie la taille des séquences
        if len(seq1) > 10000 or len(seq2) > 10000:
            print(f"⏭️  {index+1}/{len(df)} - Séquence trop longue ({len(seq1)} / {len(seq2)}), on saute : {qseqid} vs {sseqid}")
            continue

        if sequences_key in done_pairs:
            continue  # Déjà traité

        print(f"🔄 {index+1}/{len(df)} - Alignement de : {qseqid} vs {sseqid}")

        if (seq1, seq2) in alignment_cache:
            aln_seq1, aln_symbols, aln_seq2 = alignment_cache[(seq1, seq2)]
        else:
            try:
                aln = pairwise2.align.globalds(seq1, seq2, matrix, gap_open_penality, gap_extend_penality)
                aln_str = str(pairwise2.format_alignment(*aln[0]))

                aln_seq1 = aln_str.split("\n")[0]
                aln_symbols = aln_str.split("\n")[1]
                aln_seq2 = aln_str.split("\n")[2]

                alignment_cache[(seq1, seq2)] = (aln_seq1, aln_symbols, aln_seq2)
            except Exception as e:
                print(f"❌ Erreur à l'index {index} pour {qseqid} vs {sseqid} : {str(e)}")
                continue

        # Stocker l'alignement
        alignment_data = {
            'qseqid': qseqid,
            'sseqid': sseqid,
            'alignment': {
                'query_sequence_aligned': aln_seq1,
                'alignment_symbols': aln_symbols,
                'subject_sequence_aligned': aln_seq2,
            }
        }
        alignments_results.append(alignment_data)
        done_pairs.add(sequences_key)

        # Sauvegarde immédiate
        with open(output_json, "w", encoding="utf-8") as json_file:
            json.dump(alignments_results, json_file, indent=4, ensure_ascii=False)

    print(f"\n✅ Alignements enregistrés dans : {output_json}")

# Appel
if __name__ == "__main__":
    input_file = "C:/Users/brunel.leo-paul/code stage/data/blast_result_final.xlsx"
    output_json = "C:/Users/brunel.leo-paul/code stage/data/alignment_results.json"
    align_sequences_and_save_to_json(input_file, output_json)


 











## Code pour trouver acide aminé humain aligné face a site phospho chez l'ours 




def extract_alignment_for_position(blast_result_file,output_file,json_file = "data/alignment_results.json"):
    df_blast = pd.read_excel(blast_result_file, engine='openpyxl')

    with open(json_file, 'r', encoding='utf-8') as f:
        alignments_data = json.load(f)

    # Dictionnaire de recherche rapide des alignements par (qseqid, sseqid)
    alignment_dict = {
        (entry['qseqid'], entry['sseqid']): entry['alignment']
        for entry in alignments_data
    }

    # Ajouter les colonnes à remplir
    df_blast['acide_aminé_ours'] = None
    df_blast['alignement'] = None
    df_blast['position_subject'] = None

    for idx, row in df_blast.iterrows():
        qseqid = row['qseqid']
        sseqid = row['sseqid']
        position = row['Position']

        key = (qseqid, sseqid)

        if key not in alignment_dict:
            # Pas d'alignement trouvé pour cette paire : on ignore la ligne
            continue

        alignment = alignment_dict[key]
        query_aligned = alignment['query_sequence_aligned']
        subject_aligned = alignment['subject_sequence_aligned']

        try:
            pos = int(position)
        except ValueError:
            continue

        # Parcourir l'alignement pour retrouver la position correspondante
        query_pos_no_gap = 0
        subject_pos_no_gap = 0
        query_char = None
        subject_char = None
        subject_pos = None

        for i in range(len(query_aligned)):
            if query_aligned[i] != '-':
                query_pos_no_gap += 1
            if subject_aligned[i] != '-':
                subject_pos_no_gap += 1

            if query_pos_no_gap == pos:
                query_char = query_aligned[i]
                subject_char = subject_aligned[i] if subject_aligned[i] != '-' else 'gap'
                subject_pos = subject_pos_no_gap if subject_aligned[i] != '-' else 'gap'
                break

        df_blast.at[idx, 'acide_aminé_ours'] = query_char if query_char else 'gap'
        df_blast.at[idx, 'alignement'] = subject_char if subject_char else 'gap'
        df_blast.at[idx, 'position_subject'] = subject_pos if subject_pos else 'gap'

    temp_xlsx_file = output_file + ".xlsx"
    df_blast.to_excel(temp_xlsx_file, index=False, engine='openpyxl')
    os.rename(temp_xlsx_file, output_file)
    
    print(f"✅ Résultats enregistrés dans {output_file}")

# Exemple d'appel
if __name__ == "__main__":
    blast_result_file = "C:/Users/brunel.leo-paul/code stage/data/blast_result_final.xlsx"
    json_file = "C:/Users/brunel.leo-paul/code stage/data/alignment_results.json"
    output_file = "C:/Users/brunel.leo-paul/code stage/data/updated_blast_result_final.xlsx"
    extract_alignment_for_position(blast_result_file, json_file, output_file)





















## Code pour sortir position de l'acide aminé 
 


import pandas as pd
import json
import re
def position(blast_results_file,json_file = "data/filtered_phospho_data.json"):

    # Lire le fichier Excel
    blast_df = pd.read_excel(blast_results_file, engine='openpyxl')
    
    # Charger les données JSON
    with open(json_file, 'r') as f:
        json_data = json.load(f)
    
    # Initialiser la colonne pour les résultats
    blast_df['Matching Site'] = ""
    
    # Parcourir les lignes
    for idx, blast_row in blast_df.iterrows():
        protein_name = blast_row['sseqid']
        subject_position = str(blast_row['position_subject'])
    
        if protein_name in json_data:
            protein_info = json_data[protein_name]
    
            for site_info in protein_info:
                match = re.search(r'\d+', site_info['site'])  # Extrait la position (numéro)
                if match and match.group() == subject_position:
                    blast_df.at[idx, 'Matching Site'] = site_info['site']
                    break  # On sort dès qu’on trouve une correspondance
    
    # Sauvegarder le fichier mis à jour
    blast_df.to_excel(blast_results_file, index=False)
    
    print(f"✅ Comparaison terminée. Résultats enregistrés dans {blast_results_file}")
    
    
    
    
    
    
    
    
    
    








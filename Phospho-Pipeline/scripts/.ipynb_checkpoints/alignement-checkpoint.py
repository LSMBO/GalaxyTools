# -*- coding: utf-8 -*-
"""
Created on Mon Mar 24 12:14:46 2025

@author: Brunel.Leo-paul
"""

import pandas as pd
from Bio import pairwise2
from Bio.Align import substitution_matrices
import json

# Paramètres d'alignement
matrix = substitution_matrices.load("BLOSUM62")
gap_open_penality = -3 
gap_extend_penality = -1

def align_sequences_and_save_to_json(input_file, output_json):
    """
    Fonction qui aligne les séquences à partir des colonnes 'query_sequence' et 'subject_sequence'
    et sauvegarde les résultats dans un fichier JSON.
    
    Args:
    - input_file (str): Chemin du fichier Excel contenant les séquences.
    - output_json (str): Chemin du fichier JSON de sortie contenant les résultats d'alignement.
    
    Returns:
    - None: Les résultats sont sauvegardés dans un fichier JSON.
    """
    # Charger les séquences du fichier Excel
    df = pd.read_excel(input_file)
    
    # Stocker les résultats d'alignement
    alignments_results = []

    # Boucle à travers chaque paire de séquences à aligner
    for index, row in df.iterrows():
        seq1 = row['query_sequence']
        seq2 = row['subject_sequence']
        
        # Effectuer l'alignement des séquences
        aln = pairwise2.align.globalds(seq1, seq2, matrix, gap_open_penality, gap_extend_penality)
        aln_str = str(pairwise2.format_alignment(*aln[0]))

        # Extraire les parties importantes de l'alignement
        aln_seq1 = aln_str.split("\n")[0]  # Séquence 1 avec les gaps
        aln_symbols = aln_str.split("\n")[1]  # Correspondance des séquences ('|', '.', ' ')
        aln_seq2 = aln_str.split("\n")[2]  # Séquence 2 avec les gaps
        
        # Enregistrer le résultat d'alignement dans une structure de données
        alignment_data = {
            'qseqid': row['qseqid'],
            'sseqid': row['sseqid'],
            'alignment': {
                'query_sequence_aligned': aln_seq1,
                'alignment_symbols': aln_symbols,
                'subject_sequence_aligned': aln_seq2,
            }
        }

        # Ajouter l'alignement à la liste des résultats
        alignments_results.append(alignment_data)

    # Sauvegarder les résultats dans un fichier JSON
    with open(output_json, 'w') as json_file:
        json.dump(alignments_results, json_file, indent=4)
    
    print(f"Résultats d'alignement enregistrés dans {output_json}")

# Exemple d'appel de la fonction
if __name__ == "__main__":
    input_file = "C:/Users/brunel.leo-paul/code stage/data/blast_result_final.xlsx"
    output_json = "C:/Users/brunel.leo-paul/code stage/data/alignment_results.json"
    align_sequences_and_save_to_json(input_file, output_json)

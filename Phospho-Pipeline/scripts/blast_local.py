# -*- coding: utf-8 -*-
"""
Created on Wed Feb 12 12:17:17 2025

@author: Brunel.Leo-paul
"""

 ## Nécessite instalation NCBI Blast+
import pandas as pd
from Bio.Seq import Seq
from Bio.SeqRecord import SeqRecord
from Bio import SeqIO
from Bio.Blast.Applications import NcbiblastpCommandline
import os

def run_blast_analysis(csv_file, subject_file, output_file, output_fasta="data/sequences.fasta"):
    """
    Fonction qui exécute un BLAST entre des séquences d'un fichier CSV et une protéine humaine d'un fichier FASTA.
    
    Args:
    - csv_file (str): Chemin du fichier CSV contenant les séquences.
    - subject_file (str): Chemin du fichier FASTA avec la séquence protéique humaine.
    - output_fasta (str): Chemin du fichier FASTA à générer pour le BLAST.
    - output_file (str): Chemin du fichier Excel de sortie contenant les résultats filtrés.
    - top_n (int): Nombre de séquences à utiliser depuis le fichier CSV (par défaut 200).
    
    Returns:
    - None: Le résultat est sauvegardé dans un fichier Excel.
    """

    # Charger les séquences depuis le fichier CSV
    df = pd.read_csv(csv_file)
    sequences = df["Sequence"]
    identifiants = df["Identifiant"]  

    
    seq_records = [SeqRecord(Seq(seq), id=f"seq_{i+1}", description="") for i, seq in enumerate(sequences)]

    # Écrire le fichier FASTA
    with open(output_fasta, "w") as fasta_out:
        SeqIO.write(seq_records, fasta_out, "fasta")

    
    columns = ["qseqid", "sseqid", "pident", "ppos", "evalue", "nident", "positive", "qlen", "slen", "qstart", "qend", "qcovs", "qcovhsp"]
    outfmt = "6 " + " ".join(columns)
    

    # Lancer le BLAST avec le fichier FASTA généré
    blastp_cline = NcbiblastpCommandline(query=output_fasta, subject=subject_file, outfmt=outfmt, out="blast_results.csv")
    blastp_cline()

    
    df_blast = pd.read_csv("blast_results.csv", sep="\t", names=columns)
    
    df_blast['similarity'] = (df_blast['positive'] / df_blast['qlen']) * 100 

    best_matches = df_blast.sort_values(by=['evalue', 'pident'], ascending=[True, False])


    best_matches = best_matches.loc[best_matches.groupby('qseqid')['evalue'].idxmin()]


    best_matches['seq_num'] = best_matches['qseqid'].str.extract(r'(\d+)').astype(int)
    best_matches = best_matches.sort_values(by='seq_num')
    
    
    df_blast['evalue'] = df_blast['evalue'].apply(lambda x: "inférieur à 1e-180" if x == 0 else x)

    
    best_matches['qseqid'] = identifiants.values

    # Supprimer la colonne temporaire utilisée pour le tri
    best_matches = best_matches.drop(columns='seq_num')

    # Sauvegarder les meilleurs résultats dans un fichier Excel
    print("Sauvegarde des résultats dans le fichier Excel...")
    best_matches.to_excel(output_file, index=False)

    print(f"Résultats filtrés enregistrés dans {output_file}")



if __name__ == "__main__":
    csv_file = "C:/Users/brunel.leo-paul/code stage/data/protein_sequences.csv"
    subject_file = "C:/Users/brunel.leo-paul/code stage/data/prot_humaine.fasta"
    run_blast_analysis(csv_file, subject_file)









## Code récupération séquence pour alignement 


import pandas as pd
from Bio import SeqIO

def add_sequences_to_blast_results(blast_results_file, fasta_file, csv_file, output_file="C:/Users/brunel.leo-paul/code stage/data/blast_result_final_test.xlsx"):
    
    # Lire les résultats du BLAST (fichier Excel)
    df_blast = pd.read_excel(blast_results_file)
    
    # Charger les séquences du fichier CSV pour les queries
    df_sequences = pd.read_csv(csv_file)
    sequence_dict = dict(zip(df_sequences["Identifiant"], df_sequences["Sequence"]))  # Dictionnaire des séquences pour les queries

    # Fonction pour récupérer la séquence du sujet à partir du fichier FASTA
    def get_subject_sequence(fasta_file, subject_id):
        for record in SeqIO.parse(fasta_file, "fasta"):
            if subject_id in record.id:
                return str(record.seq)
        print(f"Warning: Séquence non trouvée pour {subject_id}")
        return None  # Si la séquence n'est pas trouvée

        
    df_blast['sseqid'] = df_blast['sseqid'].str.extract(r'\|([A-Za-z0-9]+)\|')

    # Ajouter les séquences des queries dans une nouvelle colonne
    df_blast['query_sequence'] = df_blast['qseqid'].apply(lambda x: sequence_dict.get(x, None))

    # Ajouter les séquences des subjects dans une nouvelle colonne
    df_blast['subject_sequence'] = df_blast['sseqid'].apply(lambda x: get_subject_sequence(fasta_file, x))

    # Sauvegarder les résultats dans un fichier Excel
    print(f"Ajout des séquences dans le fichier {blast_results_file}...")
    df_blast.to_excel(blast_results_file, index=False)  # Enregistrement avec encodage UTF-8
    print(f"Résultats avec séquences enregistrés dans {blast_results_file}")

# Exemple d'appel de la fonction depuis un autre fichier Python
if __name__ == "__main__":
    blast_results_file = "C:/Users/brunel.leo-paul/code stage/data/blast_result_final.xlsx"  # Résultats du BLAST
    fasta_file = "C:/Users/brunel.leo-paul/code stage/data/prot_humaine.fasta"  # Fichier FASTA des subjects
    csv_file = "C:/Users/brunel.leo-paul/code stage/data/protein_sequences.csv"  # Fichier CSV des queries
    add_sequences_to_blast_results(blast_results_file, fasta_file, csv_file)









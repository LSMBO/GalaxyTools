# -*- coding: utf-8 -*-
"""
Created on Mon Feb 24 16:37:41 2025

@author: Brunel.Leo-Paul
"""

from Bio.Blast.Applications import NcbimakeblastdbCommandline
from Bio.Blast.Applications import NcbiblastpCommandline
import re
import os
import csv




def run_msblast(query, subject):
    blastp_cline = NcbiblastpCommandline(
        query=query,
        subject=subject,
        out="msblast_results.txt",
        ungapped=True,
        matrix='PAM30',
        evalue=100,
        num_descriptions=50000,
        comp_based_stats='F',
        max_hsps=100,
        num_alignments=50000
    )
    stdout, stderr = blastp_cline()
    if stderr:
        raise RuntimeError(f"BLAST error: {stderr}")
    return "msblast_results.txt"

def msblast(query_file, subject_file, makeblastdb=False):
    if makeblastdb:
        db_name = os.path.splitext(subject_file)[0]
        makeblastdb_cline = NcbimakeblastdbCommandline(dbtype="prot", input_file=subject_file, out=db_name)
        stdout, stderr = makeblastdb_cline()
        if stderr:
            raise RuntimeError(f"makeblastdb error: {stderr}")
        subject_file = db_name
    
    result_file = run_msblast(query_file, subject_file)
    output = parse_blast_file(result_file)
    os.remove(result_file)

    # Exporter les résultats dans un fichier CSV
    csv_file = "C:/Users/brunel.leo-paul/code stage/data/datablast_results.csv"
    with open(csv_file, mode='w', newline='') as file:
        writer = csv.DictWriter(file, fieldnames=output[0].keys())
        writer.writeheader()
        writer.writerows(output)
    
    print(f"Les résultats ont été exportés vers {csv_file}")
    return output



def parse_blast_file(blast_file):
    results = {}
    with open(blast_file, 'r') as file:
        lines = iter(file.readlines())
        current_query = None
        current_result = None
        for line in lines:
            if line.startswith("Query="):
                if current_result:
                    results[current_query] = current_result
                current_query = line.split(' ')[1].strip()
                current_result = {'accession': current_query, 'matches': []}

            elif line.startswith(">"):
                match = {
                    'id': line.split(' ')[1],
                    'description': '',
                    'score': 0,
                    'length': 0,
                    'identities': 0,
                    'positives': 0,
                    'gaps': 0,
                    'query': '',
                    'alignment': '',
                    'subject': ''
                }
                description_parts = line.split()[1:2]  # Garder uniquement l'ID de la protéine humaine
                match['description'] = ' '.join(description_parts)
                current_result['matches'].append(match)

            elif line.startswith(" Score ="):
                match['score'] = float(line.split('=')[1].split()[0])

            elif line.startswith(" Identities ="):
                identities = line.split('=')[1].split(',')[0].strip().split('/')[0]
                positives = line.split('=')[2].split(',')[0].strip().split('/')[0]
                gaps = line.split('=')[3].strip().split('/')[0]
                match['identities'] = int(identities)
                match['positives'] = int(positives)
                match['gaps'] = int(gaps)

            elif line.startswith("Query"):
                match['query_start'] = int(line.split()[1])
                match['query'] = line.split()[2]
                match['query_end'] = int(line.split()[3])
                next_line = next(lines, '').strip()
                match['alignment'] = next_line

            elif line.startswith("Sbjct"):
                match['subject_start'] = int(line.split()[1])
                match['subject'] = line.split()[2]
                match['subject_end'] = int(line.split()[3])

        if current_result:
            results[current_query] = current_result

    organized_results = []
    for query, data in results.items():
        for match in data['matches']:
            organized_results.append({
                'description': match['description'],
                'id': query,
                'bitscore': match['score'],
                'identities': match['identities'],
                'positives': match['positives'],
                'gaps': match['gaps'],
                'query_start': match['query_start'],
                'query_end': match['query_end'],
                'subject_start': match['subject_start'],
                'subject_end': match['subject_end'],
                'query_aligned_sequence': match['query'],
                'subject_aligned_sequence': match['subject'],
                'alignment': match['alignment']
            })
            
            # Calcul des segments d'alignement et ajout aux résultats
            alignment_segments = match['alignment'].split(' ')
            max_consecutive_aa_including_pos = max(len(segment) for segment in alignment_segments)
            max_consecutive_aa_excluding_pos = get_max_consecutive_aa_excluding_pos(alignment_segments)
            max_consecutive_aa_allowing_one_pos_or_one_minus = get_max_consecutive_aa_allowing_one_pos_or_one_minus(match['alignment'])
            max_consecutive_aa_allowing_one_minus = get_max_consecutive_aa_allowing_one_minus(match['alignment'])
            organized_results[-1]['max_consecutive_aa_including_pos'] = max_consecutive_aa_including_pos
            organized_results[-1]['max_consecutive_aa_excluding_pos'] = max_consecutive_aa_excluding_pos
            organized_results[-1]['max_consecutive_aa_allowing_one_pos_or_one_minus'] = max_consecutive_aa_allowing_one_pos_or_one_minus
            organized_results[-1]['max_consecutive_aa_allowing_one_minus'] = max_consecutive_aa_allowing_one_minus

    return organized_results


def get_max_consecutive_aa_excluding_pos(segments):
    max_len = 0
    for segment in segments:
        seg_split_pos = segment.split('+')
        for seg in seg_split_pos:
            if len(seg) > max_len:
                max_len = len(seg)
    return max_len
            
def get_max_consecutive_aa_allowing_one_pos_or_one_minus(sequence):
    sequence = sequence.replace(' ', '-')
    max_len = 0
    for start in range(len(sequence)):
        current_sequence = sequence[start:]
        segments = re.findall(r'[A-Z]*[\+\-]?[A-Z]*', current_sequence)
        if segments:
            current_max_len = max([len(segment) for segment in segments])
            if current_max_len > max_len:
                max_len = current_max_len
    return max_len

def get_max_consecutive_aa_allowing_one_minus(sequence):
    sequence = sequence.replace(' ', '-')
    max_len = 0
    for start in range(len(sequence)):
        current_sequence = sequence[start:]
        segments = re.findall(r'[^\-]*[\-]?[^\-]*', current_sequence)
        if segments:
            current_max_len = max([len(segment) for segment in segments])
            if current_max_len > max_len:
                max_len = current_max_len
    return max_len



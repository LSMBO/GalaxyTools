# RefSeq assembly to Fasta

Generates a fasta file based on RefSeq assembly data.

You select a taxonomy in the list, and we download the corresponding fasta file from the NCBI FTP server. Given the nature to the data, it is suggested that you remove the duplicate sequences from the fasta file.

Once you have the fasta file generated, you can use it in the Fasta Toolbox to add contaminant proteins, generate decoy entries, etc.

**Important:**
Make sure you run getAssemblies.pl at least once to generate the files refseq_macro.xml and refseq_ref.txt necessary to list the taxonomies.
Ideally, you should use crontabl to run getAssembles.pl once a week.

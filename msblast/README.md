# MS Blast

Runs NCBI blastp version 2.11.0+ and converts its output into a user-friendly Excel file.
The parameters for blastp are the following:

* -evalue=100
* -num_descriptions 50000
* -num_alignments 50000
* -comp_based_stats F
* -ungapped
* -matrix PAM30
* -max_hsps 100
* -sorthsps 1

Documentation for NCBI blast tool suite is available here: https://www.ncbi.nlm.nih.gov/books/NBK279690/



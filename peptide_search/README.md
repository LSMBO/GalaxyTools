# Peptide Search

Searches for peptides within a Fasta file. If taxonomy ids are provided, the corresponding Fasta file will be automatically downloaded from UniProt.
Some options are available, such as considering that Leucin and Isoleucin are equivalent, or considering that Aspartate and Asparagine are equivalent.

Another option is to allow the use of Regular Expressions in the peptide list. Here are some possibilities offered by Regular expressions:

* Question mark '?': indicates zero or one occurences of a character. For instance, the sequence "PEPTI?DE" would match with either "PEPTDE" and "PEPTIDE".

* Asterisk sign '*': indicates zero or more occurences of a character. For instance, the sequence "PEPTI*DE" would match with "PEPTDE", "PEPTIDE", "PEPTIIDE", "PEPTIIIDE" and so on.

* Plus sign '+': indicates one or more occurences of a character. For instance, the sequence "PEPTI+DE" would match with "PEPTIDE", "PEPTIIDE", "PEPTIIIDE" and so on (but not with "PEPTDE").

* Dot '.': this character matches for any character, and can be combined with the previous signs. For instance, "PEPT.DE" would match with "PEPTIDE" or "PEPTLDE" or "PEPTADE", etc. And "PEPT.*DE" can match with anything starting with "PEPT" and ending with "DE".

* Square brackets: matches for a single character that is listed in the brackets. For instance, the sequence "PEPT[IL]DE" would match with either "PEPTIDE" and "PEPTLDE".

* Square brackets with a circumflex accent: this is the opposite version of the brackets, il will match for any character other than those listed in the brackets. For instance "PEPT[^IL]DE" will NOT match with "PEPTIDE" but could match with "PEPTWDE".

* Circumflex accent '^': when this accent is put at the beggining of the expression, it means that the match will only be possible at the start of the text. For instance, "^PEPTIDE" can only match with an N-terminal peptide (it's up to you to add a methionine).

* Dollar sign '$': when this sign is put at the end of the expression, it means that the match will only be possible at the end of the text. For instance, "PEPTIDE$" can only match with a C-terminal peptide.

* More information here: https://en.wikipedia.org/wiki/Regular_expression

Keep in mind that the search will only be performed on the protein sequences, and that it will always be case insensitive.

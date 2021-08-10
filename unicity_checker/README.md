# Unicity checker

Checks for each peptide whether it's unique or shared in the fasta file.

Returns an Excel file listing for each peptide the protein it can be found in, with the start and stop positions.

The enzyme definitions are based on Mascot's enzyme configuration page. Columns are explained after the table.

| Title          | Sense  | Cleave At | Restrict | Independent | Semispecific |
|----------------|--------|-----------|----------|-------------|--------------|
| Trypsin        | C-Term | KR        | P        | no          | no           |
| Trypsin/P      | C-Term | KR        |          | no          | no           |
| Arg-C          | C-Term | R         | P        | no          | no           |
| Asp-N          | N-Term | BD        |          | no          | no           |
| Asp-N_ambic    | N-Term | DE        |          | no          | no           |
| Chymotrypsin   | C-Term | FLWY      | P        | no          | no           |
| CNBr           | C-Term | M         |          | no          | no           |
| CNBr+Trypsi    | C-Term | M         |          | no          | no           |
| CNBr+Trypsi    | C-Term | KR        | P        | no          | no           |
| Formic_acid    | N-Term | D         |          | no          | no           |
| Formic_acid    | C-Term | D         |          | no          | no           |
| Lys-C          | C-Term | K         | P        | no          | no           |
| Lys-C/P        | C-Term | K         |          | no          | no           |
| LysC+AspN      | N-Term | BD        |          | no          | no           |
| LysC+AspN      | C-Term | K         | P        | no          | no           |
| Lys-N          | N-Term | K         |          | no          | no           |
| PepsinA        | C-Term | FL        |          | no          | no           |
| semiTrypsin    | C-Term | KR        | P        | no          | yes          |
| TrypChymo      | C-Term | FKLRWY    | P        | no          | no           |
| TrypsinMSIPI   | N-Term | J         |          | no          | no           |
| TrypsinMSIPI   | C-Term | KR        | P        | no          | no           |
| TrypsinMSIPI   | C-Term | J         |          | no          | no           |
| TrypsinMSIPI/P | N-Term | J         |          | no          | no           |
| TrypsinMSIPI/P | C-Term | JKR       |          | no          | no           |
| V8-DE          | C-Term | BDEZ      | P        | no          | no           |
| V8-E           | C-Term | EZ        | P        | no          | no           |
| GluC           | C-Term | DE        | P        | no          | no           |

* Sense: Whether cleavage occurs on the C terminal or N terminal side of the residues specified under Cleave At.
* Cleave At: A list of the residue 1 letter codes at which cleavage occurs.
* Restrict: A list of the residue 1 letter codes which prevent cleavage if present adjacent to the potential cleavage site.
* Independent: When value is 'no', if there are multiple components, these are combined, as if multiple enzymes had been applied simultaneously or serially to a single sample aliquot. When value is 'yes', multiple components are treated as if independent digests had been performed on separate sample aliquots and the resulting peptide mixtures combined.
* Semispecific: When value is 'yes', any given peptide need only conform to the cleavage specificity at one end.



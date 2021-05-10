# Kegg

Automatic extraction of KEGG Pathway Maps assigned to given proteins (from Swissprot accession numbers) or directly from Kegg identifiers. Kegg files will be downloaded and stored in local directories, so you only have to download them once (but the first runs will take a while).
Returns a user-friendly Excel file with the Kegg maps and pathways for each protein/id.
Also returns a zip files with all the maps in SVG format.

The color code used in the Excel file along with the SVG files is the following :

* Yellow: Does not satisfy p-value criteria (and Tukey is provided)
* Blue: Satisfies p-value criteria (and Tukey is provided)
* Red: Satisfies all statistics, the protein is upregulated
* Green: Satisfies all statistics, the protein is downregulated

KEGG database resource: Kyoto Encyclopedia of genes and Genomes


**Format of the input file**

* The input file has to be an Excel file.
* Data is expected to be in the first sheet and start at the beginning of the sheet.
* First line is considered as a header line.
* Column A has to contain protein accession numbers (such as 'P48444')
* If you have p-values
    * Column B has to contain p-values
* If you have p-values and Fold Change values
    * Column B has to contain p-values
    * Column C has contain FC values
* If you have p-values, Tukey and FC values
    * Column B has to contain p-values
    * Column C has contain Tukey values
    * Column D has contain FC values


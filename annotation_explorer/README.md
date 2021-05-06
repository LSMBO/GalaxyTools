# Annotation Explorer

Takes a list of Uniprot accession names or ids and extracts protein information and GO terms from Uniprot.
GO ancestors are queried from the Gene Ontology database http://geneontology.org/

For each proteins, GO terms are separated into three ontologies: Cellular component, Molecular function and Biological process.
Links for the AmiGO Visualize tool are generated on the fly, you can find more information about its format here: http://wiki.geneontology.org/index.php/AmiGO_2_Manual:_Visualize

You can also submit GO terms instead of protein identifiers. In this case you will only get the GO information and the corresponding categories.

In-house GO categories are provided, you can download the file here: https://iphc-galaxy.u-strasbg.fr/static/annotation_explorer_categories.xlsx
You can provide your own categories using the same XLSX format.

Finally, the output is a user-friendly Excel file with all the results returned by the differents sources.



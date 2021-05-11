# LSMBO Galaxy tools

This repository contains a list of proteomic tools for Galaxy.
Note that each tool depends on the LsmboFunctions.pm module.

* Annotation Explorer: Retrieve GO terms and ancestors list
* Fasta36 wrapper: Protein sequence comparaison
* EaseDB: Generates a taxonomy-centered database for DAVID's EASE software
* Fasta toolbox: Generation of Fasta files
* Kegg extraction: Get Kegg maps from Uniprot entries or Kegg identifiers
* MS Blast: Run NCBI blastp and generate an Excel output
* MS Merge: Merges mgf files together
* Protein/gene data: Extraction of protein information
* Protein list comparator: Transforms an Excel table to compare protein's information per sample
* RefSeq assembly to Fasta: Generation of a Fasta file based on RefSeq assemblies
* Unicity checker: Checks peptide unicity
* LsmboFunctions.pm: contains global methods


**Technical questions**

The tools have been developped and tested on a CentOS 8 with Perl v5.26.
Most of the dependencies are listed in the file LsmboFunctions.pm:
* General dependencies: Archive::Zip, Data::Dumper, File::Basename, File::Copy, File::Slurp, JSON::XS, List::MoreUtils, List::Util, LWP::Simple, LWP::UserAgent, Number::Bytes::Human, POSIX, Spreadsheet::ParseExcel::Utility, Spreadsheet::ParseXLSX, Excel::Template::XLSX
* Specific dependencies for Annotation Explorer: IO::Uncompress::Gunzip, Spreadsheet::Reader::ExcelXML, URI::Escape
* Specific dependencies for EaseDB: File::Path
* Specific dependencies for Fasta36 wrapper: Parallel::Loops, Scalar::Util
* Specific dependencies for Fasta Toolbox: Archive::Zip::MemberRead
* Specific dependencies for Kegg extraction: DBI, Image::Size, MIME::Base64, Scalar::Util, SVG, XML::Simple
* Specific dependencies for RefSeq assembly to Fasta: Mail::Sendmail


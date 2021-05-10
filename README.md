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

The tools have been developped and tested with Perl v5.26.
Most of the dependencies are listed in the file LsmboFunctions.pm:
* General:
    * Archive::Zip
    * Data::Dumper
    * File::Basename
    * File::Copy
    * File::Slurp qw(read_file write_file)
    * JSON::XS qw(encode_json decode_json)
    * List::MoreUtils qw(uniq)
    * List::Util 'shuffle'
    * LWP::Simple
    * LWP::UserAgent
    * Number::Bytes::Human qw(format_bytes)
    * POSIX qw(strftime)
    * Spreadsheet::ParseExcel::Utility 'sheetRef'
    * Spreadsheet::ParseXLSX
    * Excel::Template::XLSX
* Specific to Annotation Explorer
    * IO::Uncompress::Gunzip qw(gunzip $GunzipError)
    * Spreadsheet::Reader::ExcelXML
    * URI::Escape
* Specific to EaseDB:
    * File::Path qw(make_path remove_tree)
* Specific to Fasta36 wrapper:
    * Parallel::Loops
    * Scalar::Util qw(looks_like_number)
* Specific to Fasta Toolbox:
    * Archive::Zip qw(:ERROR_CODES :CONSTANTS)
    * Archive::Zip::MemberRead
* Specific to Kegg extraction:
    * DBI
    * Image::Size
    * MIME::Base64 qw(encode_base64)
    * Scalar::Util qw(looks_like_number)
    * SVG
    * XML::Simple
* Specific to RefSeq assembly to Fasta:
    * Mail::Sendmail
* Specific to Unicity checker:
    * List::MoreUtils qw(uniq)

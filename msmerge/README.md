# MS Merge

Merges several MGF files into a single MGF file.
You may usually find some comments at the beginning of MGF files, these lines are not kept.
Spectra are directly copied to the new file, with only one modification : the name of the file is added to the TITLE field. This helps to keep track of the original peaklist for each spectra. Eventually, it can also prevent duplicate titles if by chance we are merging two peaklists containing spectra with the same name.

**Command line usage**

> perl msmerge.pl <output_mgf> <mgf path1> <mgf name1> <mgf path2> <mgf name2>...

First argument corresponds to the path of the merged MGF file.
Next arguments are paired, with MGF path and MGF file name. This is required because Galaxy anonymizes file names, but we still want to keep the original file names in the output file.

The number of files you can merge will depend on the maximum number of argument you can pass to a command. You can obtain this information with the following command:
> getconf ARG_MAX

**Important note**

Merging peaklists can useful in some cases, but it is advised to use this tool with caution. This tool will generate a large peaklist, eventually huge, and it may not be optimal for identification software, or for the process of the identification results.

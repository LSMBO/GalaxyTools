# R 4.0.5 is required, this is the common denominator for all the required packages

# EPEL and PowerTools may be required:
# > sudo dnf config-manager --set-enabled powertools
# > sudo dnf install epel-release
# Library requirements: 
# > sudo dnf install libcurl-devel openssl-devel libxml2-devel netcdf-devel harfbuzz-devel fribidi-devel freetype-devel libpng-devel libtiff-devel libjpeg-turbo-devel cairo-devel libXt-devel

# get the absolute path of the script
SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
LIBPATH=$SCRIPTPATH/libs

# we will use a local directory to install all the libraries
# this will make the installation exclusive to this tool
mkdir -p $LIBPATH

# Start the installation
Rscript --vanilla install.R $LIBPATH 2>&1 |tee install.log

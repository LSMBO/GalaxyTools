# provide the library path as an argument
args <- commandArgs(trailingOnly=TRUE)
libraryPath <- args[1]
repository <- "http://cran.us.r-project.org"
Sys.setenv(R_INSTALL_STAGED = FALSE)

print(paste(c("Local library path is", libraryPath), collapse=" "))
print(paste(c("Remote repository is", repository), collapse=" "))

# install and load BiocManager
print("> Install and load BiocManager")
if (!requireNamespace("BiocManager", quietly = TRUE, lib.loc = libraryPath)) {
  install.packages("BiocManager", repos = repository, lib = libraryPath, clean = TRUE)
}
library(BiocManager, lib.loc = libraryPath)

# install dependencies (only those not already installed)
print("> Install dependencies")
pkgs_to_install <- c("impute", "pcaMethods", "globaltest", "GlobalAncova", "Rgraphviz", "preprocessCore", "genefilter", "SSPA", "sva", "limma", "KEGGgraph", "siggenes","BiocParallel", "MSnbase", "multtest","RBGL","edgeR","fgsea","devtools","crmn", "ellipse", "usethis", "ps", "processx", "withr", "desc", "backports")
list_installed <- installed.packages(lib.loc = libraryPath)
pkgs <- subset(pkgs_to_install, !(pkgs_to_install %in% list_installed[, "Package"]))
if(length(pkgs) > 0) {
  BiocManager::install(pkgs, lib = libraryPath, clean = TRUE)
}

# load Devtools dependencies
print("> Loading Devtools dependencies and Devtools library")
library("usethis", lib.loc = libraryPath)
library("ps", lib.loc = libraryPath)
library("processx", lib.loc = libraryPath)
library("withr", lib.loc = libraryPath)
library("desc", lib.loc = libraryPath)
library(devtools, lib.loc = libraryPath)

# install and load MetaboAnalystR dependencies
print("> Loading MetaboAnalystR dependencies")
library(BiocGenerics, lib.loc = libraryPath)
library(Biobase, lib.loc = libraryPath)
library(BiocParallel, lib.loc = libraryPath)
library(Rcpp, lib.loc = libraryPath)
library(mzR, lib.loc = libraryPath)
library(S4Vectors, lib.loc = libraryPath)
library(ProtGenerics, lib.loc = libraryPath)
library(crayon, lib.loc = libraryPath)
library(MSnbase, lib.loc = libraryPath)
library(backports, lib.loc = libraryPath)
devtools::install_github("xia-lab/OptiLCMS", build = TRUE, build_vignettes = FALSE, build_manual = FALSE, lib = libraryPath)
library(OptiLCMS, lib.loc = libraryPath)

print("> Installing MetaboAnalystR")
devtools::install_github("xia-lab/MetaboAnalystR", build = TRUE, build_vignettes = FALSE, lib = libraryPath)

print("> Installation ended")


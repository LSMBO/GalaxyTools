args <- commandArgs(trailingOnly=TRUE)

# usage: pca.R library_path input_file image_format dpi
# - image_format can be png or svg
# - dpi should be a integer (suggested values would be 72 for svg and 300 for png)

# provide the library path as an argument
libraryPath <- args[1]
filename <- args[2]
image_format <- args[3]
dpi_value <- as.numeric(args[4])
output_file_1 <- "PairSummary"
output_file_2 <- "2DScore"

# load the necessary libraries
library(crayon, lib.loc = libraryPath)
library(backports, lib.loc = libraryPath)
library(memoise, lib.loc = libraryPath)
library(MetaboAnalystR, lib.loc = libraryPath)
library(ellipse, lib.loc = libraryPath)

# initialize the objects
print("Reading input file")
mSet <- InitDataObjects("pktable", "stat", FALSE)
mSet <- Read.TextData(mSet, filename, "colu", "disc");
mSet <- SanityCheckData(mSet)
mSet <- ReplaceMin(mSet)
mSet <- PreparePrenormData(mSet)
mSet <- Normalization(mSet, "NULL", "NULL", "NULL", ratio = FALSE, ratioNum = 20)
mSet <- PCA.Anal(mSet)

# create the images
print(paste(c("Generating", image_format, "files with a dpi of", dpi_value), collapse=" "))
mSet <- PlotPCAPairSummary(mSet, output_file_1, image_format, dpi_value, width=NA, 2)
mSet <- PlotPCA2DScore(mSet, output_file_2, format = image_format, dpi = dpi_value, width = NA, 1, 2, reg = 0.95, 1, 0)

print("Done.")

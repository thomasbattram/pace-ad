# ------------------------------------------------------------
# Extract DNAm sites near eczema genes
# ------------------------------------------------------------

## Aim: To extract DNAm sites near candidate genes identified by Maria after cleaning that data

## Date: 2022-01-11

## pkgs
library(tidyverse) # tidy code and data
library(meffil) # to get DNAm positions
library(readxl) # read in the candidate gene data
library(biomaRt) # ensembl gene IDs and positions
library(usefunc) # own package of useful functions

## args
args <- commandArgs(trailingOnly = TRUE)
raw_datfile <- args[1]
clean_outfile <- args[2]
cpg_genes_output <- args[3]

# raw_datfile <- "data/candidate-genes-raw.xlsx"
# clean_outfile <- "data/candidate-genes-clean.tsv"
# cpg_genes_output <- "data/candidate-genes-cpgs.tsv"

## data
raw_dat <- read_xlsx(raw_datfile, n_max = 26)

# ------------------------------------------------------------
# Clean candidate gene data
# ------------------------------------------------------------

## Make columns easier to deal with
colnames(raw_dat)
colnames(raw_dat) <- gsub(" |-", "_", colnames(raw_dat))

## separate out gene names and prioritisation scores
clean_dat <- raw_dat %>%
	separate(Top_Ranked_Gene, "first", "\\(") %>%
	separate(Second_Ranked_Gene, "second", "\\(") %>%
	separate(Third_Ranked_Gene, "third", "\\(") %>%
	dplyr::select(-Locus, -GWAS_Index_Variant, -Nearest_Genes) %>% 
	pivot_longer(everything(), names_to = "rank", values_to = "gene") %>%
	mutate(gene = substr(gene ,1, nchar(gene) - 1))

# ------------------------------------------------------------
# Extract CpGs surrounding the genes
# ------------------------------------------------------------

mef_probe_info <- meffil.get.features()
mef_probe_info <- mef_probe_info %>%
	dplyr::filter(grepl("^cg[0-9]*", name)) %>%
	mutate(chromosome = gsub("^chr", "", chromosome)) %>%
	dplyr::select(name, chromosome, position) %>%
	as_tibble

mart <- useMart("ensembl", dataset="hsapiens_gene_ensembl")
attri <- listAttributes(mart)
chr <- c(1:22, "x", "y")
all_genes <- lapply(chr, function(chr_num) {
	print(chr_num)
	genes <- getBM(
	    attributes=c("ensembl_gene_id","hgnc_symbol","chromosome_name","start_position","end_position"),
	    filters=c("chromosome_name", "start", "end"),
	    values=list(chromosome=chr_num, start="1",end=as.character(1e99)),
    	mart=mart
    )
    genes$chromosome_name <- as.character(genes$chromosome_name)
	return(genes)   
})
library(tidyverse) # couldn't load this before as it crashed things! 
all_genes <- bind_rows(all_genes) %>%
	distinct()

clean_dat %>%
	left_join(all_genes, by = c("gene" = "hgnc_symbol")) %>%
	dplyr::select(rank, gene, chromosome = chromosome_name, start_position, end_position) %>%
	dplyr::filter(is.na(chromosome))

## make some manual edits to clean dat to get it in line with the 
new_KIAA0391 <- "PRORP" # new hgnc name for one gene
clean_dat$gene <- ifelse(clean_dat$gene == "KIAA0391", new_KIAA0391, clean_dat$gene)

# need to remove the dash for IL-XXXX 
clean_dat_no_il <- clean_dat[!grepl("IL-", clean_dat$gene),]
clean_dat_il <- clean_dat[grepl("IL-", clean_dat$gene),]
clean_dat_il$gene <- gsub("-", "", clean_dat_il$gene)
clean_dat <- bind_rows(clean_dat_no_il, clean_dat_il)

## Add in FLG to clean_dat as not included
flg_dat <- tibble(rank = NA, gene = "FLG")
clean_dat <- bind_rows(clean_dat, flg_dat)

## Combine datasets to get positions for genes
gene_dat <- clean_dat %>%
	left_join(all_genes, by = c("gene" = "hgnc_symbol")) %>%
	dplyr::select(rank, gene, chromosome = chromosome_name, start_position, end_position)

## Write out cleaned gene data
write.table(gene_dat, file = clean_outfile, col.names = T, row.names = F, quote = F, sep = "\t")

## Think about how to actually extract the data
gene_dat <- gene_dat %>%
	mutate(new_start = start_position - 1e6, new_end = end_position + 1e6)

x=1
mapped_cpgs <- lapply(1:nrow(gene_dat), function(x) {
	gd <- gene_dat[x, ]
	cpgs_within_gene <- between(mef_probe_info$position, gd$new_start, gd$new_end)
	if (sum(cpgs_within_gene) == 0) return(NULL)
	cpg_dat <- mef_probe_info %>%
		dplyr::filter(cpgs_within_gene, chromosome == gd$chromosome) %>%
		mutate(gene = gd$gene, rank = gd$rank) %>%
		distinct()
	return(cpg_dat)
})
mapped_cpgs <- bind_rows(mapped_cpgs)

table(mapped_cpgs$rank)
 # first second  third
 # 27245  27448  26844

## There are 27K near the first ranked gene so I think keeping to that would be fine

## Write out the cpgs, genes and positions
write.table(mapped_cpgs, file = cpg_genes_output, col.names = T, row.names = F, quote = F, sep = "\t")




























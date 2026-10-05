# ==============================================================================
# Giovanni Parrillo - Thesis replication package
# Pre-treatment balance and overlap diagnostics
# (writes output/balance.csv and output/balance_pscores.csv)
# ==============================================================================

.this_file <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
.script_dir <- if (!is.null(.this_file) && nzchar(.this_file)) {
  dirname(normalizePath(.this_file))
} else {
  getwd()
}
source(file.path(.script_dir, "config.R"))
rm(.this_file, .script_dir)

d <- prepare_data()
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
bal <- balance_table(d)
write_csv(bal$balance, file.path(OUT, "balance.csv"))
write_csv(bal$pscores, file.path(OUT, "balance_pscores.csv"))

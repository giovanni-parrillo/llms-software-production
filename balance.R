# ==============================================================================
# Giovanni Parrillo - Thesis replication package
# Pre-treatment balance and overlap diagnostics
# (writes output/balance.csv and output/balance_pscores.csv)
# ==============================================================================

source("config.R")

d <- prepare_data()
bal <- balance_table(d)
write_csv(bal$balance, file.path(OUT, "balance.csv"))
write_csv(bal$pscores, file.path(OUT, "balance_pscores.csv"))

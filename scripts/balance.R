# ==============================================================================
# Giovanni Parrillo - Thesis replication package
# Pre-treatment balance and overlap diagnostics
# (writes output/balance.csv, output/balance_pscores.csv and output/pre_means.csv)
# ==============================================================================

source("config.R")

d <- prepare_data()
bal <- balance_table(d)
write_csv(bal$balance, file.path(OUT, "balance.csv"))
write_csv(bal$pscores, file.path(OUT, "balance_pscores.csv"))

# Treated repositories' outcomes in the six months before adoption, 6m baseline sample
pre <- filter(d$p6, gname > 0, period >= gname - 6, period < gname)
pre_means <- bind_rows(lapply(retained_outcomes, function(y) {
  x <- pre[[y]]
  tibble(
    outcome = y,
    mean = mean(x, na.rm = TRUE),
    median = median(x, na.rm = TRUE),
    n_repositories = n_distinct(pre$repo[!is.na(x)])
  )
}))
write_csv(pre_means, file.path(OUT, "pre_means.csv"))

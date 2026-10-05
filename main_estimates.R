# ==============================================================================
# Giovanni Parrillo - Thesis replication package
# Main CS-DiD estimates and static TWFE comparison
# ==============================================================================

.this_file <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
.script_dir <- if (!is.null(.this_file) && nzchar(.this_file)) {
  dirname(normalizePath(.this_file))
} else {
  getwd()
}
source(file.path(.script_dir, "config.R"))
rm(.this_file, .script_dir)


# Construct the panel once using prepare_data()
d <- prepare_data()
specs <- specifications(d)


# ------------------------------------------------------------------------------
# 1. Callaway-Sant'Anna estimates
# ------------------------------------------------------------------------------
main <- run_cs(
  specs = specs,
  ys = retained_outcomes,
  analysis = "main CS-DiD",
  object_dir = file.path(OUT, "objects", "main")
)
write_csv(main, file.path(OUT, "main_cs.csv"))

# ------------------------------------------------------------------------------
# 2. Conventional static two-way fixed effects
# ------------------------------------------------------------------------------

library(fixest)

twfe_data <- d$p6 |>
  mutate(post = as.integer(gname > 0 & period >= gname)) # Indicator for post-treatment

twfe <- lapply(retained_outcomes, function(y) {
  dat_y <- twfe_data |>
    filter(!is.na(.data[[y]]))

  f <- as.formula(paste0(y, " ~ post | id + period")) # Construct regression formula 
  m <- feols(
    f,
    data = dat_y,
    cluster = ~id, # Cluster standard errors at the repository level
    warn = FALSE,
    notes = FALSE
  )

  est <- unname(coef(m)["post"]) # Extract the estimate for the post-treatment indicator
  std <- unname(se(m)["post"]) # Extract the standard error for the post-treatment indicator

  tibble( # Create a summary tibble for the results
    analysis = "static TWFE",
    outcome = y,
    term = "post",
    estimate = est,
    se = std,
    conf_low = est - Z95 * std,
    conf_high = est + Z95 * std,
    n_observations = nobs(m),
    n_repositories = n_distinct(dat_y$id),
    n_treated_repositories = n_distinct(dat_y$id[dat_y$gname > 0]),
    n_control_repositories = n_distinct(dat_y$id[dat_y$gname == 0])
  )
}) |>
  bind_rows()

write_csv(twfe, file.path(OUT, "twfe_static.csv"))

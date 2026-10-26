# ==============================================================================
# Giovanni Parrillo - Thesis replication package
# Main CS-DiD estimates and static TWFE comparison
# ==============================================================================

source("config.R")

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

# Role-flow outcomes with the core covering 30% and 50% instead of 75% (main specification)
sensitivity <- bind_rows(lapply(c(0.3, 0.5), function(coverage) {
  run_cs(
    specs = specifications(prepare_data(role_flows_at(coverage)))["main_spec"],
    ys = intersect(ROLE_FLOW_OUTCOMES, retained_outcomes),
    analysis = sprintf("core coverage %d%%", round(100 * coverage))
  )
}))
main <- bind_rows(main, sensitivity)
write_csv(main, file.path(OUT, "main_cs.csv"))

# ------------------------------------------------------------------------------
# 2. Conventional static two-way fixed effects
# ------------------------------------------------------------------------------
twfe_data <- d$p6 |>
  mutate(post = as.integer(gname > 0 & period >= gname))

twfe <- lapply(retained_outcomes, function(y) {
  dat_y <- twfe_data |>
    filter(!is.na(.data[[y]]))

  m <- feols(
    as.formula(paste0(y, " ~ post | id + period")),
    data = dat_y,
    cluster = ~id,
    warn = FALSE,
    notes = FALSE
  )

  est <- unname(coef(m)["post"])
  std <- unname(se(m)["post"])

  tibble(
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

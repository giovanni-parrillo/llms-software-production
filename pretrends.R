# ==============================================================================
# Event-time estimates for the main specification
# ==============================================================================
# Aggregate ATT by event time e for every retained outcome, with the pointwise standard error and the
# uniform critical value. The base period is "varying": pre-treatment estimates are one-period changes,
# so the estimate at e = -1 is not normalised to zero.

source("config.R")

E_RANGE <- c(-6, 6)

d <- prepare_data()
spec <- specifications(d)$main_spec

dynamic <- bind_rows(lapply(retained_outcomes, function(y) {
  message("Event time - ", y)
  dyn <- aggte(fit_cs(spec$data, y, spec$x), type = "dynamic", min_e = E_RANGE[1], max_e = E_RANGE[2], na.rm = TRUE)
  tibble(outcome = y, e = dyn$egt, att = dyn$att.egt, se = dyn$se.egt, crit_val = dyn$crit.val.egt)
}))

write_csv(dynamic, file.path(OUT, "dynamic_cs.csv"))

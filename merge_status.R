# ==============================================================================
# Review-role flows by pull-request merge status
# ==============================================================================
# CS-DiD estimates of the role-flow outcomes computed separately on interactions with merged and
# unmerged PRs. The core is defined within each set. Interactions are dated by review month.

source("config.R")

by_status <- bind_rows(lapply(c(merged = 1, unmerged = 0), function(merged) {
  flows <- build_role_flows(
    file.path(DATA_DIR, "author_reviewer_edges_by_status.csv.gz"),
    Sys.getenv("ROLE_TYPES", file.path(DATA_DIR, "login_types.csv")),
    freeze = core_freeze(),
    coverage = CORE_COVERAGE,
    merged = merged
  )
  run_cs(
    specs = specifications(prepare_data(flows))[c("main_spec", "baseline6m_raw")],
    ys = ROLE_FLOW_OUTCOMES,
    analysis = "role flows by merge status"
  )
}), .id = "pr_status")

write_csv(by_status, file.path(OUT, "role_flows_by_status.csv"))

# ==============================================================================
# Giovanni Parrillo - Thesis replication package
# Shared configuration and helper functions
# ==============================================================================

library(dplyr)
library(readr)
library(did)
library(fixest)

# ------------------------------------------------------------------------------
# 1. Paths and run-time options
# ------------------------------------------------------------------------------

# Scripts are run from the package root (run_all.R changes to it).
PROJECT_DIR <- normalizePath(getwd())
DATA_DIR <- file.path(PROJECT_DIR, "data")
OUT <- Sys.getenv("OUTPUT_DIR", file.path(PROJECT_DIR, "output"))
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

source(file.path(PROJECT_DIR, "role_flows.R"))

# SAVE_OBJECTS=1 keeps the fitted did objects in output/objects (large).
SAVE_OBJECTS <- identical(Sys.getenv("SAVE_OBJECTS", "0"), "1")

# Multiplier-bootstrap settings for did::att_gt()
BITERS <- as.integer(Sys.getenv("DID_BITERS", "1000"))
CORES  <- as.integer(Sys.getenv("DID_CORES", "1"))
SEED   <- as.integer(Sys.getenv("DID_SEED", "42"))
Z95    <- qnorm(.975)

# ------------------------------------------------------------------------------
# 2. Outcome sets
# ------------------------------------------------------------------------------

retained_outcomes <- c(
  # H1: candidate production
  "opened_prs",
  "share_ai_traced_prs",

  # H2: human validation and integrative capacity
  "opened_prs_per_active_reviewer_excl_bots",
  "log_human_reviews_per_reviewer",
  "reviews_by_human_reviewer",
  "merged_prs",
  "median_time_to_merge_days",
  "median_time_to_first_review_days_excl_bots",
  "unique_reviewers_excl_bots",

  # H3: participation and peripheral entry
  "first_time_author_share",
  "first_time_author_acceptance_rate",

  # H4: validation authority
  "approver_hhi_excl_bots",
  "reviews_by_llm_bot_reviewer",
  ROLE_FLOW_OUTCOMES,

  # H5: familiarity, exploration and socio-technical coordination
  "tc_author_experience_share_file",
  "tc_author_experience_share_folder",
  "tc_novel_unit_share_file",
  "tc_novel_unit_share_folder",
  "log_burden_mean_folder",
  "log_burden_mean_file",
  "tc_reviewer_coverage_share_file",
  "tc_reviewer_coverage_share_folder",
  "tc_mean_weighted_congruence_file",
  "tc_mean_weighted_congruence_folder"
)

# DID_OUTCOMES (comma-separated) restricts every run to a subset of the retained
# outcomes; unset runs them all.
if (nzchar(Sys.getenv("DID_OUTCOMES"))) {
  .sel <- trimws(strsplit(Sys.getenv("DID_OUTCOMES"), ",")[[1]])
  stopifnot(all(.sel %in% retained_outcomes))
  retained_outcomes <- .sel
  rm(.sel)
}

# ------------------------------------------------------------------------------
# 3. Basic date helpers and baseline covariates
# ------------------------------------------------------------------------------

# Convert YYYY-MM or any string beginning with YYYY-MM to an integer month index
ym_period <- function(x) {
  x <- as.character(x)
  as.integer(substr(x, 1, 4)) * 12 + as.integer(substr(x, 6, 7))
}

# Fixed-window pre-treatment covariate: log(1 + mean PRs opened) over the window.
# A repository is kept only if every calendar month in the window is observed.
baseline_pr <- function(panel, start, end, name) {
  months <- ym_period(c(start, end))
  z <- panel |>
    filter(period >= months[1], period <= months[2]) |>
    group_by(repo) |>
    summarise(
      n_months = n_distinct(period),
      value = log1p(mean(opened_prs)),
      .groups = "drop"
    ) |>
    filter(n_months == diff(months) + 1) |>
    select(repo, value)
  names(z)[2] <- name
  z
}

# ------------------------------------------------------------------------------
# 4. Canonical data construction
# ------------------------------------------------------------------------------

# The role-flow build takes minutes and is identical across steps, so it is
# computed once per R session and reused by every call to prepare_data().
# Scripts source this file again, so the cache must not be reset on re-sourcing.
if (!exists(".role_flow_cache", envir = globalenv(), inherits = FALSE)) {
  .role_flow_cache <- NULL
}
role_flows_cached <- function() {
  if (is.null(.role_flow_cache)) {
    .role_flow_cache <<- build_role_flows(
      file.path(DATA_DIR, "author_reviewer_edges.csv.gz"),
      Sys.getenv("ROLE_TYPES", file.path(DATA_DIR, "login_types.csv"))
    )
  }
  .role_flow_cache
}

prepare_data <- function() {
  panel <- read_csv(file.path(DATA_DIR, "repo_month.csv"), show_col_types = FALSE)
  master <- read_csv(file.path(DATA_DIR, "repo_master.csv"), show_col_types = FALSE)

  # Treatment timing is the first validated AI-enablement month.  Never-treated
  # repositories use gname = 0, the convention expected by did.
  created <- ym_period(master$created_at)
  names(created) <- master$repo

  panel <- panel |>
    mutate(
      period = ym_period(month),
      id = as.integer(factor(repo)),
      gname = if_else(is.na(first_ai_month), 0, ym_period(first_ai_month))
    ) |>
    filter(is.na(created[repo]) | period >= created[repo]) |>
    mutate(
      log_burden_mean_folder = log1p(tc_mean_coordination_burden_per_pr_folder),
      log_burden_mean_file = log1p(tc_mean_coordination_burden_per_pr_file),
      # Human review submissions per active non-bot reviewer; undefined (NA) in
      # months with no active reviewer.
      log_human_reviews_per_reviewer = log1p(if_else(
        unique_reviewers_excl_bots > 0,
        reviews_by_human_reviewer / unique_reviewers_excl_bots,
        NA_real_
      ))
    )

  pr6 <- baseline_pr(panel, "2022-12", "2023-05", "pr_activity_6m")
  pr3 <- baseline_pr(panel, "2023-03", "2023-05", "pr_activity_3m")

  owners <- master |>
    transmute(
      repo,
      owner = trimws(tolower(owner)),
      noncompany_governance = 1 - (tolower(owner_entity_type) == "company")
    )

  panel <- panel |>
    select(-any_of("owner")) |>
    left_join(pr6, by = "repo") |>
    left_join(pr3, by = "repo") |>
    left_join(owners, by = "repo") |>
    left_join(role_flows_cached(), by = c("repo", "month"))

  # Catch accidental joins or duplicates before they contaminate a DiD estimate.
  if (anyDuplicated(panel[c("repo", "period")])) {
    stop("repo_month.csv contains duplicate repository-month rows after preparation.")
  }
  cohort_check <- panel |> distinct(repo, gname) |> count(repo) |> filter(n != 1)
  if (nrow(cohort_check) > 0) {
    stop("Treatment cohort is not constant within repository for ", nrow(cohort_check), " repositories.")
  }

  # Samples used by the three families of adjustment specifications.
  p6 <- filter(panel, !is.na(pr_activity_6m))
  p3 <- filter(panel, !is.na(pr_activity_3m))
  p6_gov <- filter(p6, !is.na(noncompany_governance))
  p3_gov <- filter(p3, !is.na(noncompany_governance))


  list(
    full = panel,
    p6 = p6,
    p3 = p3,
    p6_gov = p6_gov,
    p3_gov = p3_gov,
    master = master
  )
}

# ------------------------------------------------------------------------------
# 5. Specifications
# ------------------------------------------------------------------------------

specifications <- function(d) list(

  # 1. Unadjusted estimate on the full eligible outcome sample.
  full_sample = list(data = d$full),

  # 2. Unadjusted estimate restricted to repositories with the 6m baseline.
  baseline6m_raw = list(data = d$p6),

  # 3. Primary adjusted estimate: 6m baseline activity only.
  main_spec = list(data = d$p6, x = ~pr_activity_6m),

  # 4. Robustness extension adding observed company/non-company governance.
  #    Missing governance is excluded rather than imputed as non-company.
  baseline6m_gov = list(
    data = d$p6_gov,
    x = ~pr_activity_6m + noncompany_governance
  ),

  # 5-7. Three-month-window counterparts.
  baseline3m_raw = list(data = d$p3, x = ~1),
  baseline3m_adj = list(data = d$p3, x = ~pr_activity_3m),
  baseline3m_gov = list(
    data = d$p3_gov,
    x = ~pr_activity_3m + noncompany_governance
  )
)

# ------------------------------------------------------------------------------
# 6. CS-DiD estimation wrappers
# ------------------------------------------------------------------------------

fit_cs <- function(data, outcome, x, control = "notyettreated", est_method = "dr") {
  set.seed(SEED)
  att_gt(
    yname = outcome,
    tname = "period",
    idname = "id",
    gname = "gname",
    xformla = x,
    data = data,
    panel = TRUE,
    allow_unbalanced_panel = TRUE,
    control_group = control,
    anticipation = 0,
    base_period = "varying",
    est_method = est_method, # "dr" = doubly robust (default), "ipw" = inverse probability weighting
    bstrap = TRUE,
    biters = BITERS,
    cband = TRUE,
    cores = CORES
  )
}

# Extract the aggregate simple ATT and bootstrapped SEs
simple_result <- function(object, specification, outcome, analysis) {
  a <- aggte(object, type = "simple", na.rm = TRUE)
  used <- object$DIDparams$data
  used_ids <- unique(used$id)

  att <- unname(a$overall.att)
  se <- unname(a$overall.se)

  tibble(
    analysis = analysis,
    specification = specification,
    outcome = outcome,
    att = att,
    se = se,
    conf_low = att - Z95 * se,
    conf_high = att + Z95 * se,
    n_observations = nrow(used),
    n_repositories = length(used_ids)
  )
}

# Fit every specification and outcome combination; return one row per fit
run_cs <- function(specs, ys, analysis, object_dir = NULL) {
  save_objects <- SAVE_OBJECTS && !is.null(object_dir)
  if (save_objects) dir.create(object_dir, recursive = TRUE, showWarnings = FALSE)

  grid <- expand.grid(y = ys, s = names(specs), stringsAsFactors = FALSE)  # specification-major order
  bind_rows(lapply(seq_len(nrow(grid)), function(i) {
    s <- grid$s[i]; y <- grid$y[i]
    message(sprintf("Fitting %s - %s ...", s, y))
    spec <- specs[[s]]
    object <- fit_cs(
      data = spec$data,
      outcome = y,
      x = spec$x,
      control = spec$control %||% "notyettreated",
      est_method = spec$est_method %||% "dr"
    )

    if (save_objects) {
      saveRDS(object, file.path(object_dir, paste0(s, "__", y, ".rds")))
    }

    simple_result(object = object, specification = s, outcome = y, analysis = analysis)
  }))
}

# ------------------------------------------------------------------------------
# 7. Pre-treatment balance and overlap diagnostics
# ------------------------------------------------------------------------------

# Repository-level balance on the baseline covariates used by the adjusted
# specifications, treated (ever AI-enabled) versus never-treated, on the 6m
# baseline sample.  Also reports the logit propensity score for ever-treated
# on pr_activity_6m, the quantity IPW reweights on.
balance_table <- function(d) {
  units <- d$p6 |>
    distinct(repo, gname, pr_activity_6m, noncompany_governance) |>
    mutate(ever_treated = as.integer(gname > 0))

  smd <- function(x, g) {
    x1 <- x[g == 1]; x0 <- x[g == 0]
    (mean(x1, na.rm = TRUE) - mean(x0, na.rm = TRUE)) /
      sqrt((var(x1, na.rm = TRUE) + var(x0, na.rm = TRUE)) / 2)
  }

  covs <- c("pr_activity_6m", "noncompany_governance")
  bal <- bind_rows(lapply(covs, function(v) {
    x <- units[[v]]; g <- units$ever_treated; ok <- !is.na(x)
    tibble(
      section = "covariate_balance",
      variable = v,
      n_treated = sum(g[ok] == 1),
      n_control = sum(g[ok] == 0),
      mean_treated = mean(x[ok & g == 1]),
      mean_control = mean(x[ok & g == 0]),
      sd_treated = sd(x[ok & g == 1]),
      sd_control = sd(x[ok & g == 0]),
      std_mean_diff = smd(x[ok], g[ok])
    )
  }))

  # Propensity score overlap (ever-treated vs never-treated)
  ps_fit <- glm(ever_treated ~ pr_activity_6m, data = units, family = binomial())
  units$ps <- fitted(ps_fit)
  lo <- max(tapply(units$ps, units$ever_treated, min))
  hi <- min(tapply(units$ps, units$ever_treated, max))
  overlap <- bind_rows(lapply(c(0, 1), function(g) {
    p <- units$ps[units$ever_treated == g]
    tibble(
      section = "propensity_overlap",
      variable = if (g == 1) "pscore_treated" else "pscore_control",
      n_treated = if (g == 1) length(p) else NA_integer_,
      n_control = if (g == 0) length(p) else NA_integer_,
      mean_treated = if (g == 1) mean(p) else NA_real_,
      mean_control = if (g == 0) mean(p) else NA_real_,
      sd_treated = if (g == 1) sd(p) else NA_real_,
      sd_control = if (g == 0) sd(p) else NA_real_,
      p01 = unname(quantile(p, .01)), p05 = unname(quantile(p, .05)),
      p50 = median(p), p95 = unname(quantile(p, .95)),
      p99 = unname(quantile(p, .99)),
      min = min(p), max = max(p),
      share_outside_common_support = mean(p < lo | p > hi),
      share_pscore_above_0.95 = mean(p > .95)
    )
  }))

  # Unit-level scores, for the common-support plot
  pscores <- units |>
    transmute(repo, ever_treated, pscore = ps, in_common_support = ps >= lo & ps <= hi)

  list(balance = bind_rows(bal, overlap), pscores = pscores)
}

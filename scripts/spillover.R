# ==============================================================================
# Spillover analysis
#
# Effect of moving from untreated and unexposed to untreated and exposed, for
# repositories that have not yet adopted. Exposure means that another repository
# has adopted, and is defined in two ways:
#   A. within owner: another repository of the same owner adopts;
#   B. cross owner: a network sibling adopts. A sibling is a repository of a
#      different owner with at least two shared reviewers or approvers and an
#      overlap coefficient above tau. The network is built once, from reviewers
#      active up to NET_END, and held fixed.
# The first exposure month plays the role of the adoption cohort in CS-DiD.
# Controls are repositories not yet exposed. Observations are censored at a
# repository's own adoption.
# ==============================================================================

source("config.R")
d <- prepare_data()

NET_END    <- ym_period("2023-05")
MIN_SHARED <- 2L
THRESHOLDS <- c(0.2, 0.3)
E_RANGE    <- c(-12, 12)

repos <- d$full |>
  distinct(repo, owner, gname) |>
  mutate(owner = if_else(is.na(owner) | owner == "", paste0("__repo__", repo), owner))
adoption_month <- setNames(ifelse(repos$gname > 0, repos$gname, Inf), repos$repo)

# Panel with each repository exposed from exposure_month (named by repo; Inf = never exposed)
exposure_panel <- function(exposure_month) {
  d$p6 |>
    mutate(exposure = unname(exposure_month[repo]),
           exposure = if_else(is.finite(exposure), exposure, Inf)) |>
    filter(gname == 0 | period < gname) |>
    mutate(gname_own = gname,
           gname = if_else(is.finite(exposure) & (gname_own == 0 | exposure < gname_own), exposure, 0))
}

fit_spill <- function(data, analysis, ys) {
  bind_rows(lapply(ys, function(y) {
    message(sprintf("Fitting %s - %s ...", analysis, y))
    fit <- fit_cs(data, y, ~pr_activity_6m)
    out <- list(
      simple = aggte(fit, type = "simple", na.rm = TRUE),
      dynamic = aggte(fit, type = "dynamic", min_e = E_RANGE[1], max_e = E_RANGE[2], na.rm = TRUE)
    )
    bind_rows(
      tibble(type = "simple", e = NA_real_, att = out$simple$overall.att, se = out$simple$overall.se),
      tibble(type = "dynamic", e = out$dynamic$egt, att = out$dynamic$att.egt, se = out$dynamic$se.egt)
    ) |> mutate(analysis = analysis, outcome = y,
                n_exposed = n_distinct(data$repo[data$gname > 0]),
                n_control = n_distinct(data$repo[data$gname == 0]), .before = 1)
  }))
}

# --- A. within owner ---------------------------------------------------------
owner_exposure <- repos |>
  mutate(exposure = vapply(seq_len(n()), function(i) min(adoption_month[repo[-i]], Inf), numeric(1)),
         .by = owner) |>
  with(setNames(exposure, repo))
write_csv(fit_spill(exposure_panel(owner_exposure), "within-owner", retained_outcomes),
          file.path(OUT, "spillover_within_owner.csv"))

# --- B. cross owner ----------------------------------------------------------
# Reviewers and approvers of each repository: humans whose first review or
# approval there is on or before NET_END.
reviewers <- read_csv(file.path(DATA_DIR, "actor_repo.csv"), show_col_types = FALSE) |>
  filter(actor_type == "human") |>
  mutate(first_rev = pmin(first_review_date, first_approval_date, na.rm = TRUE)) |>
  filter(!is.na(first_rev), ym_period(format(first_rev, "%Y-%m")) <= NET_END) |>
  distinct(repo, login)

reviewer_counts <- count(reviewers, repo, name = "n")

# Overlap is measured against the smaller of the two reviewer sets.
sibling_pairs <- inner_join(reviewers, reviewers, by = "login", relationship = "many-to-many") |>
  filter(repo.x < repo.y) |>
  count(repo.x, repo.y, name = "shared") |>
  filter(shared >= MIN_SHARED) |>
  mutate(overlap = shared / pmin(reviewer_counts$n[match(repo.x, reviewer_counts$repo)],
                                 reviewer_counts$n[match(repo.y, reviewer_counts$repo)])) |>
  left_join(select(repos, repo, owner), by = c(repo.x = "repo")) |>
  left_join(select(repos, repo, owner), by = c(repo.y = "repo"), suffix = c(".x", ".y")) |>
  filter(owner.x != owner.y)
sibling_pairs <- bind_rows(sibling_pairs, rename(sibling_pairs, repo.x = repo.y, repo.y = repo.x))

net_stats <- list()
cross_owner_results <- list()
for (tau in THRESHOLDS) {
  net_exposure <- sibling_pairs |>
    filter(overlap > tau) |>
    summarise(exposure = min(adoption_month[repo.y]), n_sib = n(), .by = repo.x)
  exposure_all <- setNames(rep(Inf, nrow(repos)), repos$repo)
  exposure_all[net_exposure$repo.x] <- net_exposure$exposure

  panel <- exposure_panel(exposure_all)
  sample_units <- distinct(panel, repo, gname, gname_own)
  net_stats[[length(net_stats) + 1]] <- tibble(
    tau = tau,
    repos_sample = nrow(sample_units),
    repos_with_sibling = sum(sample_units$repo %in% net_exposure$repo.x),
    repos_with_treated_sibling = sum(sample_units$repo %in% net_exposure$repo.x[is.finite(net_exposure$exposure)]),
    repos_exposed_untreated = sum(sample_units$gname > 0),
    exposed_never_treated = sum(sample_units$gname > 0 & sample_units$gname_own == 0),
    exposed_later_treated = sum(sample_units$gname > 0 & sample_units$gname_own > 0),
    unexposed_controls = sum(sample_units$gname == 0),
    median_siblings = median(net_exposure$n_sib),
    reviewer_set_median = median(reviewer_counts$n)
  )
  cross_owner_results[[length(cross_owner_results) + 1]] <-
    fit_spill(panel, paste0("cross-owner overlap>", tau), retained_outcomes)
}
write_csv(bind_rows(net_stats), file.path(OUT, "spillover_network_stats.csv"))
write_csv(bind_rows(cross_owner_results), file.path(OUT, "spillover_cross_owner.csv"))

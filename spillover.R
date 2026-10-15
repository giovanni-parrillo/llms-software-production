# ==============================================================================
# Spillover analysis: effect of (D=0,H=0) -> (D=0,H=1) on still-untreated repos
#   A. within-owner: S_i = first adoption by another repo of the same owner
#   B. cross-owner:  S_i = first adoption by a network sibling (different owner,
#      >= 2 shared reviewers/approvers, overlap coefficient > tau, measured
#      once up to NET_END and kept fixed)
# Exposure date S_i plays the role of the cohort in CS-DiD; controls are
# not-yet-exposed repos; observations are censored at own adoption.
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
G <- setNames(ifelse(repos$gname > 0, repos$gname, Inf), repos$repo)  # adoption month

# Exposure panel from S (named by repo; Inf = never exposed)
exposure_panel <- function(S) {
  d$p6 |>
    mutate(S = unname(S[repo]), S = if_else(is.finite(S), S, Inf)) |>
    filter(gname == 0 | period < gname) |>                  # censor at own adoption
    mutate(gname_own = gname,
           gname = if_else(is.finite(S) & (gname_own == 0 | S < gname_own), S, 0))
}

fit_spill <- function(data, analysis, ys) {
  bind_rows(lapply(ys, function(y) {
    message(sprintf("Fitting %s - %s ...", analysis, y))
    fit <- fit_cs(data, y, ~pr_activity_6m)
    out <- list(
      s = aggte(fit, type = "simple", na.rm = TRUE),
      dyn = aggte(fit, type = "dynamic", min_e = E_RANGE[1], max_e = E_RANGE[2], na.rm = TRUE)
    )
    bind_rows(
      tibble(type = "simple", e = NA_real_, att = out$s$overall.att, se = out$s$overall.se),
      tibble(type = "dynamic", e = out$dyn$egt, att = out$dyn$att.egt, se = out$dyn$se.egt)
    ) |> mutate(analysis = analysis, outcome = y,
                n_exposed = n_distinct(data$repo[data$gname > 0]),
                n_control = n_distinct(data$repo[data$gname == 0]), .before = 1)
  }))
}

# --- A. within owner ---------------------------------------------------------
S_owner <- repos |>
  mutate(S = vapply(seq_len(n()), function(i) min(G[repo[-i]], Inf), numeric(1)), .by = owner) |>
  with(setNames(S, repo))
write_csv(fit_spill(exposure_panel(S_owner), "within-owner", retained_outcomes),
          file.path(OUT, "spillover_within_owner.csv"))

# --- B. cross owner ----------------------------------------------------------
# Reviewer/approver set of each repo: humans whose first review or approval in
# that repo is on or before NET_END
pre <- read_csv(file.path(DATA_DIR, "actor_repo.csv"), show_col_types = FALSE) |>
  filter(actor_type == "human") |>
  mutate(first_rev = pmin(first_review_date, first_approval_date, na.rm = TRUE)) |>
  filter(!is.na(first_rev), ym_period(format(first_rev, "%Y-%m")) <= NET_END) |>
  distinct(repo, login)

size <- count(pre, repo, name = "n")
pairs <- inner_join(pre, pre, by = "login", relationship = "many-to-many") |>
  filter(repo.x < repo.y) |>
  count(repo.x, repo.y, name = "shared") |>
  filter(shared >= MIN_SHARED) |>
  mutate(overlap = shared / pmin(size$n[match(repo.x, size$repo)],
                                 size$n[match(repo.y, size$repo)])) |>   # overlap coefficient
  left_join(select(repos, repo, owner), by = c(repo.x = "repo")) |>
  left_join(select(repos, repo, owner), by = c(repo.y = "repo"), suffix = c(".x", ".y")) |>
  filter(owner.x != owner.y)
pairs <- bind_rows(pairs, rename(pairs, repo.x = repo.y, repo.y = repo.x))  # symmetric

net_stats <- list(); res <- list()
for (k in THRESHOLDS) {
  S_net <- pairs |>
    filter(overlap > k) |>
    summarise(S = min(G[repo.y]), n_sib = n(), .by = repo.x)
  S_all <- setNames(rep(Inf, nrow(repos)), repos$repo)
  S_all[S_net$repo.x] <- S_net$S
  panel <- exposure_panel(S_all)
  u <- distinct(panel, repo, gname, gname_own)
  net_stats[[length(net_stats) + 1]] <- tibble(
    tau = k,
    repos_sample = nrow(u),
    repos_with_sibling = sum(u$repo %in% S_net$repo.x),
    repos_with_treated_sibling = sum(u$repo %in% S_net$repo.x[is.finite(S_net$S)]),
    repos_exposed_untreated = sum(u$gname > 0),
    exposed_never_treated = sum(u$gname > 0 & u$gname_own == 0),
    exposed_later_treated = sum(u$gname > 0 & u$gname_own > 0),
    unexposed_controls = sum(u$gname == 0),
    median_siblings = median(S_net$n_sib),
    reviewer_set_median = median(size$n))
  res[[length(res) + 1]] <- fit_spill(panel, paste0("cross-owner overlap>", k), retained_outcomes)
}
write_csv(bind_rows(net_stats), file.path(OUT, "spillover_network_stats.csv"))
write_csv(bind_rows(res), file.path(OUT, "spillover_cross_owner.csv"))

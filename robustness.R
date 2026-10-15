# ==============================================================================
# Giovanni Parrillo - Thesis replication package
# Robustness and falsification exercises
# ==============================================================================
# Three of the four robustness exercises of Section 6.3 of the thesis
# (the fourth, the spillover analysis, is in spillover.R):
#   A. never-treated comparison group;
#   B. owner-clean comparison pool (controls exposed through common ownership removed);
#   C. three-month lead placebo restricted to genuinely pre-treatment data.


source("config.R")
d <- prepare_data()

if (!SAVE_OBJECTS) {
  unlink(file.path(OUT, "objects"), recursive = TRUE, force = TRUE)
}

# ------------------------------------------------------------------------------
# A. Never-treated-only comparison group
# ------------------------------------------------------------------------------
# The main estimate uses not-yet-treated + never-treated controls.  This exercise
# changes only the comparison set; the treatment definition, outcome variables,
# covariate adjustment and aggregation remain the same.
never_specs <- list(
  main_spec_never = list(
    data = d$p6,
    x = ~pr_activity_6m,
    control = "nevertreated"
  )
)

r_never <- run_cs(
  specs = never_specs,
  ys = retained_outcomes,
  analysis = "never-treated controls",
  object_dir = file.path(OUT, "objects", "never_treated")
)

# ------------------------------------------------------------------------------
# B. Owner-clean controls
# ------------------------------------------------------------------------------
# A formally untreated repository is not an uncontaminated control if another
# repository owned by the same observed GitHub owner is treated somewhere in
# the analysis sample.  Treated repositories themselves are always retained;
# only potential controls are removed.
owner_status <- d$full |>
  distinct(repo, owner, gname) |>
  mutate(
    # Missing/blank owner strings do not constitute evidence of common
    # ownership.  Give such repositories a repository-specific key so they are
    # not spuriously treated as one giant shared-owner cluster.
    owner_key = if_else(is.na(owner) | owner == "", paste0("__repo__", repo), owner)
  )

treated_owners <- owner_status |>
  filter(gname > 0) |>
  distinct(owner_key) |>
  pull(owner_key)

keep_repos <- owner_status |>
  filter(repo %in% d$p6$repo) |>
  filter(gname > 0 | !(owner_key %in% treated_owners)) |>
  pull(repo)

spill <- d$p6 |>
  filter(repo %in% keep_repos)

# These checks document the intended comparison-pool restriction for the
# bundled canonical data.  They do not affect estimation.
if (!identical(Sys.getenv("STRICT_DATA_CHECKS", "1"), "0")) {
  stopifnot(
    n_distinct(spill$repo[spill$gname > 0]) == 292L,
    n_distinct(spill$repo[spill$gname == 0]) == 374L
  )
}

r_spill <- run_cs(
  specs = list(
    main_spec_owner_clean = list(
      data = spill,
      x = ~pr_activity_6m
    )
  ),
  ys = retained_outcomes,
  analysis = "owner-clean controls",
  object_dir = file.path(OUT, "objects", "owner_spillover")
)

# ------------------------------------------------------------------------------
# C. Three-month lead placebo
# ------------------------------------------------------------------------------
# Each treated repository receives a fictitious adoption month three months
# before its actual adoption.  Crucially, observations at/after the REAL
# adoption date are removed before estimation, so the placebo post interval
# contains no genuinely post-treatment observations.
units <- d$p6 |>
  distinct(repo, id, gname)

eligible <- units |>
  filter(gname > 0) |>
  mutate(fake_g = gname - 3L) |>
  inner_join(d$p6 |> select(repo, period), by = "repo") |>
  # Require at least three observed months before the fictitious treatment.
  filter(period < fake_g) |>
  summarise(
    n_pre = n_distinct(period),
    .by = c(repo, id, gname, fake_g)
  ) |>
  filter(n_pre >= 3L)

placebo <- d$p6 |>
  filter(gname == 0 | repo %in% eligible$repo) |>
  mutate(
    real_gname = gname,
    gname = if_else(real_gname == 0L, 0L, real_gname - 3L)
  ) |>
  filter(real_gname == 0L | period < real_gname)

# The placebo deliberately uses no baseline-activity covariate: the fixed
# Dec-2022--May-2023 activity window is not entirely pre-placebo for every fake
# cohort, so conditioning on it would use information from the placebo "post"
# period.  Both not-yet-treated and never-treated comparison versions are shown.
placebo_specs <- list(
  placebo_notyet = list(
    data = placebo,
    x = ~1,
    control = "notyettreated"
  ),
  placebo_never = list(
    data = placebo,
    x = ~1,
    control = "nevertreated"
  )
)

r_placebo <- run_cs(
  specs = placebo_specs,
  ys = retained_outcomes,
  analysis = "three-month placebo",
  object_dir = file.path(OUT, "objects", "placebo")
)

write_csv(
  bind_rows(r_never, r_spill, r_placebo),
  file.path(OUT, "robustness.csv")
)

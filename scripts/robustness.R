# ==============================================================================
# Robustness exercises
#
#   A. never-treated comparison group;
#   B. owner-clean comparison pool: potential controls that share an owner with a
#      treated repository are removed;
#   C. three-month lead placebo, using only pre-treatment observations.
# The spillover analysis is a fourth exercise, in spillover.R.
# ==============================================================================

source("config.R")
d <- prepare_data()

if (!SAVE_OBJECTS) {
  unlink(file.path(OUT, "objects"), recursive = TRUE, force = TRUE)
}

# --- A. never-treated comparison group ---------------------------------------
# The main estimate compares with not-yet-treated and never-treated repositories.
# This exercise keeps only the never-treated ones; everything else is unchanged.
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

# --- B. owner-clean comparison pool -------------------------------------------
# An untreated repository is contaminated if another repository of the same
# observed owner is treated within the analysis sample. Treated repositories are
# always kept; only potential controls are removed.
owner_status <- d$full |>
  distinct(repo, owner, gname) |>
  mutate(
    # Blank owners are not evidence of common ownership. Give them a
    # repository-specific key so they do not form one shared-owner cluster.
    owner_key = if_else(is.na(owner) | owner == "", paste0("__repo__", repo), owner)
  )

treated_owners <- owner_status |>
  filter(gname > 0) |>
  distinct(owner_key) |>
  pull(owner_key)

owner_clean_repos <- owner_status |>
  filter(repo %in% d$p6$repo) |>
  filter(gname > 0 | !(owner_key %in% treated_owners)) |>
  pull(repo)

owner_clean_panel <- d$p6 |>
  filter(repo %in% owner_clean_repos)

# Expected repository counts for the bundled sample. They do not affect estimation.
if (!identical(Sys.getenv("STRICT_DATA_CHECKS", "1"), "0")) {
  stopifnot(
    n_distinct(owner_clean_panel$repo[owner_clean_panel$gname > 0]) == 292L,
    n_distinct(owner_clean_panel$repo[owner_clean_panel$gname == 0]) == 374L
  )
}

r_owner_clean <- run_cs(
  specs = list(
    main_spec_owner_clean = list(
      data = owner_clean_panel,
      x = ~pr_activity_6m
    )
  ),
  ys = retained_outcomes,
  analysis = "owner-clean controls",
  object_dir = file.path(OUT, "objects", "owner_spillover")
)

# --- C. three-month lead placebo ----------------------------------------------
# Each treated repository gets a fictitious adoption month three months before
# its actual one. Observations from the real adoption month onwards are removed
# first, so the placebo post-period contains no real post-treatment data.
units <- d$p6 |>
  distinct(repo, id, gname)

placebo_eligible <- units |>
  filter(gname > 0) |>
  mutate(fake_g = gname - 3L) |>
  inner_join(d$p6 |> select(repo, period), by = "repo") |>
  filter(period < fake_g) |>
  summarise(
    n_pre = n_distinct(period),
    .by = c(repo, id, gname, fake_g)
  ) |>
  filter(n_pre >= 3L)

placebo <- d$p6 |>
  filter(gname == 0 | repo %in% placebo_eligible$repo) |>
  mutate(
    real_gname = gname,
    gname = if_else(real_gname == 0L, 0L, real_gname - 3L)
  ) |>
  filter(real_gname == 0L | period < real_gname)

# No baseline-activity covariate: the fixed Dec 2022 to May 2023 window is not
# entirely before every fictitious adoption month, so adjusting for it would
# use information from the placebo post-period. Both comparison groups are shown.
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
  bind_rows(r_never, r_owner_clean, r_placebo),
  file.path(OUT, "robustness.csv")
)

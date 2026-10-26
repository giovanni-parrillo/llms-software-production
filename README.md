# LLMs and the reorganisation of software production

Replication package for the repository-level empirical analysis of Giovanni Parrillo's master's
thesis. The repository contains the analytical datasets, R scripts and estimation outputs for the
Callaway–Sant'Anna difference-in-differences analysis, the two-way fixed-effects comparison, balance
diagnostics, robustness checks, the spillover analysis, review-role flows by pull-request merge status
and event-time estimates.

## 1. Running the analysis

From the package root:

```bash
Rscript run_all.R
```

`run_all.R` changes to the package root and runs, in one R session:

1. `scripts/main_estimates.R`: CS-DiD estimates for all specifications (`main_cs.csv`) and static TWFE (`twfe_static.csv`).
2. `scripts/balance.R`: pre-treatment balance and overlap diagnostics (`balance.csv`, `balance_pscores.csv`).
3. `scripts/robustness.R`: never-treated, owner-clean and placebo exercises (`robustness.csv`).
4. `scripts/spillover.R`: within-owner and cross-owner spillover analysis (`spillover_*.csv`).
5. `scripts/merge_status.R`: role-flow estimates on interactions with merged and unmerged pull requests (`role_flows_by_status.csv`).
6. `scripts/event_study.R`: event-time estimates for the main specification (`dynamic_cs.csv`). All CS estimates use `base_period = "varying"`, so the pre-treatment estimates are one-period changes and the estimate at e = -1 is not normalised to zero.

Each script can also be run on its own with `Rscript scripts/<script>.R` from the package root. Generated files go to `output/`, which is created on the first run.

## 2. Data and anonymisation

### Data

- `data/repo_month.csv`: repository-month panel.
- `data/repo_master.csv`: repository attributes (owner, creation date, governance).
- `data/actor_repo.csv`: login-repository table with first review and approval dates, used for the cross-owner network. Logins are pseudonymised.
- `data/author_reviewer_edges.csv.gz`: author-reviewer interaction counts by repository and merged month (formal reviews and inline review comments, self-interactions excluded). Logins are pseudonymised. Gzip-compressed CSV, read directly by `readr`.
- `data/author_reviewer_edges_by_status.csv.gz`: author-reviewer interaction counts by repository, review month and pull-request merge status (formal reviews and inline review comments, self-interactions excluded), used by `scripts/merge_status.R`. Logins are pseudonymised.
- `data/login_types.csv`: pseudonymised login and actor type (`human`, `unknown`, `generic_bot`, `llm_bot`), from the same classification as the scraper's `actor_type_lookup`. It covers every login in both edge files.

Column definitions for every file are in `DATA_DICTIONARY.md`. Repository owners are organisation names and are not pseudonymised. Repository names are public GitHub identifiers and are left as they are. Only GitHub user logins are pseudonymised.

## 3. Requirements

- R 4.4.0 or later (`config.R` uses the base `%||%` operator, added in R 4.4.0). Tested with R 4.6.1.
- R packages: `did` 2.5.1, `fixest` 0.14.2, `dplyr` 1.2.1, `readr` 2.2.0.
- `renv.lock` pins R 4.6.1 and the full dependency set. To install the same versions, run `install.packages("renv")`, then `renv::restore()` from the package root.
- Python 3.8 or later for `tools/anonymize.py` (standard library only).

## 4. Options

### Environment variables

```bash
export DID_BITERS=1000      # did multiplier-bootstrap iterations (all steps)
export DID_CORES=1          # did cores
export DID_SEED=42
export DID_OUTCOMES=...     # comma-separated subset of outcomes (default: all retained outcomes)
export OUTPUT_DIR=...       # results directory (default: output/)
export ROLE_TYPES=...       # login-type table for the role-flow outcomes (default: data/login_types.csv)
export CORE_FREEZE=2025-01  # end of the core window; earlier adopters use their treatment month
export SAVE_OBJECTS=0       # 1 saves the fitted did objects to output/objects (large; off by default)
export STRICT_DATA_CHECKS=0 # skip the owner-clean repository-count check in scripts/robustness.R
```

`DID_OUTCOMES` applies to every script and overwrites the files in the results directory. To run a subset without replacing the full-suite files, set `OUTPUT_DIR` to another directory, for example:

```bash
OUTPUT_DIR=results/role_flows DID_OUTCOMES=role_flow_a0_r2 Rscript scripts/main_estimates.R
```

Role-flow outcomes (`role_flow_a<i>_r<j>`) are the share of a repository-month's review interactions from author role i to reviewer role j (0 core, 1 other human, 2 bot). The core is the smallest set of human reviewers covering 75% of the repository's human review interactions in the 12 months before `CORE_FREEZE`, held fixed for every month. A month enters with at least ten interactions, and repositories with no human review activity in the window have no core and drop out. `main_cs.csv` also reports the role-flow outcomes, main specification, with the core covering 30% and 50% (`analysis` = `core coverage 30%` and `core coverage 50%`).

## 5. Licence

The materials are licensed under CC-BY-4.0; see `LICENSE`.

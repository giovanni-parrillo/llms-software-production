## Master Thesis - MSc in Economics at University of Pisa and Sant'Anna School of Advanced Studies
## Giovanni Parrillo
# Reproducibility package

This archive reproduces the empirical design of my master thesis, including seven declared
sample/covariate specifications, a static TWFE comparison,
pre-treatment balance/overlap diagnostics, four robustness exercises, and a dedicated
spillover analysis (within-owner and cross-owner exposure).


## 1. One-command run

From the package directory:

```bash
Rscript run_all.R
```

`run_all.R` executes:

1. `main_estimates.R` - CS-DiD estimates for all specifications (`main_cs.csv`) and static TWFE (`twfe_static.csv`)
2. `balance.R` - pre-treatment balance and overlap diagnostics (`balance.csv`)
3. `robustness.R` - never-treated, owner-clean and placebo exercises (`robustness.csv`)
4. `spillover.R` - the fourth robustness exercise: direct within-owner and cross-owner spillover analysis (`spillover_*.csv`)

`prepare_data()` (in `config.R`) also builds the review-role flow outcomes from `author_reviewer_edges.csv.gz` and `login_types.csv` (`role_flows.R`; this step takes several minutes). They are `role_flow_a<i>_r<j>`, the share of all of a repository-month's interactions in which the pull-request author has role i and the reviewer has role j (0 = core, 1 = other human, 2 = bot). The core is the smallest set of human reviewers covering 80% of human interactions in the previous 12 months; a month enters only with at least 10 interactions and some human activity in the previous 12 months. Where a month does not enter, the flow is missing, not zero.

Because the entry condition depends on activity, the role-flow outcomes are estimated on a smaller and differently composed sample than the other outcomes (616 repositories in the main specification, against 682 to 763 for the other outcomes). The share of repository-months with a defined flow is about 20% for never-treated repositories and about 81% for eventually-treated repositories after adoption, so the estimates are conditional on that availability. They are ordinary outcomes in every script.

`run_all.R` can be invoked from any working directory, including by absolute
path; it moves to the package root before running the steps above.
Generated files are written to `output/` (created on first run).

## 2. Data and anonymisation

### Data

- `data/repo_month.csv` - repository-month panel
- `data/repo_master.csv` - repository attributes (owner, creation date, governance)
- `data/actor_repo.csv` - login-repository table with first review / approval dates (used for the cross-owner network); logins are pseudonymised, see below
- `data/author_reviewer_edges.csv.gz` - author-reviewer interaction counts by repository and merged month (formal reviews plus inline review comments, self-interactions excluded); logins are pseudonymised. Gzip-compressed CSV, read directly by `readr`. Input to the review-role flow outcomes.
- `data/login_types.csv` - pseudonymised login and actor type (`human`, `unknown`, `generic_bot`, `llm_bot`), from the same classification as the scraper's `actor_type_lookup`. Input to the review-role flow outcomes.

Repository owners are organisation names and are not pseudonymised; repository names are public GitHub identifiers and are left as they are. Only GitHub user logins are pseudonymised.

### Anonymisation

GitHub logins in `data/actor_repo.csv` are replaced by `u_` + the first 12 hex characters of
`HMAC-SHA256(secret key, login)`.

```bash
python tools/anonymize.py anonymize   # logins -> pseudonyms (creates private/ on first run)
python tools/anonymize.py restore     # pseudonyms -> original logins (needs private/; only data/actor_repo.csv)
python tools/anonymize.py anonymize-file data/login_types.csv login   # same key and map, for any CSV with login columns
```

`anonymize-file` leaves values that already start with `u_` unchanged, so running it again is safe.

### Design notes

- `fit_cs()` accepts `est_method` (`"dr"` by default, or `"ipw"`); all reported specifications use the
  doubly robust estimator, which already incorporates propensity-score weighting.
- `output/balance.csv`: on the 6m-baseline sample, ever-treated vs never-treated balance
  (means, SDs, standardized mean difference) for `pr_activity_6m` and
  `noncompany_governance`, plus propensity-score overlap (quantiles, min/max, share outside
  common support, share with score > 0.95) from a logit of ever-treated on `pr_activity_6m`.
  Rows are indexed by `section` (`covariate_balance` / `propensity_overlap`).
- `output/balance_pscores.csv`: unit-level propensity scores (`repo`, `ever_treated`, `pscore`,
  `in_common_support`) for the common-support plot.


## 3. Required R packages

- R >= 4.4.0 (`config.R` uses the base `%||%` operator, added in R 4.4.0)
- `did` 2.5.1
- `fixest` 0.14.2
- `dplyr` 1.2.1
- `readr` 2.2.0
- Python >= 3.8 for `tools/anonymize.py` (standard library only)

## 4. Caching and disk use

Useful options:

```bash
# Save the fitted did model objects for main/robustness runs (large; off by default)
export SAVE_OBJECTS=1
```

## 5. Environment variables

```bash
export DID_BITERS=1000      # did multiplier-bootstrap iterations (all steps)
export DID_CORES=1          # did cores
export DID_SEED=42
export DID_OUTCOMES=...     # comma-separated subset of outcomes (default: all retained outcomes)
export OUTPUT_DIR=...       # results directory (default: output/)
export ROLE_TYPES=...       # login-type table for the role-flow outcomes (default: data/login_types.csv)
export STRICT_DATA_CHECKS=0 # skip the owner-clean repository-count check in robustness.R
```

`DID_OUTCOMES` applies to every script and overwrites the files in the results directory. To run a subset without replacing the full-suite files, set `OUTPUT_DIR` to another directory, for example:

```bash
OUTPUT_DIR=results/role_flows DID_OUTCOMES=role_flow_a0_r2 Rscript main_estimates.R
```

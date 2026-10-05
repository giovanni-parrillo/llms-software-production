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

`run_all.R` can be invoked from any working directory, including by absolute
path; it moves to the package root before running the steps above.
Generated files are written to `output/` (created on first run).

### Data

- `data/repo_month.csv` - repository-month panel
- `data/repo_master.csv` - repository attributes (owner, creation date, governance)
- `data/actor_repo.csv` - login-repository table with first review / approval dates (used for the cross-owner network); logins are pseudonymised, see below

### Anonymisation

GitHub logins in `data/actor_repo.csv` are replaced by `u_` + the first 12 hex characters of
`HMAC-SHA256(secret key, login)`.

```bash
python tools/anonymize.py anonymize   # logins -> pseudonyms (creates private/ on first run)
python tools/anonymize.py restore     # pseudonyms -> original logins (needs private/)
```

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

## 5. Other environment variables

```bash
export DID_BITERS=1000      # did multiplier-bootstrap iterations (all steps)
export DID_CORES=1          # did cores
export DID_SEED=42
```

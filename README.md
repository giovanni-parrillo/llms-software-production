# Replication package: empirical design of the thesis

Giovanni Parrillo, MSc in Economics, University of Pisa and Sant'Anna School of Advanced Studies.

The package reproduces the empirical design of the thesis: seven sample and covariate
specifications, a static two-way fixed-effects comparison, pre-treatment balance and overlap
diagnostics, three robustness exercises, and a spillover analysis (within-owner and cross-owner
exposure).

## 1. Running the analysis

From the package root:

```bash
Rscript run_all.R
```

`run_all.R` changes to the package root and runs, in one R session:

1. `main_estimates.R`: CS-DiD estimates for all specifications (`main_cs.csv`) and static TWFE (`twfe_static.csv`).
2. `balance.R`: pre-treatment balance and overlap diagnostics (`balance.csv`, `balance_pscores.csv`).
3. `robustness.R`: never-treated, owner-clean and placebo exercises (`robustness.csv`).
4. `spillover.R`: within-owner and cross-owner spillover analysis (`spillover_*.csv`).

Each script can also be run on its own with `Rscript <script>.R` from the package root. Generated files go to `output/` (created on first run).

### Review-role flow outcomes

`prepare_data()` (in `config.R`) builds the review-role flow outcomes from `author_reviewer_edges.csv.gz` and `login_types.csv` (`role_flows.R`). The build takes several minutes and is cached once per R session. The outcomes are `role_flow_a<i>_r<j>`: the share of all of a repository-month's interactions in which the pull-request author has role i and the reviewer has role j (0 = core, 1 = other human, 2 = bot). The core is the smallest set of human reviewers covering 80% of human interactions in the previous 12 months. A month enters only with at least 10 interactions and some human activity in the previous 12 months; where it does not enter, the flow is missing, not zero.

Because the entry condition depends on activity, the role-flow outcomes are estimated on a smaller and differently composed sample than the other outcomes: 616 repositories in the main specification, against 657 to 763 for the other outcomes. About 20% of never-treated repository-months and about 81% of eventually-treated repository-months after adoption have a defined flow, so these estimates are conditional on that availability. They are ordinary outcomes in every script.

### Spillover outputs

`spillover_cross_owner.csv` and `spillover_within_owner.csv` report the aggregate effect and the event-time effects for `e` in [-12, 12]. The event-time estimator reports only the event times it identifies for each cohort, so an outcome can have fewer than 25 event-time rows (19 to 25 in the cross-owner file). Missing rows are not zeros.

## 2. Data and anonymisation

### Data

- `data/repo_month.csv`: repository-month panel.
- `data/repo_master.csv`: repository attributes (owner, creation date, governance).
- `data/actor_repo.csv`: login-repository table with first review and approval dates, used for the cross-owner network. Logins are pseudonymised.
- `data/author_reviewer_edges.csv.gz`: author-reviewer interaction counts by repository and merged month (formal reviews and inline review comments, self-interactions excluded). Logins are pseudonymised. Gzip-compressed CSV, read directly by `readr`. Input to the review-role flow outcomes.
- `data/login_types.csv`: pseudonymised login and actor type (`human`, `unknown`, `generic_bot`, `llm_bot`), from the same classification as the scraper's `actor_type_lookup`. Input to the review-role flow outcomes.

Repository owners are organisation names and are not pseudonymised. Repository names are public GitHub identifiers and are left as they are. Only GitHub user logins are pseudonymised.

### Anonymisation

GitHub logins are replaced by `u_` followed by the first 12 hexadecimal characters of `HMAC-SHA256(secret key, login)`.

```bash
python tools/anonymize.py anonymize                                  # logins in data/actor_repo.csv -> pseudonyms
python tools/anonymize.py restore                                    # pseudonyms -> logins in data/actor_repo.csv (needs private/)
python tools/anonymize.py anonymize-file data/login_types.csv login  # any plain or gzip CSV with login columns
```

The first run creates `private/` with the secret key and the pseudonym-to-login map. `private/` is gitignored and must not be shared with the data. Re-running any command is safe: values that already start with `u_` are left unchanged.

### Design notes

- `fit_cs()` accepts `est_method` (`"dr"` by default, or `"ipw"`). All reported specifications use the doubly robust estimator, which already incorporates propensity-score weighting.
- `output/balance.csv`: on the 6-month-baseline sample, ever-treated versus never-treated balance (means, SDs, standardised mean difference) for `pr_activity_6m` and `noncompany_governance`, plus propensity-score overlap (quantiles, min and max, share outside common support, share with score above 0.95) from a logit of ever-treated on `pr_activity_6m`. Rows are indexed by `section` (`covariate_balance` or `propensity_overlap`).
- `output/balance_pscores.csv`: unit-level propensity scores (`repo`, `ever_treated`, `pscore`, `in_common_support`) for the common-support plot.

## 3. Requirements

- R 4.4.0 or later (`config.R` uses the base `%||%` operator, added in R 4.4.0). Tested with R 4.6.1.
- R packages: `did` 2.5.1, `fixest` 0.14.2, `dplyr` 1.2.1, `readr` 2.2.0.
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
export SAVE_OBJECTS=0       # 1 saves the fitted did objects to output/objects (large; off by default)
export STRICT_DATA_CHECKS=0 # skip the owner-clean repository-count check in robustness.R
```

`DID_OUTCOMES` applies to every script and overwrites the files in the results directory. To run a subset without replacing the full-suite files, set `OUTPUT_DIR` to another directory, for example:

```bash
OUTPUT_DIR=results/role_flows DID_OUTCOMES=role_flow_a0_r2 Rscript main_estimates.R
```

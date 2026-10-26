# Data dictionary

This file documents the columns that the package's code reads. Other columns in the presented files
are not used by any script and are not described here. Variable definitions (treatment, outcomes,
actor classification) are documented in the thesis.

Logins are pseudonymised (`u_` followed by 12 hexadecimal characters). Repository owners are
organisation names and are not pseudonymised.

## `data/repo_month.csv`: repository-month panel

One row per repository and calendar month.

| Column | Type | Description |
|---|---|---|
| `repo` | text | Repository, `owner/name`. |
| `month` | `YYYY-MM` | Calendar month. |
| `first_ai_month` | `YYYY-MM` or empty | Month of the first validated AI-enablement artifact. Empty for never-treated repositories. Defines the treatment cohort. |
| `opened_prs` | integer | Pull requests opened in the month. Source of the baseline covariate. |
| `tc_mean_coordination_burden_per_pr_file` | number | Mean coordination burden per pull request, file-based unit. Log-transformed as `log_burden_mean_file`. |
| `tc_mean_coordination_burden_per_pr_folder` | number | As above, folder-based unit. Log-transformed as `log_burden_mean_folder`. |
| `reviews_by_human_reviewer` | integer | Review submissions by human reviewers in the month. |
| `unique_reviewers_excl_bots` | integer | Distinct non-bot reviewers active in the month. Together with `reviews_by_human_reviewer` it defines `log_human_reviews_per_reviewer` = log(1 + reviews by human reviewers / unique non-bot reviewers), set to missing when there is no active reviewer. |
| outcome columns | number | The other outcomes listed in `retained_outcomes` in `config.R`, except the role-flow outcomes. Their definitions are in the thesis. |

## `data/repo_master.csv`: repository attributes

One row per sampled repository.

| Column | Type | Description |
|---|---|---|
| `repo` | text | Repository, `owner/name`. Join key. |
| `owner` | text | Repository owner (organisation name). |
| `created_at` | ISO 8601 timestamp | Repository creation time. Panel rows before creation are dropped. |
| `owner_entity_type` | text | Owner classification. `company` is coded as company governance; any other value as non-company. |

The free-text `description` column was removed from the shipped copy because it contained personal
identifiers. No script reads it.

## `data/actor_repo.csv`: login-repository table

One row per login and repository.

| Column | Type | Description |
|---|---|---|
| `login` | pseudonym | GitHub login, pseudonymised. |
| `repo` | text | Repository. |
| `owner` | text | Repository owner. |
| `actor_type` | text | `human`, `unknown`, `generic_bot` or `llm_bot`. Only `human` rows enter the reviewer sets. |
| `first_review_date` | date or empty | Date of the login's first review in the repository. |
| `first_approval_date` | date or empty | Date of the login's first approval in the repository. |

## `data/login_types.csv`: actor classification

| Column | Type | Description |
|---|---|---|
| `login` | pseudonym | GitHub login, pseudonymised. One row per login. |
| `actor_type` | text | `human`, `unknown`, `generic_bot` or `llm_bot`. Bots (generic and LLM) are pooled for the role-flow outcomes. |

The table covers every login in `author_reviewer_edges.csv.gz` and `author_reviewer_edges_by_status.csv.gz`.

## `data/author_reviewer_edges.csv.gz`: author-reviewer interactions

Gzip-compressed CSV, one row per repository, merged month and author-reviewer pair.

| Column | Type | Description |
|---|---|---|
| `repo` | text | Repository. |
| `month` | `YYYY-MM` | Month in which the pull request was merged. |
| `author` | pseudonym | Pull-request author, pseudonymised. |
| `reviewer` | pseudonym | Reviewer, pseudonymised. Formal reviews and inline review comments; self-interactions excluded. |
| `n` | integer | Number of interactions for the triple. |

## `data/author_reviewer_edges_by_status.csv.gz`: interactions by merge status

Gzip-compressed CSV, one row per repository, review month, author-reviewer pair and merge status.

| Column | Type | Description |
|---|---|---|
| `repo` | text | Repository. |
| `month` | `YYYY-MM` | Month of the formal review or inline review comment. |
| `author` | pseudonym | Pull-request author, pseudonymised. |
| `reviewer` | pseudonym | Reviewer, pseudonymised. Formal reviews and inline review comments; self-interactions excluded. |
| `merged` | 0/1 | 1 if the pull request was merged, 0 otherwise. |
| `n` | integer | Number of interactions for the row. |

## Output files (`output/`)

| File | Contents |
|---|---|
| `main_cs.csv` | Callaway–Sant'Anna aggregate ATT, standard error and 95% interval, per specification and outcome. |
| `twfe_static.csv` | Static two-way fixed-effects estimate per outcome, with repository-clustered standard errors. |
| `robustness.csv` | Never-treated, owner-clean and placebo estimates, per outcome. |
| `spillover_within_owner.csv`, `spillover_cross_owner.csv` | Spillover aggregate and event-time estimates. |
| `spillover_network_stats.csv` | Size of the cross-owner exposure network for each overlap threshold. |
| `balance.csv`, `balance_pscores.csv` | Pre-treatment balance, overlap diagnostics and unit-level propensity scores. |
| `role_flows_by_status.csv` | Role-flow ATTs for merged and unmerged pull requests (`pr_status`), main and unadjusted specifications. |
| `dynamic_cs.csv` | Event-time aggregate ATT (`e` = -6 to 6) per outcome, main specification, with standard error and uniform critical value (`crit_val`). |

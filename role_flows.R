# ==============================================================================
# Review-role flow outcomes (joint shares, frozen core)
# ==============================================================================
# Share of a repository-month's interactions in each (author role i, reviewer role j) pair.
# Roles: core (0) = human reviewers covering `coverage` of human review interactions in the
# `lookback` months before the repository's freeze month, held fixed for every month;
# other human (1) = every other human login (unknown counts as human); bot (2) = generic and LLM bots.
# Interactions: formal reviews and inline review comments, self-interactions excluded; `merged` (0/1)
# keeps one PR merge status when the edge file has that column.
# A month enters with >= min_interactions interactions; repositories without human review
# activity in the freeze window have no core and are dropped.
# Outputs role_flow_a<i>_r<j>.

ROLE_FLOW_OUTCOMES <- sprintf("role_flow_a%d_r%d", rep(0:2, each = 3), rep(0:2, 3))

build_role_flows <- function(edges_path, types_path, freeze, coverage, min_interactions = 10, lookback = 12, merged = NULL) {
  types <- read_csv(types_path, col_types = cols(.default = "c"), show_col_types = FALSE)
  bots <- types$login[types$actor_type %in% c("generic_bot", "llm_bot")]

  e <- read_csv(edges_path, col_types = cols(.default = "c", n = "d"), show_col_types = FALSE)
  if (!is.null(merged)) e <- e[e$merged == as.character(merged), ]
  e$t <- as.integer(substr(e$month, 1, 4)) * 12L + as.integer(substr(e$month, 6, 7))

  out <- lapply(split(e, e$repo), function(g) {
    repo <- g$repo[1]
    if (is.na(freeze[repo])) return(NULL)
    win <- g$t >= freeze[repo] - lookback & g$t < freeze[repo] & !g$reviewer %in% bots
    past <- tapply(g$n[win], g$reviewer[win], sum)
    if (!length(past)) return(NULL)
    past <- past[order(-past, names(past))]   # ties break by login
    core <- names(past)[seq_len(sum(cumsum(past) / sum(past) < coverage) + 1)]

    role <- function(x) ifelse(x %in% bots, 2, ifelse(x %in% core, 0, 1))
    cell <- factor(role(g$author) * 3 + role(g$reviewer), levels = 0:8)
    flows <- tapply(g$n, list(g$t, cell), sum)
    flows[is.na(flows)] <- 0
    total <- rowSums(flows)
    keep <- total >= min_interactions
    if (!any(keep)) return(NULL)

    t <- as.integer(rownames(flows))[keep]
    res <- as.data.frame(flows[keep, , drop = FALSE] / total[keep])
    names(res) <- ROLE_FLOW_OUTCOMES
    cbind(repo = repo, month = sprintf("%04d-%02d", (t - 1) %/% 12, (t - 1) %% 12 + 1), res)
  })
  as_tibble(bind_rows(out))
}

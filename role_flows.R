# ==============================================================================
# Review-role flow outcomes (joint shares, 80% coverage core)
# ==============================================================================
# Share of a repository-month's interactions in each (author role i, reviewer role j) pair.
# Roles: core (0) = human reviewers covering 80% of human interactions in the prior 12 months;
# other human (1) = every other human login (unknown counts as human); bot (2) = generic and LLM bots.
# Interactions: formal reviews and inline review comments on merged PRs, self-interactions excluded.
# A month enters only with >= 10 interactions and some human activity in the prior 12 months.
# Outputs role_flow_a<i>_r<j>; NA where undefined. See README for the sample implications.

ROLE_LABELS <- c("core", "other", "bot")

build_role_flows <- function(edges_path, types_path) {
  types <- read_csv(types_path, col_types = cols(.default = "c"), show_col_types = FALSE)
  types <- types[!duplicated(types$login), ]
  bots <- types$login[types$actor_type %in% c("generic_bot", "llm_bot")]

  e <- read_csv(edges_path, col_types = cols(.default = "c", n = "d"), show_col_types = FALSE)
  e$t <- as.integer(substr(e$month, 1, 4)) * 12L + as.integer(substr(e$month, 6, 7))
  e$w <- e$n
  MIN_W <- 10; LOOK <- 12

  out <- vector("list", length(unique(e$repo)))
  for (k in seq_along(unique(e$repo))) {
    repo <- unique(e$repo)[k]
    g <- e[e$repo == repo, ]
    logins <- sort(unique(c(g$author, g$reviewer)))   # sorted so ties in the core ranking break deterministically
    ai <- match(g$author, logins); ri <- match(g$reviewer, logins)
    isb <- logins %in% bots
    hum <- !isb[ri]
    t0 <- min(g$t); t1 <- max(g$t)
    # sum duplicate (reviewer, month) pairs explicitly: matrix assignment would keep only the last
    H <- tapply(g$w[hum], list(factor(ri[hum], levels = seq_along(logins)), factor(g$t[hum] - t0 + 1, levels = seq_len(t1 - t0 + 1))), sum)
    H[is.na(H)] <- 0
    cs <- t(apply(H, 1, cumsum))
    rows <- list()
    for (m in sort(unique(g$t))) {
      sel <- g$t == m
      Wm <- sum(g$w[sel])
      if (Wm < MIN_W) next
      lo <- max(m - LOOK, t0); hi <- m - 1
      if (hi < t0) next
      past <- cs[, hi - t0 + 1] - if (lo - 1 >= t0) cs[, lo - t0] else 0
      if (sum(past) <= 0) next
      ord <- order(-past); ord <- ord[past[ord] > 0]   # ties keep login order (stable)
      cum <- cumsum(past[ord]) / sum(past)
      core <- ord[seq_len(sum(cum < 0.8) + 1)]
      a <- ai[sel]; r <- ri[sel]
      ra <- ifelse(isb[a], 2, ifelse(a %in% core, 0, 1))
      rr <- ifelse(isb[r], 2, ifelse(r %in% core, 0, 1))
      cell <- tapply(g$w[sel], factor(ra * 3 + rr, levels = 0:8), sum)
      cell[is.na(cell)] <- 0
      f <- as.numeric(cell) / Wm
      names(f) <- sprintf("role_flow_a%d_r%d", rep(0:2, each = 3), rep(0:2, 3))
      rows[[length(rows) + 1]] <- c(repo = repo, month = sprintf("%04d-%02d", (m - 1) %/% 12, (m - 1) %% 12 + 1), f)
    }
    out[[k]] <- if (length(rows)) bind_rows(lapply(rows, function(x) as.data.frame(as.list(x), stringsAsFactors = FALSE))) else NULL
  }
  res <- bind_rows(out)
  res[, 3:11] <- lapply(res[, 3:11], as.numeric)
  res
}

ROLE_FLOW_OUTCOMES <- sprintf("role_flow_a%d_r%d", rep(0:2, each = 3), rep(0:2, 3))

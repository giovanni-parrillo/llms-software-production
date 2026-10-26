# ==============================================================================
# One-command replication of the repository-level estimates
# ==============================================================================
# Usage:
#   Rscript run_all.R
#   Rscript /absolute/path/to/run_all.R
#

.args <- commandArgs(trailingOnly = FALSE)
.file_arg <- grep("^--file=", .args, value = TRUE)
.script_dir <- if (length(.file_arg) == 1L) {
  dirname(normalizePath(sub("^--file=", "", .file_arg)))
} else {
  getwd()
}
setwd(.script_dir)
rm(.args, .file_arg, .script_dir)

source("scripts/main_estimates.R")
source("scripts/balance.R")
source("scripts/robustness.R")
source("scripts/spillover.R")
source("scripts/merge_status.R")
source("scripts/event_study.R")

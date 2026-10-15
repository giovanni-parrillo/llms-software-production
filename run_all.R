# ==============================================================================
# One-command replication of the thesis empirical design (Chapter 6)
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

source("main_estimates.R")
source("balance.R")
source("robustness.R")
source("spillover.R")

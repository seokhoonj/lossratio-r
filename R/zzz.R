# Tell data.table that this package understands data.table semantics
# (reference semantics, NSE in `j`, etc.). Recommended for any package
# that Imports data.table -- avoids spurious copy-on-modify warnings
# when data.table is passed through lossratio functions.
.datatable.aware <- TRUE


# `utils::globalVariables` registrations are *empirical* -- every name
# below has been verified to trigger an `R CMD check` NOTE when omitted.
# The list is alphabetically sorted within each section so future
# additions / removals stay diff-friendly.
#
# Sections:
#   1. data.table system idioms (`.`, `i.<col>`, `x.<col>`)
#   2. Triangle / Link / fit output schema columns
#   3. Fit SE / variance / CV / tail-factor schema
#   4. Aggregation counts & reserved data.table value names
#
# Internal temp columns (`.col`) are handled at function scope via local
# `NULL` declarations, not registered here. See e.g. `plot.LRFit`.

utils::globalVariables(c(

  # 1. data.table system idioms ----------------------------------------
  ".",
  "i.is_observed", "i.loss_param_se", "i.loss_proc_se", "i.loss_proj",
  "i.loss_total_se", "i.lr_ci_lower", "i.lr_ci_upper", "i.lr_cv",
  "i.lr_proj", "i.lr_se", "i.n_obs", "i.premium_proj",
  "i.premium_total_cv", "i.premium_total_se", "i.target_param_se",
  "i.target_proc_se", "i.target_proj", "i.target_total_se",
  "x.change_date", "x.dev_split", "x.m_k",

  # 2. Triangle / Link / fit output schema -----------------------------
  "ae_err_incr", "aeg", "aeg_incr",
  "ata", "ata_from", "ata_link", "ata_to",
  "change", "change_count",
  "cohort", "dev",
  "exposure_from", "exposure_proj", "exposure_to",
  "f", "f_exposure", "f_selected", "f_sigma2", "f_var",
  "g", "g_selected", "g_sigma2", "g_var",
  "intensity",
  "is_excluded", "is_fit_data", "is_held_out", "is_observed",
  "label", "last_obs", "lower", "upper",
  "loss", "loss_incr", "loss_incr_proj", "loss_incr_share", "loss_obs",
  "loss_proj", "loss_share",
  "lr", "lr_incr", "lr_mad", "lr_median", "lr_proj", "lr_se", "lr_var",
  "magnitude_mean", "mat_x", "maturity_from",
  "premium", "premium_incr", "premium_incr_proj", "premium_obs",
  "premium_proj", "premium_share",
  "regime", "regime_id", "reserve", "selected",
  "actual", "actual_incr", "expected", "expected_incr",
  "target_delta", "target_from",
  "target_obs", "target_proj", "target_to",
  "value",  # default melt() value column when value.name not set

  # 3. Fit SE / variance / CV / tail-factor schema ---------------------
  "cv", "flag", "metric", "rse", "sigma2", "type",
  "loss_param_se2", "loss_proc_se2", "loss_total_se", "loss_total_se2",
  "premium_total_cv", "premium_total_se",
  "target_param_se", "target_param_se2", "target_param_se_tail",
  "target_param_se2_tail",
  "target_proc_cv", "target_proc_se", "target_proc_se2",
  "target_proc_se_tail", "target_proc_se2_tail",
  "target_tail",
  "target_total_cv", "target_total_se", "target_total_se2",
  "target_total_se_tail", "target_total_se2_tail",

  # 4. Aggregation counts & plot coordinate vars -----------------------
  "N", "n", "n_cohorts", "n_expected", "n_obs", "n_observed", "n_valid",
  "w", "weight",
  "x_end", "x_start", "xint", "y_end", "y_start"
))

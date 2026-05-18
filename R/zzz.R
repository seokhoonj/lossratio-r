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
# `NULL` declarations, not registered here. See e.g. `plot.RatioFit`.

utils::globalVariables(c(

  # 1. data.table system idioms ----------------------------------------
  ".",
  "i.is_observed", "i.loss_param_se", "i.loss_proc_se", "i.loss_proj",
  "i.loss_total_se", "i.ratio_ci_lo", "i.ratio_ci_hi", "i.ratio_cv",
  "i.ratio_proj", "i.ratio_se", "i.n_cohorts", "i.exposure_proj",
  "i.exposure_total_cv", "i.exposure_total_se",
  "x.change_date", "x.dev_split", "x.m_k",

  # 2. Triangle / Link / fit output schema -----------------------------
  "incr_ae_err", "aeg", "incr_aeg",
  "ata", "ata_from", "ata_link", "ata_to",
  "change", "change_count",
  "cohort", "dev",
  "elr", "elr_cc", "exposure_ult",
  "exposure_from", "exposure_proj", "exposure_to",
  "f", "f_exposure", "f_sel", "f_sigma2", "f_var",
  "g", "g_sel", "g_sigma2", "g_var",
  "intensity",
  "is_excluded", "is_fit_data", "is_held_out", "is_observed",
  "label", "last_obs", "latest", "lower", "upper",
  "loss", "incr_loss", "incr_loss_proj", "incr_loss_share",
  "loss_delta", "loss_from", "loss_latest", "loss_obs", "loss_proj",
  "loss_proj_cl", "loss_share",
  "loss_to", "loss_ult", "loss_ult_bf", "loss_ult_cc", "loss_ult_cl",
  "q",
  "ratio", "incr_ratio", "ratio_proj", "ratio_se", "ratio_var",
  "magnitude_mean", "mat_x", "maturity_from",
  "exposure", "incr_exposure", "incr_exposure_proj", "exposure_obs",
  "exposure_share",
  "regime", "regime_id", "reserve", "selected",
  "actual", "incr_actual", "expected", "incr_expected",
  "value",  # default melt() value column when value.name not set

  # 3. Fit SE / variance / CV / tail-factor schema ---------------------
  "cv", "metric", "rse", "sigma2", "type",
  "loss_param_se",  "loss_param_se2", "loss_param_se_tail",
  "loss_param_se2_tail",
  "loss_proc_cv",   "loss_proc_se",   "loss_proc_se2",
  "loss_proc_se_tail",  "loss_proc_se2_tail",
  "loss_tail",
  "loss_total_cv",  "loss_total_se",  "loss_total_se2",
  "loss_total_se_tail", "loss_total_se2_tail",
  "exposure_total_cv", "exposure_total_se",

  # 4. Aggregation counts & plot coordinate vars -----------------------
  "N", "n", "n_expected", "n_cohorts", "n_dev", "n_valid",
  "w", "weight",
  "x_end", "x_start", "xint", "y_end", "y_start"
))

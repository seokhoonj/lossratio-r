# Synthetic experience-study generator for the lossratio package.
#
# Produces a 36 x 36 jagged triangle x 4 coverages, deterministic via
# set.seed(20260501). Calibration scalars (target ratio, premium volume,
# cell noise CV) per coverage were measured once on a real long-term
# Korean health-insurance portfolio and are baked in here as constants
# so this script ships without any real-data dependency. `surgery`
# carries a regime shift at cohort idx 18 (2024-07): target ratio is
# scaled to 0.6x to mimic the real portfolio's underwriting
# tightening.
#
# Run from the package root:
#   Rscript -e 'source("data-raw/make_experience.R")'

suppressPackageStartupMessages({
  library(data.table)
  library(usethis)
})

set.seed(20260501L)

# ---- Calibration constants (per coverage) -----------------------------------
#
# Coverage labels (lowercase full-word, audience-facing):
#   ci         Critical-illness rider covering the two major non-cancer
#              CIs: cerebrovascular disease (stroke, cerebral infarction,
#              cerebral haemorrhage) and ischemic heart disease (angina,
#              acute MI). Does NOT include cancer; cancer is its own
#              `cancer` coverage.
#   cancer     Cancer rider.
#   inpatient  Hospitalisation rider (per-day fixed benefit).
#   surgery    Surgery rider (per-event fixed benefit).
calib <- data.table(
  coverage      = c("ci",       "cancer",   "inpatient", "surgery"),
  target_ratio  = c(0.6041798,  0.4966633,  0.3533962,   1.4291995),
  premium_mean = c(490082826,  403465899,  32725571,    704738057),
  premium_cv   = c(0.9332768,  0.8684393,  0.8545352,   0.6738675),
  cell_cv       = c(1.3679838,  1.6660074,  0.8603264,   0.3589258)
)

# Single regime shift on `surgery` at cohort idx 18 (2024-07): scale
# target ratio by 0.6 (1.43 -> ~0.86), reflecting an underwriting
# tightening.
shifts <- list("surgery" = list(at = 18L, scale = 0.60))

# ---- Synthesis grid -------------------------------------------------------

n_cohorts    <- 36L
K            <- 36L
max_cy_m_idx <- n_cohorts - 1L

# Runoff: roughly constant incremental loss per dev with a small dev-1
# dampening that mimics the waiting-period dip in real long-term
# health data.
weights    <- rep(1.0, K)
weights[1] <- 0.2
weights    <- weights / sum(weights)

records <- vector("list", 0L)
for (i in seq_len(nrow(calib))) {
  cv            <- calib$coverage[i]
  target_ratio  <- calib$target_ratio[i]
  premium_mean <- calib$premium_mean[i] / K
  premium_cv   <- calib$premium_cv[i]
  cell_cv       <- calib$cell_cv[i]

  shift_at    <- if (!is.null(shifts[[cv]])) shifts[[cv]]$at    else NA_integer_
  shift_scale <- if (!is.null(shifts[[cv]])) shifts[[cv]]$scale else 1.0

  for (ci in 0L:(n_cohorts - 1L)) {
    cohort_mult      <- exp(rnorm(1L, mean = 0, sd = premium_cv))
    premium_base_ci <- premium_mean * cohort_mult
    eff_target       <- target_ratio *
                        (if (!is.na(shift_at) && ci >= shift_at) shift_scale else 1.0)

    cy_u <- ci %/% 12L
    cm_u <- ci %% 12L + 1L
    uy_m <- as.Date(sprintf("%d-%02d-01", 2023L + cy_u, cm_u))

    for (k in 0L:(K - 1L)) {
      if (ci + k > max_cy_m_idx) break
      cy_c <- (ci + k) %/% 12L
      cm_c <- (ci + k) %% 12L + 1L
      cy_m <- as.Date(sprintf("%d-%02d-01", 2023L + cy_c, cm_c))

      incr_premium <- premium_base_ci * (1 + rnorm(1L, 0, 0.05))
      incr_premium <- max(incr_premium, 0)

      noise <- exp(rnorm(1L, 0, log(1 + cell_cv)))
      incr_loss <- incr_premium * eff_target * weights[k + 1L] * K * noise

      # Real-world premium / loss are recorded in won (integer);
      # round to match that convention but keep `numeric` (double)
      # storage -- actuarial values may exceed R's int32 ceiling once
      # portfolios scale, and downstream computations (cumulative
      # sums, projections, ratios) produce non-integer values anyway.
      records[[length(records) + 1L]] <- data.table(
        coverage      = cv,
        cy_m          = cy_m,
        uy_m          = uy_m,
        incr_loss     = round(incr_loss),
        incr_premium = round(incr_premium)
      )
    }
  }
}

experience <- rbindlist(records)

# ---- Derived time-axis columns ---------------------------------------------
.year_of  <- function(d) as.Date(sprintf(
  "%d-01-01", data.table::year(d)))
.half_of  <- function(d) as.Date(sprintf(
  "%d-%02d-01", data.table::year(d),
  ifelse(data.table::month(d) <= 6L, 1L, 7L)))
.quart_of <- function(d) as.Date(sprintf(
  "%d-%02d-01", data.table::year(d),
  ((data.table::month(d) - 1L) %/% 3L) * 3L + 1L))

experience[, `:=`(
  uy     = .year_of(uy_m),
  uy_h   = .half_of(uy_m),
  uy_q   = .quart_of(uy_m),
  cy     = .year_of(cy_m),
  cy_h   = .half_of(cy_m),
  cy_q   = .quart_of(cy_m),
  dev_y  = data.table::year(cy_m) - data.table::year(uy_m) + 1L,
  dev_h  = 2L * (data.table::year(cy_m) - data.table::year(uy_m)) +
           ((data.table::month(cy_m) - 1L) %/% 6L -
           (data.table::month(uy_m) - 1L) %/% 6L) + 1L,
  dev_q  = 4L * (data.table::year(cy_m) - data.table::year(uy_m)) +
           ((data.table::month(cy_m) - 1L) %/% 3L -
           (data.table::month(uy_m) - 1L) %/% 3L) + 1L,
  dev_m  = 12L * (data.table::year(cy_m) - data.table::year(uy_m)) +
           (data.table::month(cy_m) - data.table::month(uy_m)) + 1L
)]

setcolorder(experience, c(
  "coverage",
  "uy", "uy_h", "uy_q", "uy_m",
  "cy", "cy_h", "cy_q", "cy_m",
  "dev_y", "dev_h", "dev_q", "dev_m",
  "incr_loss", "incr_premium"
))

cat(sprintf("experience: %d rows x %d cols, coverage = %s\n",
            nrow(experience), ncol(experience),
            paste(unique(experience$coverage), collapse = ", ")))

usethis::use_data(experience, overwrite = TRUE)

# Synthetic experience-study generator for the lossratio package.
#
# Produces a 36 x 36 jagged triangle x 4 coverages, deterministic via
# set.seed(20260501). Calibration scalars (target LR, premium volume,
# cell noise CV) per coverage were measured once on a real long-term
# Korean health-insurance portfolio and are baked in here as constants
# so this script ships without any real-data dependency. SUR carries a
# regime shift at cohort 18 (2025-07): target LR is scaled down to
# 0.6x to mimic the real portfolio's underwriting tightening.
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
# Coverage codes (letter-first uppercase, valid bare identifiers):
#   CI   The two major non-cancer critical illnesses:
#          - cerebrovascular disease (stroke, cerebral infarction,
#            cerebral haemorrhage)
#          - ischemic heart disease (angina, acute myocardial
#            infarction)
#        Does NOT include cancer; cancer is the separate `CAN` coverage.
#   CAN  Cancer
#   HOS  Hospitalisation (per-day fixed benefit)
#   SUR  Surgery (per-event fixed benefit)
calib <- data.table(
  coverage     = c("CI",       "CAN",      "HOS",      "SUR"),
  target_lr = c(0.6041798,  0.4966633,  0.3533962,  1.4291995),
  prem_mean = c(490082826,  403465899,  32725571,   704738057),
  prem_cv   = c(0.9332768,  0.8684393,  0.8545352,  0.6738675),
  cell_cv   = c(1.3679838,  1.6660074,  0.8603264,  0.3589258)
)

# Single regime shift on SUR at cohort idx 18 (2025-07): scale target
# LR by 0.6 (1.43 -> ~0.86), reflecting an underwriting tightening.
shifts <- list("SUR" = list(at = 18L, scale = 0.60))

# ---- Synthesis grid -------------------------------------------------------

n_cohorts   <- 36L
K           <- 36L
max_cym_idx <- n_cohorts - 1L

# Runoff: roughly constant incremental loss per dev with a small dev-1
# dampening that mimics the waiting-period dip in real long-term
# health data.
weights    <- rep(1.0, K)
weights[1] <- 0.2
weights    <- weights / sum(weights)

records <- vector("list", 0L)
for (i in seq_len(nrow(calib))) {
  cv        <- calib$coverage[i]
  target_lr <- calib$target_lr[i]
  prem_mean <- calib$prem_mean[i] / K
  prem_cv   <- calib$prem_cv[i]
  cell_cv   <- calib$cell_cv[i]

  shift_at    <- if (!is.null(shifts[[cv]])) shifts[[cv]]$at    else NA_integer_
  shift_scale <- if (!is.null(shifts[[cv]])) shifts[[cv]]$scale else 1.0

  for (ci in 0L:(n_cohorts - 1L)) {
    cohort_mult  <- exp(rnorm(1L, mean = 0, sd = prem_cv))
    prem_base_ci <- prem_mean * cohort_mult
    eff_target   <- target_lr *
                    (if (!is.na(shift_at) && ci >= shift_at) shift_scale else 1.0)

    cy_u <- ci %/% 12L
    cm_u <- ci %% 12L + 1L
    uym  <- as.Date(sprintf("%d-%02d-01", 2024L + cy_u, cm_u))

    for (k in 0L:(K - 1L)) {
      if (ci + k > max_cym_idx) break
      cy_c <- (ci + k) %/% 12L
      cm_c <- (ci + k) %% 12L + 1L
      cym  <- as.Date(sprintf("%d-%02d-01", 2024L + cy_c, cm_c))

      incr_premium <- prem_base_ci * (1 + rnorm(1L, 0, 0.05))
      incr_premium <- max(incr_premium, 0)

      noise <- exp(rnorm(1L, 0, log(1 + cell_cv)))
      incr_loss <- incr_premium * eff_target * weights[k + 1L] * K * noise

      records[[length(records) + 1L]] <- data.table(
        coverage        = cv,
        cym          = cym,
        uym          = uym,
        loss_incr    = incr_loss,
        premium_incr = incr_premium
      )
    }
  }
}

experience <- rbindlist(records)

# ---- Derived time-axis columns ---------------------------------------------
.year_of  <- function(d) data.table::year(d)
.half_of  <- function(d) as.Date(sprintf(
  "%d-%02d-01", data.table::year(d),
  ifelse(data.table::month(d) <= 6L, 1L, 7L)))
.quart_of <- function(d) as.Date(sprintf(
  "%d-%02d-01", data.table::year(d),
  ((data.table::month(d) - 1L) %/% 3L) * 3L + 1L))

experience[, `:=`(
  uy     = .year_of(uym),
  uyh    = .half_of(uym),
  uyq    = .quart_of(uym),
  cy     = .year_of(cym),
  cyh    = .half_of(cym),
  cyq    = .quart_of(cym),
  dev_y = data.table::year(cym)  - data.table::year(uym) + 1L,
  dev_h = 2L * (data.table::year(cym) - data.table::year(uym)) +
          ((data.table::month(cym) - 1L) %/% 6L -
           (data.table::month(uym) - 1L) %/% 6L) + 1L,
  dev_q = 4L * (data.table::year(cym) - data.table::year(uym)) +
          ((data.table::month(cym) - 1L) %/% 3L -
           (data.table::month(uym) - 1L) %/% 3L) + 1L,
  dev_m = 12L * (data.table::year(cym) - data.table::year(uym)) +
          (data.table::month(cym) - data.table::month(uym)) + 1L
)]

setcolorder(experience, c(
  "coverage",
  "uy", "uyh", "uyq", "uym",
  "cy", "cyh", "cyq", "cym",
  "dev_y", "dev_h", "dev_q", "dev_m",
  "loss_incr", "premium_incr"
))
setattr(experience$uy,  "class", "Date")  # year-as-Date convention

cat(sprintf("experience: %d rows x %d cols, coverage = %s\n",
            nrow(experience), ncol(experience),
            paste(unique(experience$coverage), collapse = ", ")))

usethis::use_data(experience, overwrite = TRUE)

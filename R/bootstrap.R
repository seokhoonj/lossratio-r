# Bootstrap helpers ---------------------------------------------------------
#
# Single-role per-cohort bootstrap simulators. Each returns the full
# [n_dev x B] simulation matrix; CI / SE extraction is left to a separate
# helper so the caller can derive both per-dev quantities directly from
# the matrix.
#
# Phase 2a scope: Normal parametric residuals only (Mack 1993 variance
# structure). ODP / Gamma process distributions and maturity-stratified
# shape estimation are deferred to Phase 2b/2c.
#
# References:
#   Mack (1993, ASTIN Bull 23/2)        -- sigma_k^2 / f_k variance form.
#   Mack (1999, ASTIN Bull 29/2)        -- sigma^2 extrapolation (tail).
#   England & Verrall (1999, IME 25/3)  -- bootstrap framing.
#   Barnett & Zehnwirth (2007, IW TR)   -- residual diagnostic critique.


#' Per-step CL random draw (Normal residuals)
#'
#' One Mack-style multiplicative step `C_{k+1} = f_k * C_k + eps` with
#' parameter `f_k ~ N(f_hat, Var(f_hat))` and process noise
#' `eps ~ N(0, sigma_k^2 * |C_k|^alpha)`.
#'
#' @keywords internal
.cl_step <- function(prev, f_hat, f_var_k, sigma2_k, alpha, B, process) {
  f_sd <- if (is.finite(f_var_k)) sqrt(max(f_var_k, 0)) else 0

  f_samp <- if (is.finite(f_hat) && f_sd > 0) {
    stats::rnorm(B, f_hat, f_sd)
  } else if (is.finite(f_hat)) {
    rep(f_hat, B)
  } else {
    rep(1, B)
  }

  eps_sd_vec <- ifelse(
    is.finite(sigma2_k) & is.finite(prev) & prev > 0,
    sqrt(pmax(sigma2_k * abs(prev)^alpha, 0)),
    0
  )

  eps <- switch(process,
    normal = stats::rnorm(B) * eps_sd_vec,
    stop("process = '", process, "' not yet implemented (Phase 2b).",
         call. = FALSE)
  )

  f_samp * prev + eps
}


#' Per-step ED random draw (Normal residuals)
#'
#' One additive step `C_{k+1} = C_k + g_k * P_k + eps` with parameter
#' `g_k ~ N(g_hat, Var(g_hat))` and process noise
#' `eps ~ N(0, sigma_k^2 * P_k^alpha)`.
#'
#' @keywords internal
.ed_step <- function(prev, e_k, g_hat, g_var_k, sigma2_k, alpha, B, process) {
  g_sd <- if (is.finite(g_var_k)) sqrt(max(g_var_k, 0)) else 0

  g_samp <- if (is.finite(g_hat) && g_sd > 0) {
    stats::rnorm(B, g_hat, g_sd)
  } else if (is.finite(g_hat)) {
    rep(g_hat, B)
  } else {
    rep(NA_real_, B)
  }

  eps_sd <- if (is.finite(sigma2_k) && is.finite(e_k) && e_k > 0) {
    sqrt(max(sigma2_k * e_k^alpha, 0))
  } else 0

  eps <- switch(process,
    normal = if (eps_sd > 0) stats::rnorm(B, 0, eps_sd) else rep(0, B),
    stop("process = '", process, "' not yet implemented (Phase 2b).",
         call. = FALSE)
  )

  prev + g_samp * e_k + eps
}


#' Per-cohort CL parametric bootstrap (sim matrix only)
#'
#' @description
#' Simulates `B` replicates of a Mack chain-ladder projection path for a
#' single cohort. Future cells (`k > last_obs`) are drawn via the
#' multiplicative recursion (see [.cl_step]); observed cells are filled
#' with the observed value across all replicates.
#'
#' @param target_obs Numeric vector of observed cumulative target by dev
#'   (NA for not-yet-observed cells).
#' @param target_proj Numeric vector of projected cumulative target (used
#'   only for length; values not consumed in simulation).
#' @param f_sel,f_sigma2,f_var Per-dev factor / Mack-sigma^2 / Var(f_hat)
#'   vectors, aligned with `target_proj` indices `1..n-1` (link k -> k+1).
#' @param last_obs Index of the last observed dev (boundary between
#'   observed-rows-fixed and projected-rows-simulated).
#' @param B Integer number of bootstrap replicates.
#' @param alpha Variance exponent in `sigma_k^2 * C_k^alpha` (Mack uses 1).
#' @param process Process distribution. Phase 2a: only `"normal"`.
#'
#' @return A `[length(target_proj) x B]` numeric matrix. Observed rows
#'   are constant across columns (the observed value); projected rows
#'   contain `B` simulated cumulative values. Negative simulations are
#'   clipped to 0.
#'
#' @keywords internal
.cl_bootstrap <- function(target_obs, target_proj,
                          f_sel, f_sigma2, f_var,
                          last_obs, B, alpha,
                          process = c("normal")) {
  process <- match.arg(process)
  n <- length(target_proj)

  sim <- matrix(NA_real_, nrow = n, ncol = B)
  for (i in seq_len(last_obs)) sim[i, ] <- target_obs[i]

  if (last_obs >= n || last_obs < 1L || B < 1L) {
    sim[!is.na(sim) & sim < 0] <- 0
    return(sim)
  }

  for (i in seq(last_obs + 1L, n)) {
    k    <- i - 1L
    prev <- sim[i - 1L, ]
    sim[i, ] <- .cl_step(prev, f_sel[k], f_var[k], f_sigma2[k],
                         alpha, B, process)
  }

  sim[!is.na(sim) & sim < 0] <- 0
  sim
}


#' Per-cohort ED parametric bootstrap (sim matrix only)
#'
#' @description
#' Simulates `B` replicates of an exposure-driven projection path for a
#' single cohort. Future cells are drawn via the additive recursion (see
#' [.ed_step]).
#'
#' @param target_obs,target_proj See [.cl_bootstrap].
#' @param exposure_proj Numeric vector of projected exposure (premium) by
#'   dev; supplies the `P_k` multiplier for the ED intensity.
#' @param g_sel,g_sigma2,g_var Per-dev intensity / Mack-sigma^2 /
#'   Var(g_hat) vectors.
#' @param last_obs,B,alpha,process See [.cl_bootstrap].
#'
#' @return A `[length(target_proj) x B]` numeric matrix; same convention
#'   as [.cl_bootstrap].
#'
#' @keywords internal
.ed_bootstrap <- function(target_obs, target_proj, exposure_proj,
                          g_sel, g_sigma2, g_var,
                          last_obs, B, alpha,
                          process = c("normal")) {
  process <- match.arg(process)
  n <- length(target_proj)

  sim <- matrix(NA_real_, nrow = n, ncol = B)
  for (i in seq_len(last_obs)) sim[i, ] <- target_obs[i]

  if (last_obs >= n || last_obs < 1L || B < 1L) {
    sim[!is.na(sim) & sim < 0] <- 0
    return(sim)
  }

  for (i in seq(last_obs + 1L, n)) {
    k    <- i - 1L
    prev <- sim[i - 1L, ]
    e_k  <- exposure_proj[k]
    sim[i, ] <- .ed_step(prev, e_k, g_sel[k], g_var[k], g_sigma2[k],
                         alpha, B, process)
  }

  sim[!is.na(sim) & sim < 0] <- 0
  sim
}


#' Per-cohort SA parametric bootstrap (ED before maturity, CL after)
#'
#' @description
#' Simulates the stage-adaptive projection path: cells with dev source
#' `k < maturity_from` use the ED additive recursion; cells with
#' `k >= maturity_from` use the CL multiplicative recursion. When
#' `maturity_from` is non-finite, the function degenerates to pure ED.
#'
#' @inheritParams .ed_bootstrap
#' @param f_sel,f_sigma2,f_var CL factor / Mack-sigma^2 / Var(f_hat).
#' @param maturity_from Source-dev index k\* where the SA boundary lies.
#'   Cells with `k < maturity_from` are in the ED phase; cells with
#'   `k >= maturity_from` are in the CL phase.
#'
#' @return A `[length(target_proj) x B]` numeric matrix.
#'
#' @keywords internal
.sa_bootstrap <- function(target_obs, target_proj, exposure_proj,
                          g_sel, f_sel,
                          g_sigma2, f_sigma2, g_var, f_var,
                          last_obs, maturity_from, B, alpha,
                          process = c("normal")) {
  process <- match.arg(process)
  n <- length(target_proj)

  sim <- matrix(NA_real_, nrow = n, ncol = B)
  for (i in seq_len(last_obs)) sim[i, ] <- target_obs[i]

  if (last_obs >= n || last_obs < 1L || B < 1L) {
    sim[!is.na(sim) & sim < 0] <- 0
    return(sim)
  }

  mat <- if (is.finite(maturity_from)) maturity_from else Inf

  for (i in seq(last_obs + 1L, n)) {
    k    <- i - 1L
    prev <- sim[i - 1L, ]

    if (k < mat) {
      e_k <- exposure_proj[k]
      sim[i, ] <- .ed_step(prev, e_k, g_sel[k], g_var[k], g_sigma2[k],
                           alpha, B, process)
    } else {
      sim[i, ] <- .cl_step(prev, f_sel[k], f_var[k], f_sigma2[k],
                           alpha, B, process)
    }
  }

  sim[!is.na(sim) & sim < 0] <- 0
  sim
}


#' Per-dev CI bounds and SE from a bootstrap simulation matrix
#'
#' @description
#' Extracts percentile-based CI and standard deviation per dev row from a
#' `[n_dev x B]` simulation matrix. Observed rows (index `<= last_obs`)
#' return the constant observed value with SE = 0; projected rows return
#' quantile-based CI and empirical SD.
#'
#' @param sim `[n_dev x B]` simulation matrix from one of
#'   [.cl_bootstrap] / [.ed_bootstrap] / [.sa_bootstrap].
#' @param last_obs Boundary index (observed-row count).
#' @param probs Length-2 numeric vector of lower/upper quantile probs
#'   (e.g., `c(0.025, 0.975)`).
#'
#' @return A list with three numeric vectors of length `nrow(sim)`:
#'   `ci_lo`, `ci_hi`, `se`.
#'
#' @keywords internal
.bootstrap_summary <- function(sim, last_obs, probs) {
  n <- nrow(sim)
  ci_lo <- rep(NA_real_, n)
  ci_hi <- rep(NA_real_, n)
  se    <- rep(NA_real_, n)

  for (i in seq_len(last_obs)) {
    v <- sim[i, 1L]
    ci_lo[i] <- v
    ci_hi[i] <- v
    se[i]    <- 0
  }

  if (last_obs < n) {
    for (i in seq(last_obs + 1L, n)) {
      vals <- sim[i, ]
      if (all(!is.finite(vals))) next
      q <- stats::quantile(vals, probs = probs, na.rm = TRUE, names = FALSE)
      ci_lo[i] <- q[1L]
      ci_hi[i] <- q[2L]
      se[i]    <- stats::sd(vals, na.rm = TRUE)
    }
  }

  list(ci_lo = ci_lo, ci_hi = ci_hi, se = se)
}

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


# =============================================================================
# Phase 1 — Triangle-level bootstrap worker (new entry point)
#
# Design: dev/BOOTSTRAP.md
#
# Layer 1 (Triangle worker, 1x): data perturbation, model-agnostic output.
# Layer 2 (fit consumers, per method, B times): refit + Stage 2 process noise.
#
# Legacy helpers above (.cl_step / .ed_step / .cl_bootstrap / .ed_bootstrap /
# .sa_bootstrap / .bootstrap_summary) remain unchanged so the current
# fit_lr/fit_loss/fit_premium/backtest pipeline keeps working. Phase 2 will
# migrate them onto `bootstrap.Triangle()`; phase 3 drops the legacy helpers.
# =============================================================================


#' Bootstrap a Triangle
#'
#' @description
#' Generate `B` alternative realizations of a `Triangle` via residual
#' (England-Verrall) or parametric (Mack normal) Stage 1 perturbation. The
#' output is a model-agnostic `BootstrapTriangle` object that downstream
#' fit functions (`fit_cl` / `fit_ed` / `fit_lr`) consume to recover
#' parameter and process risk decomposition.
#'
#' This entry point sits at the Triangle level — it knows nothing about CL,
#' ED, or SA. Each fit method later refits its own model on every alt
#' triangle and adds Stage 2 process noise using its own variance recipe.
#' The same bootstrap object is therefore reusable across all fit methods.
#'
#' Bootstrap proceeds in two conceptual stages (see `dev/BOOTSTRAP.md`):
#'
#' 1. **Stage 1 — parameter uncertainty**: residual resample (or parametric
#'    Normal draw) propagated through the cumulative loss chain, refitted
#'    factors per replicate. This produces `B` alternative *mean*
#'    predictions per cell.
#' 2. **Stage 2 — process uncertainty**: added *inside the fit function*
#'    on demand, using the method-specific `sigma^2`. The `process` argument
#'    here is stored as metadata so the consuming fit method knows which
#'    distribution to use.
#'
#' @param x A `Triangle` object.
#' @param method One of `"parametric"` or `"residual"`. `"parametric"` draws
#'   new link factors from `N(f_hat, sqrt(Var(f_hat)))` (Mack-style);
#'   `"residual"` resamples standardized Pearson residuals and reconstructs
#'   the alt triangle.
#' @param mode One of `"dev"`, `"pooled"`, `"dev_maturity"`. Controls how
#'   residuals (residual method) or per-link sigma (parametric method) are
#'   grouped. `"dev"` keeps each development link independent
#'   (Mack-faithful). `"pooled"` shares residuals across links. `"dev_maturity"`
#'   uses per-link before maturity and pooled after.
#' @param process One of `"normal"`, `"gamma"`, `"odp"`. Stored as metadata;
#'   downstream fit functions read this to choose the Stage 2 noise
#'   distribution. `"gamma"` matches `ChainLadder::BootChainLadder`
#'   defaults for non-negative right-skewed loss data.
#' @param B Number of bootstrap replicates. Default `1000`.
#' @param seed Optional integer seed for reproducibility.
#' @param alpha Variance exponent in Mack's `Var(C_{k+1} | C_k) = sigma_k^2
#'   C_k^alpha`. Default `1` (volume-weighted).
#' @param maturity Required only when `mode = "dev_maturity"`. Four-type
#'   dispatch following the package convention: `NULL` (error in this mode),
#'   a `Maturity` object, the string `"auto"`, or a function
#'   `function(tri) -> Maturity`.
#' @param ... Reserved for future use.
#'
#' @return An object of class `BootstrapTriangle` (a list) with elements:
#' \describe{
#'   \item{`alt_triangles`}{Long-format `data.table` with columns
#'     `[groups]`, `cohort`, `dev`, `rep`, `loss`. `rep` ranges over `1..B`.
#'     Observed-region cells contain residual-perturbed (or original for
#'     `"parametric"`) cumulative loss; the missing region contains
#'     Stage 1 forward projection means.}
#'   \item{`residual_pool`}{`data.table` of the standardized residuals used,
#'     with the `pool_id` column identifying which pool each residual
#'     belongs to (depends on `mode`).}
#'   \item{`f_anchor`}{Per-link Mack factor estimates `f_hat` with
#'     `n_cohorts`.}
#'   \item{`sigma2_anchor`}{Per-link Mack `sigma^2` and `Var(f_hat)`.}
#'   \item{`meta`}{`list(method, mode, process, B, seed, alpha, target,
#'     groups, maturity)`.}
#' }
#'
#' @seealso `dev/BOOTSTRAP.md` for the full design rationale.
#'
#' @examples
#' \dontrun{
#' data(experience)
#' tri <- as_triangle(
#'   experience[coverage == "SUR"],
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "loss_incr",
#'   premium  = "premium_incr"
#' )
#'
#' boots <- bootstrap(tri, method = "residual", mode = "dev",
#'                    process = "gamma", B = 500, seed = 1)
#' print(boots)
#' }
#'
#' @export
bootstrap <- function(x, ...) {
  UseMethod("bootstrap")
}


#' @rdname bootstrap
#' @export
bootstrap.Triangle <- function(x,
                                method   = c("parametric", "residual"),
                                mode     = c("dev", "pooled", "dev_maturity"),
                                process  = c("normal", "gamma", "odp"),
                                B        = 1000L,
                                seed     = NULL,
                                alpha    = 1,
                                maturity = NULL,
                                ...) {

  .assert_class(x, "Triangle")
  method  <- match.arg(method)
  mode    <- match.arg(mode)
  process <- match.arg(process)

  if (!is.numeric(B) || length(B) != 1L || is.na(B) || B < 1L)
    stop("`B` must be a single positive integer.", call. = FALSE)
  B <- as.integer(B)

  if (!is.numeric(alpha) || length(alpha) != 1L ||
      is.na(alpha) || !is.finite(alpha))
    stop("`alpha` must be a single finite numeric value.", call. = FALSE)

  if (!is.null(seed)) {
    if (!is.numeric(seed) || length(seed) != 1L || is.na(seed))
      stop("`seed` must be a single numeric value or NULL.", call. = FALSE)
    set.seed(as.integer(seed))
  }

  if (identical(mode, "dev_maturity")) {
    maturity <- .resolve_maturity(maturity, x)
    if (is.null(maturity))
      stop("`mode = 'dev_maturity'` requires a maturity. Pass ",
           "`maturity = 'auto'` for automatic detection, or supply a ",
           "Maturity object.", call. = FALSE)
  } else {
    maturity <- NULL
  }

  grp <- attr(x, "groups")
  if (is.null(grp)) grp <- character(0)

  # 1) Build Link (loss-side ATA) -------------------------------------------
  link <- as_link(x, target = "loss", drop_invalid = TRUE)

  # 2) Compute Mack anchor per (group, ata_to) ------------------------------
  anchor <- .boot_anchor(link, grp = grp, alpha = alpha)

  # 3) Attach standardized residuals to each Link row ----------------------
  link <- .boot_attach_residuals(link, anchor = anchor, grp = grp)

  # 4) Build residual pool per mode ----------------------------------------
  pool <- .boot_build_pool(link, anchor = anchor, grp = grp,
                            mode = mode, maturity = maturity)

  # 5) Stage 1 — B alt triangles -------------------------------------------
  alt_triangles <- .boot_stage1(
    triangle = x, link = link, anchor = anchor, pool = pool,
    grp = grp, method = method, B = B, alpha = alpha
  )

  # 6) Assemble -------------------------------------------------------------
  structure(
    list(
      alt_triangles = alt_triangles,
      residual_pool = pool,
      f_anchor      = anchor[, .SD,
                              .SDcols = c(grp, "ata_from", "ata_to",
                                          "f_hat", "n_cohorts")],
      sigma2_anchor = anchor[, .SD,
                              .SDcols = c(grp, "ata_from", "ata_to",
                                          "sigma2", "f_var")],
      meta = list(
        method   = method,
        mode     = mode,
        process  = process,
        B        = B,
        seed     = seed,
        alpha    = alpha,
        target   = "loss",
        groups   = grp,
        maturity = maturity
      )
    ),
    class = c("BootstrapTriangle", "list")
  )
}


# Internal: per-link Mack anchor (f_hat, sigma2, f_var, n) -----------------
#
# Volume-weighted f_hat = sum(target_to) / sum(target_from).
# Mack sigma^2_k     = (1/(n-1)) * sum(C_{k-1} * (f_ik - f_hat)^2)
#                     = (1/(n-1)) * sum((target_to - f_hat*target_from)^2 / target_from)
# Var(f_hat)         = sigma^2_k / sum(target_from)
#
# When n=1 for the last link, use Mack tail rule:
#   sigma^2_K = min(sigma^2_{K-1}^2 / sigma^2_{K-2}, sigma^2_{K-2}, sigma^2_{K-1})
# Simpler fallback when K < 3: sigma^2_K = sigma^2_{K-1}.
.boot_anchor <- function(link, grp, alpha = 1) {
  # data.table NSE
  target_from <- target_to <- f_hat <- sigma2 <- f_var <- sum_from <- NULL

  by_cols <- c(grp, "ata_from", "ata_to")

  anchor <- link[is.finite(target_from) & is.finite(target_to) & target_from > 0,
                 {
                   f       <- sum(target_to) / sum(target_from)
                   n       <- .N
                   if (n >= 2L) {
                     resid_sq <- (target_to - f * target_from)^2 / target_from
                     s2 <- sum(resid_sq) / (n - 1L)
                   } else {
                     s2 <- NA_real_
                   }
                   list(
                     f_hat     = f,
                     sigma2    = s2,
                     n_cohorts = n,
                     sum_from  = sum(target_from)
                   )
                 },
                 by = by_cols]

  # Mack tail rule for sigma2 at the last link if n=1
  if (length(grp) > 0L) {
    by_grp <- grp
  } else {
    by_grp <- NULL
  }
  data.table::setorderv(anchor, c(grp, "ata_from"))
  anchor[, sigma2 := .boot_fill_sigma2(sigma2), by = by_grp]

  anchor[, f_var := data.table::fifelse(
    is.finite(sigma2) & is.finite(sum_from) & sum_from > 0,
    sigma2 / sum_from,
    NA_real_
  )]

  anchor[]
}


# Mack tail-rule extrapolation for sigma^2 (per group, ordered by ata_from)
.boot_fill_sigma2 <- function(s2) {
  K <- length(s2)
  if (K == 0L) return(s2)
  out <- s2
  for (i in seq_len(K)) {
    if (is.na(out[i])) {
      # Use the last available sigma^2 (LOCF). Mack tail rule with
      # min(s_{K-1}^2/s_{K-2}, ...) needs >= 2 prior values; LOCF is a
      # simpler conservative fallback that matches `sigma_method = "locf"`
      # used elsewhere in the package.
      if (i >= 2L && is.finite(out[i - 1L])) {
        out[i] <- out[i - 1L]
      } else {
        out[i] <- 0
      }
    }
  }
  out
}


# Internal: standardized Pearson residuals on the Link rows ---------------
#
# r_ik = (target_to - f_hat_k * target_from) / sqrt(sigma2_k * target_from)
#
# Returns the Link with two new columns: `residual` and `pool_id`. The
# `pool_id` is filled later by .boot_build_pool() (mode-dependent).
.boot_attach_residuals <- function(link, anchor, grp) {
  # NSE
  target_from <- target_to <- f_hat <- sigma2 <- residual <- NULL

  by_cols <- c(grp, "ata_from", "ata_to")

  dt <- .copy_dt(link)
  dt <- merge(dt, anchor[, .SD,
                          .SDcols = c(by_cols, "f_hat", "sigma2")],
              by = by_cols, all.x = TRUE, sort = FALSE)

  dt[, residual := data.table::fifelse(
    is.finite(target_from) & target_from > 0 &
      is.finite(sigma2) & sigma2 > 0 &
      is.finite(target_to) & is.finite(f_hat),
    (target_to - f_hat * target_from) / sqrt(sigma2 * target_from),
    NA_real_
  )]

  dt[, c("f_hat", "sigma2") := NULL]
  dt
}


# Internal: build residual pool with `pool_id` per mode -------------------
.boot_build_pool <- function(link, anchor, grp, mode, maturity) {
  residual <- ata_to <- mat_change <- grp_key <- NULL  # NSE

  dt <- link[is.finite(residual)]

  # Build group key string ("g1|g2|...") once
  if (length(grp) > 0L) {
    dt[, ("grp_key") := do.call(paste, c(.SD, sep = "|")), .SDcols = grp]
  } else {
    dt[, ("grp_key") := ""]
  }

  if (identical(mode, "dev")) {
    dt[, ("pool_id") := paste(grp_key, as.character(ata_to), sep = "|")]
  } else if (identical(mode, "pooled")) {
    dt[, ("pool_id") := data.table::fifelse(grp_key == "", "all", grp_key)]
  } else if (identical(mode, "dev_maturity")) {
    # per-group maturity boundary: ata_to < k* keeps per-dev pool, ata_to >= k*
    # collapses to a single group-level pooled bucket ("POST").
    if (length(grp) > 0L) {
      mat <- data.table::as.data.table(maturity)
      mat <- mat[, .SD, .SDcols = c(grp, "change")]
      data.table::setnames(mat, "change", "mat_change")
      dt <- merge(dt, mat, by = grp, all.x = TRUE, sort = FALSE)
    } else {
      mc <- attr(maturity, "change")
      if (is.null(mc)) {
        mat_df <- data.table::as.data.table(maturity)
        mc <- mat_df$change[1L]
      }
      dt[, ("mat_change") := mc]
    }
    is_post <- is.finite(dt$mat_change) & dt$ata_to >= dt$mat_change
    dt[, ("pool_id") := data.table::fifelse(
      is_post,
      paste(grp_key, "POST", sep = "|"),
      paste(grp_key, as.character(ata_to), sep = "|")
    )]
    dt[, mat_change := NULL]
  }

  dt[, grp_key := NULL]

  keep <- c(grp, "cohort", "ata_from", "ata_to", "residual", "pool_id")
  dt[, .SD, .SDcols = keep]
}


# Internal: Stage 1 — generate B alt triangles -----------------------------
#
# For each group:
#   1. Snapshot the original cumulative loss matrix (cohort x dev grid).
#   2. Identify observed and missing cells.
#   3. For each replicate b in 1..B:
#       a. Build alt observed cells:
#          - residual method: chain residual resample through the cumulative
#            recursion: alt C_{i,k} = f_hat_k * alt C_{i,k-1} + r* * sd_k
#          - parametric method: keep original observed; draw f_k* ~
#            N(f_hat, sqrt(Var(f_hat))) for projection.
#       b. Refit f_k* from alt observed (residual) or use drawn f_k*
#          (parametric).
#       c. Forward-project missing cells using f_k*.
#       d. Stack into long-format with rep = b.
#
# Returns a long-format data.table with columns [grp..], cohort, dev, rep,
# loss.
.boot_stage1 <- function(triangle, link, anchor, pool,
                          grp, method, B, alpha) {

  # Per-group iteration
  if (length(grp) > 0L) {
    grp_vals <- unique(triangle[, .SD, .SDcols = grp])
    out_list <- vector("list", nrow(grp_vals))
    for (gi in seq_len(nrow(grp_vals))) {
      gkey <- grp_vals[gi]
      tri_g <- merge(triangle, gkey, by = grp, sort = FALSE)
      link_g <- merge(link, gkey, by = grp, sort = FALSE)
      anchor_g <- merge(anchor, gkey, by = grp, sort = FALSE)
      pool_g <- merge(pool, gkey, by = grp, sort = FALSE)
      out_list[[gi]] <- .boot_stage1_one(
        triangle = tri_g, link = link_g, anchor = anchor_g, pool = pool_g,
        method = method, B = B, alpha = alpha,
        grp_vals = gkey
      )
    }
    data.table::rbindlist(out_list, use.names = TRUE)
  } else {
    .boot_stage1_one(
      triangle = triangle, link = link, anchor = anchor, pool = pool,
      method = method, B = B, alpha = alpha, grp_vals = NULL
    )
  }
}


# Per-group worker for Stage 1. Returns long-format with `rep` column.
.boot_stage1_one <- function(triangle, link, anchor, pool,
                              method, B, alpha, grp_vals) {

  cohort <- dev <- loss <- NULL  # NSE

  # Snapshot cohort x dev cumulative loss matrix
  cohorts <- sort(unique(triangle$cohort))
  devs    <- sort(unique(triangle$dev))
  n_coh   <- length(cohorts)
  n_dev   <- length(devs)

  # Wide observed matrix [cohort × dev]
  mat_obs <- matrix(NA_real_, nrow = n_coh, ncol = n_dev,
                    dimnames = list(as.character(cohorts), as.character(devs)))
  obs_dt <- triangle[, .SD, .SDcols = c("cohort", "dev", "loss")]
  for (r in seq_len(nrow(obs_dt))) {
    ci <- match(as.character(obs_dt$cohort[r]), rownames(mat_obs))
    di <- match(as.character(obs_dt$dev[r]),    colnames(mat_obs))
    if (!is.na(ci) && !is.na(di))
      mat_obs[ci, di] <- obs_dt$loss[r]
  }

  # f_hat and sigma2 per link, indexed by ata_to (= colname after first)
  # ata_from -> ata_to mapping uses sequential dev indices.
  data.table::setorderv(anchor, "ata_from")
  link_to_idx <- match(anchor$ata_to, devs)
  f_hat_vec  <- anchor$f_hat
  sigma2_vec <- anchor$sigma2
  fvar_vec   <- anchor$f_var
  sum_from   <- anchor$sum_from
  n_links    <- nrow(anchor)

  # Residual pool by pool_id
  pool_by_id <- split(pool$residual, pool$pool_id)

  # For residual method, we need to know which pool_id each (cohort, ata_to)
  # row maps to. Build a lookup keyed by ata_to (since pool_id was built
  # per group already inside .boot_build_pool, and we are inside one group).
  if (identical(method, "residual")) {
    pool_lookup <- unique(pool[, .SD, .SDcols = c("ata_to", "pool_id")])
    pool_id_by_to <- setNames(pool_lookup$pool_id,
                              as.character(pool_lookup$ata_to))
  }

  # Identify, per cohort, the last observed dev index (max j where mat_obs[i, j] is finite)
  last_obs_idx <- apply(mat_obs, 1L, function(row) {
    ok <- which(is.finite(row))
    if (length(ok) == 0L) NA_integer_ else max(ok)
  })

  # Allocate B output replicates as 3D array [cohort × dev × B]
  out_arr <- array(NA_real_, dim = c(n_coh, n_dev, B))

  for (b in seq_len(B)) {

    if (identical(method, "residual")) {

      # Chain residual resample forward through the cumulative recursion.
      # alt_C[i, k] = f_hat_k * alt_C[i, k-1] + r* * sqrt(sigma2_k * alt_C[i, k-1])
      # Base column (dev index 1) keeps the original observed C.
      mat_alt <- matrix(NA_real_, nrow = n_coh, ncol = n_dev)
      mat_alt[, 1L] <- mat_obs[, 1L]

      for (k in seq_len(n_links)) {
        to_col <- link_to_idx[k]
        if (is.na(to_col) || to_col < 2L) next
        from_col <- to_col - 1L
        f_k  <- f_hat_vec[k]
        s2_k <- sigma2_vec[k]
        # cohorts with both alt_C[from] and originally observed C[to] are alt-able
        prev_alt <- mat_alt[, from_col]
        was_obs  <- is.finite(mat_obs[, to_col]) & is.finite(prev_alt) & prev_alt > 0

        n_alt <- sum(was_obs)
        if (n_alt > 0L) {
          pid <- pool_id_by_to[as.character(devs[to_col])]
          r_pool <- if (!is.na(pid)) pool_by_id[[pid]] else NULL
          if (is.null(r_pool) || length(r_pool) == 0L) {
            r_draw <- rep(0, n_alt)
          } else {
            r_draw <- sample(r_pool, n_alt, replace = TRUE)
          }
          if (!is.finite(s2_k) || s2_k < 0) s2_k <- 0
          mat_alt[was_obs, to_col] <- f_k * prev_alt[was_obs] +
            r_draw * sqrt(s2_k * prev_alt[was_obs])
        }
      }

      # Clip alt observed cells to >=0 (cumulative loss is non-negative)
      mat_alt[mat_alt < 0 & is.finite(mat_alt)] <- 0

      # Refit f_k* from alt observed
      f_star <- f_hat_vec  # fallback
      for (k in seq_len(n_links)) {
        to_col <- link_to_idx[k]
        if (is.na(to_col) || to_col < 2L) next
        from_col <- to_col - 1L
        num <- sum(mat_alt[, to_col],   na.rm = TRUE)
        den <- sum(mat_alt[, from_col], na.rm = TRUE)
        if (is.finite(den) && den > 0) f_star[k] <- num / den
      }

      # Forward-project missing cells from each cohort's last observed dev
      for (i in seq_len(n_coh)) {
        last_j <- last_obs_idx[i]
        if (is.na(last_j) || last_j >= n_dev) next
        base <- mat_alt[i, last_j]
        if (!is.finite(base)) next
        for (j in seq(last_j + 1L, n_dev)) {
          k_idx <- match(devs[j], anchor$ata_to)
          if (is.na(k_idx)) {
            mat_alt[i, j] <- base
          } else {
            mat_alt[i, j] <- f_star[k_idx] * base
            base <- mat_alt[i, j]
          }
        }
      }

      out_arr[, , b] <- mat_alt

    } else {

      # Parametric method: original observed cells unchanged; draw f_k* ~
      # N(f_hat, sqrt(Var(f_hat))). Forward-project from each cohort's last
      # observed dev using the drawn f_k*.
      f_star <- f_hat_vec
      for (k in seq_len(n_links)) {
        fv <- fvar_vec[k]
        if (is.finite(fv) && fv > 0) {
          f_star[k] <- stats::rnorm(1L, f_hat_vec[k], sqrt(fv))
        }
      }

      mat_alt <- mat_obs

      for (i in seq_len(n_coh)) {
        last_j <- last_obs_idx[i]
        if (is.na(last_j) || last_j >= n_dev) next
        base <- mat_alt[i, last_j]
        if (!is.finite(base)) next
        for (j in seq(last_j + 1L, n_dev)) {
          k_idx <- match(devs[j], anchor$ata_to)
          if (is.na(k_idx)) {
            mat_alt[i, j] <- base
          } else {
            mat_alt[i, j] <- f_star[k_idx] * base
            base <- mat_alt[i, j]
          }
        }
      }

      mat_alt[mat_alt < 0 & is.finite(mat_alt)] <- 0
      out_arr[, , b] <- mat_alt
    }
  }

  # Reshape 3D array -> long data.table.
  # `as.numeric(out_arr)` flattens column-major: cohort fastest, then dev,
  # then rep. We construct the index columns to match exactly that order.
  long <- data.table::data.table(
    cohort = rep(rep(cohorts, times = n_dev), times = B),
    dev    = rep(rep(devs, each = n_coh),    times = B),
    rep    = rep(seq_len(B), each = n_coh * n_dev),
    loss   = as.numeric(out_arr)
  )

  if (!is.null(grp_vals)) {
    for (col in names(grp_vals)) {
      long[, (col) := grp_vals[[col]]]
    }
    data.table::setcolorder(long, c(names(grp_vals), "cohort", "dev", "rep", "loss"))
  }

  long[]
}


#' Print method for BootstrapTriangle
#' @param x A `BootstrapTriangle` object.
#' @param ... Unused.
#' @method print BootstrapTriangle
#' @export
print.BootstrapTriangle <- function(x, ...) {
  m <- x$meta
  cat("<BootstrapTriangle>\n")
  cat(sprintf("  method   : %s\n", m$method))
  cat(sprintf("  mode     : %s\n", m$mode))
  cat(sprintf("  process  : %s (Stage 2 distribution, applied by fit)\n",
              m$process))
  cat(sprintf("  B        : %d replicates\n", m$B))
  cat(sprintf("  alpha    : %g\n", m$alpha))
  if (!is.null(m$seed))
    cat(sprintf("  seed     : %s\n", as.character(m$seed)))
  cat(sprintf("  groups   : %s\n",
              if (length(m$groups) == 0L) "(none)"
              else paste(m$groups, collapse = ", ")))
  cat(sprintf("  n_links  : %d\n", nrow(x$f_anchor)))
  cat(sprintf("  n_pool   : %d residuals (%d unique pool_id)\n",
              nrow(x$residual_pool),
              length(unique(x$residual_pool$pool_id))))
  cat(sprintf("  alt size : %d rows ([cohort x dev x B] long-format)\n",
              nrow(x$alt_triangles)))
  invisible(x)
}

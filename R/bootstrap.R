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


#' Validate the bootstrap argument combination
#'
#' Internal helper called by `bootstrap.Triangle()` after `match.arg()`.
#' Enforces the type/residual/process/method/tail combination matrix and
#' warns when an argument is silently ignored.
#'
#' @param type,residual,process,method,tail Resolved (post-match.arg) values.
#' @param min_pool,hat_adj,maturity Scalar values to validate.
#' @param residual_set,process_set,method_set,tail_set,hat_adj_set,min_pool_set
#'   Logicals indicating whether the user explicitly passed each argument
#'   (computed via `match.call()` in the caller).
#'
#' @return `invisible(TRUE)` after raising any errors / warnings.
#'
#' @keywords internal
.validate_bootstrap_args <- function(type, residual, process, method, tail,
                                     min_pool, hat_adj, maturity,
                                     residual_set, process_set,
                                     method_set, tail_set, hat_adj_set,
                                     min_pool_set) {

  # `min_pool` must be a single positive integer regardless of type/method.
  if (!is.numeric(min_pool) || length(min_pool) != 1L ||
      is.na(min_pool) || min_pool < 1L ||
      !isTRUE(all.equal(min_pool, round(min_pool))))
    stop("`min_pool` must be a single positive integer.", call. = FALSE)

  if (identical(type, "parametric")) {
    if (process_set && !identical(process, "normal"))
      stop("type = 'parametric' (Mack 1993 closed-form) requires ",
           "process = 'normal'. For other process distributions use ",
           "type = 'nonparametric'.",
           call. = FALSE)
    if (residual_set)
      warning("type = 'parametric' uses closed-form simulation; ",
              "'residual' argument is ignored.",
              call. = FALSE)
    if (method_set)
      warning("type = 'parametric' has no residual pool; ",
              "'method' argument is ignored.",
              call. = FALSE)
    if (tail_set)
      warning("type = 'parametric' has no residual pool; ",
              "'tail' argument is ignored.",
              call. = FALSE)
    if (min_pool_set)
      warning("type = 'parametric' has no residual pool; ",
              "'min_pool' argument is ignored.",
              call. = FALSE)
    if (hat_adj_set && isTRUE(hat_adj))
      warning("'hat_adj' is only defined for residual = 'cell'; ignored.",
              call. = FALSE)
  } else {
    # type == "nonparametric"
    if (identical(residual, "cell"))
      stop("residual = 'cell' (Pearson on incremental cells, ",
           "E-V 1999/2002 path) is not yet implemented. Use ",
           "residual = 'link' (Mack 1993 / Pinheiro 2003) for now. ",
           "Cell support arrives in Phase 5b.2.",
           call. = FALSE)
    if (identical(residual, "link") && isTRUE(hat_adj))
      warning("hat_adj is currently only implemented for residual = ",
              "'cell'. Pinheiro 2003 defines it for link residuals but ",
              "implementation is deferred to a future release. Ignored.",
              call. = FALSE)
    if (identical(process, "lognormal"))
      stop("process = 'lognormal' not yet implemented (Phase 5b.3). ",
           "Use 'gamma', 'od_pois', or 'normal'.",
           call. = FALSE)
    if (!identical(method, "tail_pooled")) {
      if (tail_set)
        warning("'tail' applies only to method = 'tail_pooled'; ignored.",
                call. = FALSE)
      if (min_pool_set)
        warning("'min_pool' applies only to method = 'tail_pooled' ",
                "with tail = 'auto'; ignored.",
                call. = FALSE)
    } else {
      if (!identical(tail, "auto") && min_pool_set)
        warning("'min_pool' applies only to tail = 'auto'; ignored.",
                call. = FALSE)
    }
  }

  invisible(TRUE)
}


#' Bootstrap a Triangle
#'
#' @description
#' Generate `B` alternative realizations of a `Triangle` via nonparametric
#' (England-Verrall residual) or parametric (Mack normal closed-form) Stage 1
#' perturbation. The output is a model-agnostic `BootstrapTriangle` object
#' that downstream fit functions (`fit_cl` / `fit_ed` / `fit_lr`) consume to
#' recover parameter and process risk decomposition.
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
#' @param type One of `"nonparametric"` or `"parametric"`. `"parametric"`
#'   draws new link factors from `N(f_hat, sqrt(Var(f_hat)))` (Mack 1993
#'   closed-form); `"nonparametric"` resamples standardized residuals and
#'   reconstructs the alt triangle (England-Verrall / Pinheiro).
#' @param residual Residual scope for `type = "nonparametric"`. One of
#'   `"link"` (Mack 1993 / Pinheiro 2003 — Pearson residuals on link
#'   factors) or `"cell"` (E-V 1999/2002 — Pearson residuals on
#'   incremental cells; *not yet implemented*, arrives in Phase 5b.2).
#' @param hat_adj Logical. Hat-matrix adjustment for the cell residual
#'   path. Defaults `FALSE`. Currently only defined for `residual = "cell"`;
#'   warned-ignored otherwise.
#' @param process One of `"gamma"`, `"od_pois"`, `"normal"`, `"lognormal"`.
#'   Stored as metadata; downstream fit functions read this to choose the
#'   Stage 2 noise distribution. `"gamma"` matches
#'   `ChainLadder::BootChainLadder` defaults for non-negative right-skewed
#'   loss data. `"lognormal"` is reserved for Phase 5b.3 and currently
#'   errors.
#' @param method Residual-pool grouping. One of `"pooled"`, `"separated"`,
#'   `"tail_pooled"`. `"pooled"` shares residuals across all links;
#'   `"separated"` keeps each development link independent (Mack-faithful);
#'   `"tail_pooled"` uses per-link pools before a cut and a single pooled
#'   bucket after.
#' @param tail Tail-cut rule for `method = "tail_pooled"`. One of `"auto"`
#'   (cut at the smallest `ata_to` whose residual count drops below
#'   `min_pool`) or `"maturity"` (cut at the resolved `Maturity` change
#'   point).
#' @param min_pool Minimum residual count per per-link pool under
#'   `method = "tail_pooled" && tail = "auto"`. Default `5`.
#' @param maturity Required only when `method = "tail_pooled" &&
#'   tail = "maturity"`. Four-type dispatch: `NULL`, a `Maturity` object,
#'   the string `"auto"`, or a function `function(tri) -> Maturity`.
#' @param B Number of bootstrap replicates. Default `1000`.
#' @param seed Optional integer seed for reproducibility.
#' @param alpha Variance exponent in Mack's `Var(C_{k+1} | C_k) = sigma_k^2
#'   C_k^alpha`. Default `1` (volume-weighted).
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
#'     belongs to (depends on `method`/`tail`).}
#'   \item{`f_anchor`}{Per-link Mack factor estimates `f_hat` with
#'     `n_cohorts`.}
#'   \item{`sigma2_anchor`}{Per-link Mack `sigma^2` and `Var(f_hat)`.}
#'   \item{`meta`}{`list(type, residual, hat_adj, process, method, tail,
#'     min_pool, B, seed, alpha, target, groups, maturity)`.}
#' }
#'
#' @seealso `dev/BOOTSTRAP.md` for the full design rationale.
#'
#' @examples
#' \dontrun{
#' data(experience)
#' tri <- as_triangle(
#'   experience[coverage == "surgery"],
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "loss_incr",
#'   premium  = "premium_incr"
#' )
#'
#' boots <- bootstrap(tri, type = "nonparametric", residual = "link",
#'                    method = "separated", process = "gamma",
#'                    B = 500, seed = 1)
#' print(boots)
#' }
#'
#' @export
bootstrap <- function(x, ...) {
  UseMethod("bootstrap")
}


#' @rdname bootstrap
#' @param target Cumulative metric to perturb. One of `"loss"` (default) or
#'   `"prem"`. The value column in `$alt_triangles` is named after this
#'   target so downstream refit helpers know which column to read.
#' @export
bootstrap.Triangle <- function(x,
                                type     = c("nonparametric", "parametric"),
                                residual = c("link", "cell"),
                                hat_adj  = FALSE,
                                process  = c("gamma", "od_pois", "normal",
                                             "lognormal"),
                                method   = c("pooled", "separated",
                                             "tail_pooled"),
                                tail     = c("auto", "maturity"),
                                min_pool = 5L,
                                maturity = NULL,
                                target   = c("loss", "prem"),
                                B        = 1000L,
                                seed     = NULL,
                                alpha    = 1,
                                ...) {

  .assert_class(x, "Triangle")

  # Detect explicitly-passed args (before match.arg() overwrites) so the
  # validator can issue "ignored" warnings only when the user actually
  # supplied a value.
  mc <- match.call()
  residual_set <- "residual" %in% names(mc)
  process_set  <- "process"  %in% names(mc)
  method_set   <- "method"   %in% names(mc)
  tail_set     <- "tail"     %in% names(mc)
  hat_adj_set  <- "hat_adj"  %in% names(mc)
  min_pool_set <- "min_pool" %in% names(mc)

  type     <- match.arg(type)
  residual <- match.arg(residual)
  process  <- match.arg(process)
  method   <- match.arg(method)
  tail     <- match.arg(tail)
  target   <- match.arg(target)

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

  .validate_bootstrap_args(
    type = type, residual = residual, process = process,
    method = method, tail = tail,
    min_pool = min_pool, hat_adj = hat_adj, maturity = maturity,
    residual_set = residual_set, process_set = process_set,
    method_set = method_set, tail_set = tail_set,
    hat_adj_set = hat_adj_set, min_pool_set = min_pool_set
  )

  min_pool <- as.integer(min_pool)

  # Parametric path has only one supported process (Mack 1993 closed-form
  # uses Normal). When the user didn't explicitly request a different
  # process, silently coerce to "normal" so meta$process truthfully
  # records what Stage 1 simulated under. (If the user *did* set process
  # to something non-normal, the validator already errored above.)
  if (identical(type, "parametric")) process <- "normal"

  # Resolve maturity when tail_pooled + maturity. Note: for tail = "auto"
  # we don't need a Maturity object — the cut is derived from residual
  # counts vs `min_pool`.
  if (identical(method, "tail_pooled") && identical(tail, "maturity")) {
    maturity <- .resolve_maturity(maturity, x)
    if (is.null(maturity))
      stop("`method = 'tail_pooled'` with `tail = 'maturity'` requires a ",
           "maturity. Pass `maturity = 'auto'` for automatic detection, ",
           "or supply a Maturity object.", call. = FALSE)
  } else {
    maturity <- NULL
  }

  grp <- attr(x, "groups")
  if (is.null(grp)) grp <- character(0)

  is_residual_mode <- identical(type, "nonparametric")

  if (is_residual_mode) {
    # 1) Build Link on the chosen target
    link <- as_link(x, target = target, drop_invalid = TRUE)

    # 2) Compute Mack anchor per (group, ata_to)
    anchor <- .boot_anchor(link, grp = grp, alpha = alpha)

    # 3) Attach standardized residuals to each Link row
    link <- .boot_attach_residuals(link, anchor = anchor, grp = grp)

    # 4) Build residual pool per (method, tail)
    pool <- .boot_build_pool(link, anchor = anchor, grp = grp,
                              method = method, tail = tail,
                              min_pool = min_pool, maturity = maturity)
  } else {
    # parametric path: closed-form simulation, no residual pool needed.
    # We still compute the anchor (f_hat, sigma2, f_var) — those drive
    # the N(f_hat, sqrt(Var(f_hat))) draws inside .boot_stage1_one.
    link   <- as_link(x, target = target, drop_invalid = TRUE)
    anchor <- .boot_anchor(link, grp = grp, alpha = alpha)
    pool   <- .boot_empty_pool(grp)
  }

  # 5) Stage 1 — B alt triangles -------------------------------------------
  alt_triangles <- .boot_stage1(
    triangle = x, link = link, anchor = anchor, pool = pool,
    grp = grp, is_residual_mode = is_residual_mode,
    B = B, alpha = alpha, target = target
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
        type     = type,
        residual = residual,
        hat_adj  = hat_adj,
        process  = process,
        method   = method,
        tail     = if (identical(method, "tail_pooled")) tail
                   else NA_character_,
        min_pool = if (identical(method, "tail_pooled") &&
                       identical(tail, "auto")) min_pool
                   else NA_integer_,
        B        = B,
        seed     = seed,
        alpha    = alpha,
        target   = target,
        groups   = grp,
        maturity = maturity
      )
    ),
    class = c("BootstrapTriangle", "list")
  )
}


# Empty residual pool used by the parametric path so downstream code that
# inspects `pool$residual` / `pool$pool_id` sees a well-formed 0-row table.
.boot_empty_pool <- function(grp) {
  keep <- c(grp, "cohort", "ata_from", "ata_to", "residual", "pool_id")
  out <- data.table::data.table()
  for (col in keep) {
    out[, (col) := if (col == "residual") numeric(0)
                   else if (col %in% c("ata_from", "ata_to")) integer(0)
                   else character(0)]
  }
  out
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


# Internal: build residual pool with `pool_id` per (method, tail) ---------
.boot_build_pool <- function(link, anchor, grp, method, tail, min_pool,
                              maturity) {
  # data.table NSE
  residual <- ata_to <- mat_change <- grp_key <- N <- below <-
    cut_to <- is_post <- NULL

  dt <- link[is.finite(residual)]

  # Build group key string ("g1|g2|...") once
  if (length(grp) > 0L) {
    dt[, ("grp_key") := do.call(paste, c(.SD, sep = "|")), .SDcols = grp]
  } else {
    dt[, ("grp_key") := ""]
  }

  if (identical(method, "separated")) {
    dt[, ("pool_id") := paste(grp_key, as.character(ata_to), sep = "|")]
  } else if (identical(method, "pooled")) {
    dt[, ("pool_id") := data.table::fifelse(grp_key == "", "all", grp_key)]
  } else if (identical(method, "tail_pooled")) {
    if (identical(tail, "maturity")) {
      # per-group maturity boundary: ata_to < k* keeps per-dev pool, ata_to
      # >= k* collapses to a single group-level pooled bucket ("POST").
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
      dt[, ("is_post") := is.finite(mat_change) & ata_to >= mat_change]
      dt[, ("pool_id") := data.table::fifelse(
        is_post,
        paste(grp_key, "POST", sep = "|"),
        paste(grp_key, as.character(ata_to), sep = "|")
      )]
      dt[, c("mat_change", "is_post") := NULL]
    } else {
      # tail = "auto" -- per-group cut at the smallest ata_to whose count
      # falls below `min_pool`. ata_to < cut_to keeps per-dev pool; ata_to
      # >= cut_to collapses into a single group-level "POST" bucket. No
      # cut (all counts >= min_pool) gives fully per-dev pools; first
      # ata_to below min_pool gives fully pooled (POST only).
      counts <- dt[, .N, by = c("grp_key", "ata_to")]
      data.table::setorderv(counts, c("grp_key", "ata_to"))
      counts[, ("below") := N < min_pool]
      cut_lookup <- counts[, {
        first_below <- which(below)[1L]
        list(cut_to = if (is.na(first_below)) NA_real_
                       else as.numeric(ata_to[first_below]))
      }, by = "grp_key"]
      dt <- merge(dt, cut_lookup, by = "grp_key", all.x = TRUE, sort = FALSE)
      dt[, ("is_post") := is.finite(cut_to) & ata_to >= cut_to]
      dt[, ("pool_id") := data.table::fifelse(
        is_post,
        paste(grp_key, "POST", sep = "|"),
        paste(grp_key, as.character(ata_to), sep = "|")
      )]
      dt[, c("cut_to", "is_post") := NULL]
    }
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
                          grp, is_residual_mode, B, alpha,
                          target = "loss") {

  # Per-group iteration
  if (length(grp) > 0L) {
    grp_vals <- unique(triangle[, .SD, .SDcols = grp])
    out_list <- vector("list", nrow(grp_vals))
    for (gi in seq_len(nrow(grp_vals))) {
      gkey <- grp_vals[gi]
      tri_g <- merge(triangle, gkey, by = grp, sort = FALSE)
      link_g <- merge(link, gkey, by = grp, sort = FALSE)
      anchor_g <- merge(anchor, gkey, by = grp, sort = FALSE)
      pool_g <- if (nrow(pool) > 0L) {
        merge(pool, gkey, by = grp, sort = FALSE)
      } else pool
      out_list[[gi]] <- .boot_stage1_one(
        triangle = tri_g, link = link_g, anchor = anchor_g, pool = pool_g,
        is_residual_mode = is_residual_mode, B = B, alpha = alpha,
        grp_vals = gkey, target = target
      )
    }
    data.table::rbindlist(out_list, use.names = TRUE)
  } else {
    .boot_stage1_one(
      triangle = triangle, link = link, anchor = anchor, pool = pool,
      is_residual_mode = is_residual_mode, B = B, alpha = alpha,
      grp_vals = NULL, target = target
    )
  }
}


# Per-group worker for Stage 1. Returns long-format with `rep` column.
.boot_stage1_one <- function(triangle, link, anchor, pool,
                              is_residual_mode, B, alpha, grp_vals,
                              target = "loss") {

  cohort <- dev <- NULL  # NSE

  # Snapshot cohort x dev cumulative loss matrix
  cohorts <- sort(unique(triangle$cohort))
  devs    <- sort(unique(triangle$dev))
  n_coh   <- length(cohorts)
  n_dev   <- length(devs)

  # Wide observed matrix [cohort × dev]
  mat_obs <- matrix(NA_real_, nrow = n_coh, ncol = n_dev,
                    dimnames = list(as.character(cohorts), as.character(devs)))
  obs_dt <- triangle[, .SD, .SDcols = c("cohort", "dev", target)]
  for (r in seq_len(nrow(obs_dt))) {
    ci <- match(as.character(obs_dt$cohort[r]), rownames(mat_obs))
    di <- match(as.character(obs_dt$dev[r]),    colnames(mat_obs))
    if (!is.na(ci) && !is.na(di))
      mat_obs[ci, di] <- obs_dt[[target]][r]
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
  if (is_residual_mode && nrow(pool) > 0L) {
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

    if (is_residual_mode) {

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

  # Reshape 3D array -> long data.table. The value column is named after
  # `target` ("loss" or "prem") so downstream refit helpers know what to
  # read. `as.numeric(out_arr)` flattens column-major: cohort fastest,
  # then dev, then rep.
  long <- data.table::data.table(
    cohort = rep(rep(cohorts, times = n_dev), times = B),
    dev    = rep(rep(devs, each = n_coh),    times = B),
    rep    = rep(seq_len(B), each = n_coh * n_dev)
  )
  long[, (target) := as.numeric(out_arr)]

  if (!is.null(grp_vals)) {
    for (col in names(grp_vals)) {
      long[, (col) := grp_vals[[col]]]
    }
    data.table::setcolorder(long, c(names(grp_vals), "cohort", "dev", "rep", target))
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
  is_param <- identical(m$type, "parametric")
  is_tail  <- identical(m$method, "tail_pooled")

  cat("<BootstrapTriangle>\n")
  cat(sprintf("  type     : %s\n", m$type))
  if (!is_param) {
    cat(sprintf("  residual : %s\n", m$residual))
    cat(sprintf("  hat_adj  : %s\n", as.character(isTRUE(m$hat_adj))))
  }
  cat(sprintf("  process  : %s\n", m$process))
  if (!is_param) {
    cat(sprintf("  method   : %s\n", m$method))
    if (is_tail) {
      cat(sprintf("  tail     : %s\n", m$tail))
      if (identical(m$tail, "auto"))
        cat(sprintf("  min_pool : %d\n", as.integer(m$min_pool)))
    }
  }
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


# =============================================================================
# Phase 2a — Consumer helpers
#
# Internal helpers consumed by fit_lr / fit_loss / fit_premium / backtest in
# Phase 2b-e. Decomposed into single-purpose units so each helper has one job
# and the call site in fit functions is explicit about every step.
#
# Pipeline:
#   boots      <- .resolve_bootstrap(arg, tri, B, seed, ...)
#   refit      <- .boot_refit_{cl,ed,sa}(tri, boots, alpha, ...)
#                 # list(cell_mean, cell_proc_var) — method baked into proc_var
#   cell_real  <- .boot_add_process_noise(refit$cell_mean, refit$cell_proc_var,
#                                          boots$meta$process)
#   se_dt      <- .boot_summarize_se(refit$cell_mean, cell_real)
# =============================================================================


#' Resolve a bootstrap argument to a BootstrapTriangle (4-type dispatch)
#'
#' Mirrors `.resolve_maturity()` / `.resolve_regime()` pattern. Accepts:
#'
#' \itemize{
#'   \item `NULL` (or `FALSE`, back-compat) — returns `NULL` (no bootstrap).
#'   \item `TRUE` (back-compat) — equivalent to `"auto"`.
#'   \item `"auto"` — internal `bootstrap(tri, ...)` call with supplied
#'     defaults.
#'   \item A `BootstrapTriangle` object — returned as-is.
#'   \item A function `function(tri) -> BootstrapTriangle` — invoked on `tri`.
#' }
#'
#' @param arg The bootstrap argument supplied by the user.
#' @param tri A `Triangle` object (the data the bootstrap will be computed on).
#' @param B,seed,type,residual,hat_adj,process,method,tail,min_pool,maturity,target,alpha
#'   Defaults forwarded to `bootstrap.Triangle()` when `arg` resolves to
#'   `"auto"` or `TRUE`.
#'
#' @return A `BootstrapTriangle` object or `NULL`.
#'
#' @keywords internal
.resolve_bootstrap <- function(arg, tri,
                                B        = 1000L,
                                seed     = NULL,
                                type     = "parametric",
                                residual = "link",
                                hat_adj  = FALSE,
                                process  = "normal",
                                method   = "pooled",
                                tail     = "auto",
                                min_pool = 5L,
                                maturity = NULL,
                                target   = "loss",
                                alpha    = 1) {
  if (is.null(arg)) return(NULL)

  # Legacy back-compat: bare logical
  if (is.logical(arg) && length(arg) == 1L && !is.na(arg)) {
    if (isFALSE(arg)) return(NULL)
    if (isTRUE(arg))  arg <- "auto"
  }

  if (inherits(arg, "BootstrapTriangle")) {
    boots_target <- arg$meta$target
    if (is.null(boots_target)) boots_target <- "loss"
    if (!identical(boots_target, target))
      stop("supplied `BootstrapTriangle` has meta$target = '", boots_target,
           "' but this fit expects target = '", target, "'.",
           call. = FALSE)
    return(arg)
  }

  if (identical(arg, "auto")) {
    # Pass only the args that apply to the chosen `type`. Parametric path
    # has no residual pool, so omitting residual/hat_adj/method/tail/
    # min_pool/maturity prevents the validator from triggering "ignored"
    # warnings inside fit_loss / fit_premium / fit_lr (which always
    # forward `type = "parametric"` for their internal default).
    args <- list(tri,
                 type    = type,
                 process = process,
                 target  = target,
                 B       = B,
                 seed    = seed,
                 alpha   = alpha)
    if (identical(type, "nonparametric")) {
      args <- c(args, list(residual = residual,
                           hat_adj  = hat_adj,
                           method   = method,
                           tail     = tail,
                           min_pool = min_pool,
                           maturity = maturity))
    }
    return(do.call(bootstrap, args))
  }

  if (is.function(arg)) {
    out <- arg(tri)
    if (!inherits(out, "BootstrapTriangle"))
      stop("bootstrap function must return a `BootstrapTriangle` object; ",
           "got class: ", paste(class(out), collapse = "/"), ".",
           call. = FALSE)
    out_target <- out$meta$target
    if (is.null(out_target)) out_target <- "loss"
    if (!identical(out_target, target))
      stop("bootstrap function returned a `BootstrapTriangle` with ",
           "meta$target = '", out_target, "' but this fit expects ",
           "target = '", target, "'.",
           call. = FALSE)
    return(out)
  }

  stop("`bootstrap` must be NULL, TRUE/FALSE, \"auto\", a `BootstrapTriangle` ",
       "object, or a function returning one.",
       call. = FALSE)
}


#' Refit chain-ladder per bootstrap replicate (unified entry point)
#'
#' For each replicate `b` in `boots$alt_triangles`, refit factors and
#' compute the per-cell mean projection and process variance. Method
#' dispatch (`"cl"` / `"ed"` / `"sa"`) determines the recursion and the
#' variance structure. `cell_proc_var` carries the method-specific
#' variance baked in so the downstream Stage 2 helper can stay
#' method-blind.
#'
#' Recursions:
#' \itemize{
#'   \item `"cl"` — Mack multiplicative: `C_{k+1} = f_k * C_k`,
#'     `proc_var = sigma^2_f_k * C_k`.
#'   \item `"ed"` — additive exposure-driven: `C_{k+1} = C_k + g_k * P_k`,
#'     `proc_var = sigma^2_g_k * P_k`. Uses the triangle's `prem` column
#'     as the exposure anchor.
#'   \item `"sa"` — stage-adaptive hybrid: ED for `dev < maturity$change`,
#'     CL from `maturity$change` onward.
#' }
#'
#' The CL path reads the target column from `boots$meta$target` (`"loss"`
#' by default, but `fit_premium()` passes `"prem"`). ED and SA paths are
#' loss-specific (they need an external exposure column) and only support
#' `target = "loss"`.
#'
#' @param triangle The original `Triangle` (carries the observed region
#'   mask).
#' @param boots A `BootstrapTriangle` from `bootstrap()`.
#' @param method One of `"cl"`, `"ed"`, `"sa"`.
#' @param alpha Mack variance exponent (currently `1` only).
#' @param maturity Required when `method = "sa"`. A resolved `Maturity`
#'   object (use `.resolve_maturity()` upstream).
#'
#' @return A `data.table` keyed by `[groups..], cohort, dev, rep` with
#'   columns `cell_mean`, `cell_proc_var`.
#'
#' @keywords internal
# Draw realised cell value with given mean and variance, per process
# distribution. Vectorised over `mu` / `var`. Pure numerical kernel --
# designed to map cleanly to a future C port (one call per chain step in
# refit_*_one).
#
# normal: cell = mu + N(0, sqrt(var)). Can go negative -> clipped to 0
#         by caller.
# gamma : cell = Gamma(shape = mu^2/var, rate = mu/var). Requires mu > 0
#         and var > 0; falls back to normal for non-positive cases.
# odp   : phi = var/mu; cell = phi * Poisson(mu/phi). Falls back to
#         normal for non-positive cases.
.boot_draw_noise <- function(mu, var, dist) {
  # NOTE: `dist` is trusted -- one of "normal" / "gamma" / "od_pois".
  # Caller validates once (typically against boots$meta$process). Skipping
  # match.arg() saves ~10% on hot-loop benchmarks where this is called
  # once per chain step.
  n <- length(mu)
  if (n == 0L) return(numeric(0))

  if (dist == "normal") {
    var_safe <- var
    var_safe[var_safe < 0 | !is.finite(var_safe)] <- 0
    return(mu + stats::rnorm(n, 0, sqrt(var_safe)))
  }

  out <- mu
  pos <- is.finite(mu) & is.finite(var) & mu > 0 & var > 0
  neg <- !pos

  if (dist == "gamma") {
    if (any(pos)) {
      shape <- mu[pos]^2 / var[pos]
      rate  <- mu[pos]   / var[pos]
      out[pos] <- stats::rgamma(sum(pos), shape = shape, rate = rate)
    }
  } else if (dist == "od_pois") {
    if (any(pos)) {
      phi <- var[pos] / mu[pos]
      out[pos] <- phi * stats::rpois(sum(pos), lambda = mu[pos] / phi)
    }
  }
  if (any(neg)) {
    var_neg <- var[neg]
    var_neg[var_neg < 0 | !is.finite(var_neg)] <- 0
    out[neg] <- mu[neg] + stats::rnorm(sum(neg), 0, sqrt(var_neg))
  }
  out
}


.boot_refit <- function(triangle, boots,
                         method = c("cl", "ed", "sa"),
                         alpha = 1,
                         maturity = NULL) {
  method <- match.arg(method)
  target <- boots$meta$target
  if (is.null(target)) target <- "loss"
  process_dist <- boots$meta$process
  if (is.null(process_dist)) process_dist <- "normal"

  if (method %in% c("ed", "sa") && !identical(target, "loss")) {
    stop("method = '", method, "' only supports target = 'loss'; ",
         "boots$meta$target = '", target, "'.",
         call. = FALSE)
  }
  if (identical(method, "sa") && is.null(maturity)) {
    stop("method = 'sa' requires a resolved Maturity object.",
         call. = FALSE)
  }

  grp <- attr(triangle, "groups")
  if (is.null(grp)) grp <- character(0)

  one_fn <- switch(method,
    cl = function(tri_g, alt_g, gkey)
           .boot_refit_cl_one(tri_g, alt_g, alpha, grp_vals = gkey,
                               target = target, process_dist = process_dist),
    ed = function(tri_g, alt_g, gkey)
           .boot_refit_ed_one(tri_g, alt_g, alpha, grp_vals = gkey,
                               process_dist = process_dist),
    sa = function(tri_g, alt_g, gkey) {
           key_str <- if (is.null(gkey)) "__single__"
                      else do.call(paste, c(as.list(gkey), sep = "|"))
           .boot_refit_sa_one(tri_g, alt_g, alpha, grp_vals = gkey,
                               mat_change = mat_change_by_grp[[key_str]],
                               process_dist = process_dist)
         }
  )

  if (identical(method, "sa")) {
    mat_change_by_grp <- .boot_maturity_lookup(maturity, grp)
  }

  if (length(grp) > 0L) {
    grp_vals <- unique(triangle[, .SD, .SDcols = grp])
    out_list <- vector("list", nrow(grp_vals))
    for (gi in seq_len(nrow(grp_vals))) {
      gkey  <- grp_vals[gi]
      tri_g <- merge(triangle, gkey, by = grp, sort = FALSE)
      alt_g <- merge(boots$alt_triangles, gkey, by = grp, sort = FALSE)
      out_list[[gi]] <- one_fn(tri_g, alt_g, gkey)
    }
    data.table::rbindlist(out_list, use.names = TRUE)
  } else {
    one_fn(triangle, boots$alt_triangles, NULL)
  }
}


# Per-group CL refit. Returns long-format DT with (cohort, dev, rep,
# cell_mean, cell_proc_var) [+ optional group cols].
.boot_refit_cl_one <- function(triangle, alt_long, alpha, grp_vals,
                                target = "loss",
                                process_dist = "normal") {

  cohorts <- sort(unique(triangle$cohort))
  devs    <- sort(unique(triangle$dev))
  n_coh   <- length(cohorts)
  n_dev   <- length(devs)
  B       <- max(alt_long$rep)

  # Observed-region mask + original target matrix.
  obs_mask <- matrix(FALSE,    nrow = n_coh, ncol = n_dev,
                     dimnames = list(as.character(cohorts),
                                     as.character(devs)))
  mat_obs  <- matrix(NA_real_, nrow = n_coh, ncol = n_dev,
                     dimnames = dimnames(obs_mask))
  tri_target <- triangle[[target]]
  for (r in seq_len(nrow(triangle))) {
    ci <- match(as.character(triangle$cohort[r]), rownames(obs_mask))
    di <- match(as.character(triangle$dev[r]),    colnames(obs_mask))
    if (!is.na(ci) && !is.na(di) && is.finite(tri_target[r])) {
      obs_mask[ci, di] <- TRUE
      mat_obs[ci, di]  <- tri_target[r]
    }
  }

  last_obs_idx <- apply(obs_mask, 1L, function(row) {
    ok <- which(row)
    if (length(ok) == 0L) NA_integer_ else max(ok)
  })

  data.table::setorderv(alt_long, c("rep", "dev", "cohort"))
  arr_mean <- array(alt_long[[target]], dim = c(n_coh, n_dev, B),
                    dimnames = list(as.character(cohorts),
                                    as.character(devs), NULL))

  # ----- Vectorised refit (over B axis) ---------------------------------
  # sigma2_mat[k, b] = Mack sigma^2_k under replicate b. Computed from
  # cells whose (i, k-1) and (i, k) are *observed* (perturbed or
  # original). Vectorised across replicates via colSums on the slice.
  f_obs_mat  <- matrix(NA_real_, nrow = n_dev, ncol = B)
  sigma2_mat <- matrix(NA_real_, nrow = n_dev, ncol = B)
  for (k in seq(2L, n_dev)) {
    idx <- which(obs_mask[, k - 1L] & obs_mask[, k])
    if (length(idx) == 0L) next
    from_arr <- matrix(arr_mean[idx, k - 1L, ], nrow = length(idx))  # [n_idx, B]
    to_arr   <- matrix(arr_mean[idx, k,       ], nrow = length(idx))
    valid    <- from_arr > 0 & is.finite(from_arr) & is.finite(to_arr)
    from_v   <- from_arr * valid
    to_v     <- to_arr   * valid
    n_valid  <- colSums(valid)
    from_sum <- colSums(from_v)
    fhat_b <- to_v |> colSums() / from_sum
    fhat_b[!is.finite(fhat_b) | from_sum == 0] <- NA_real_
    f_obs_mat[k, ] <- fhat_b
    if (any(n_valid >= 2L)) {
      pred <- t(t(from_arr) * fhat_b)
      resid_sq <- (to_arr - pred)^2 / pmax(from_arr, 1e-12) * valid
      resid_sq[!is.finite(resid_sq)] <- 0
      s2_b <- colSums(resid_sq) / pmax(n_valid - 1L, 1)
      s2_b[n_valid < 2L] <- NA_real_
      sigma2_mat[k, ] <- s2_b
    }
  }
  # LOCF on sigma2_mat per replicate
  for (k in seq(2L, n_dev)) {
    bad <- !is.finite(sigma2_mat[k, ])
    if (any(bad)) sigma2_mat[k, bad] <- sigma2_mat[k - 1L, bad]
  }

  # f_proj_mat[k, b]: the f_star actually used by stage1 in projection
  # (drawn N for parametric; refit on alt observed for residual). Extract
  # from arr_mean ratios at any cohort whose dev k is projected.
  f_proj_mat <- matrix(NA_real_, nrow = n_dev, ncol = B)
  for (k in seq(2L, n_dev)) {
    proj_idx <- which(!obs_mask[, k] & !is.na(last_obs_idx))
    if (length(proj_idx) == 0L) next
    i_pick <- proj_idx[1L]
    from_b <- arr_mean[i_pick, k - 1L, ]
    to_b   <- arr_mean[i_pick, k,     ]
    ratio  <- to_b / from_b
    ratio[!is.finite(ratio)] <- NA_real_
    f_proj_mat[k, ] <- ratio
  }
  # Where f_proj is missing, fall back to f_obs (refit from observed).
  for (k in seq(2L, n_dev)) {
    bad <- !is.finite(f_proj_mat[k, ])
    if (any(bad)) f_proj_mat[k, bad] <- f_obs_mat[k, bad]
  }

  # ----- Vectorised forward simulation of cell_real ---------------------
  arr_real <- arr_mean  # parameter chain copy; projected cells overwritten
  # Anchor observed region to original mat_obs (constant across B)
  for (i in seq_len(n_coh)) {
    for (k in seq_len(n_dev)) {
      if (obs_mask[i, k]) arr_real[i, k, ] <- mat_obs[i, k]
    }
  }
  for (k in seq(2L, n_dev)) {
    proj_idx <- which(!obs_mask[, k] & !is.na(last_obs_idx))
    if (length(proj_idx) == 0L) next

    base_arr <- matrix(arr_real[proj_idx, k - 1L, ], nrow = length(proj_idx))
    f_b  <- f_proj_mat[k, ]
    s2_b <- sigma2_mat[k, ]
    f_b[!is.finite(f_b)]   <- 1
    s2_b[!is.finite(s2_b)] <- 0

    # mu[i, b] = f_b[b] * base_arr[i, b] (broadcast columns)
    mu_arr  <- t(t(base_arr) * f_b)
    var_arr <- t(t(base_arr) * s2_b)
    mu_arr[!is.finite(mu_arr)]   <- 0
    var_arr[!is.finite(var_arr) | var_arr < 0] <- 0

    cell_vec <- .boot_draw_noise(as.numeric(mu_arr),
                                  as.numeric(var_arr),
                                  dist = process_dist)
    cell_vec[is.finite(cell_vec) & cell_vec < 0] <- 0
    arr_real[proj_idx, k, ] <- matrix(cell_vec, nrow = length(proj_idx))
  }

  long <- data.table::data.table(
    cohort    = rep(rep(cohorts, times = n_dev), times = B),
    dev       = rep(rep(devs, each = n_coh),    times = B),
    rep       = rep(seq_len(B), each = n_coh * n_dev),
    cell_mean = as.numeric(arr_mean),
    cell_real = as.numeric(arr_real)
  )

  if (!is.null(grp_vals)) {
    for (col in names(grp_vals)) {
      long[, (col) := grp_vals[[col]]]
    }
    data.table::setcolorder(long, c(names(grp_vals), "cohort", "dev", "rep",
                                     "cell_mean", "cell_real"))
  }

  long[]
}


# Per-group ED refit. Mirrors .boot_refit_cl_one but uses additive
# recursion against the original (un-bootstrapped) premium column.
# Dispatched via `.boot_refit(method = "ed")`.
.boot_refit_ed_one <- function(triangle, alt_long, alpha, grp_vals,
                                process_dist = "normal") {

  cohorts <- sort(unique(triangle$cohort))
  devs    <- sort(unique(triangle$dev))
  n_coh   <- length(cohorts)
  n_dev   <- length(devs)
  B       <- max(alt_long$rep)

  obs_mask <- matrix(FALSE,    nrow = n_coh, ncol = n_dev,
                     dimnames = list(as.character(cohorts),
                                     as.character(devs)))
  mat_obs  <- matrix(NA_real_, nrow = n_coh, ncol = n_dev,
                     dimnames = dimnames(obs_mask))
  mat_prem <- matrix(NA_real_, nrow = n_coh, ncol = n_dev,
                     dimnames = dimnames(obs_mask))

  for (r in seq_len(nrow(triangle))) {
    ci <- match(as.character(triangle$cohort[r]), rownames(obs_mask))
    di <- match(as.character(triangle$dev[r]),    colnames(obs_mask))
    if (!is.na(ci) && !is.na(di)) {
      if (is.finite(triangle$loss[r])) {
        obs_mask[ci, di] <- TRUE
        mat_obs[ci, di]  <- triangle$loss[r]
      }
      mat_prem[ci, di] <- triangle$prem[r]
    }
  }
  for (i in seq_len(n_coh)) {
    last_p <- NA_real_
    for (j in seq_len(n_dev)) {
      if (is.finite(mat_prem[i, j])) {
        last_p <- mat_prem[i, j]
      } else if (is.finite(last_p)) {
        mat_prem[i, j] <- last_p
      }
    }
  }

  last_obs_idx <- apply(obs_mask, 1L, function(row) {
    ok <- which(row)
    if (length(ok) == 0L) NA_integer_ else max(ok)
  })

  data.table::setorderv(alt_long, c("rep", "dev", "cohort"))
  arr_alt <- array(alt_long$loss, dim = c(n_coh, n_dev, B),
                   dimnames = list(as.character(cohorts),
                                   as.character(devs), NULL))

  # ----- Vectorised refit (over B axis) ---------------------------------
  # g_obs_mat[k, b]: refit intensity from observed (alt-perturbed) cells.
  # sigma2_g_mat[k, b]: ED-style sigma^2_g per replicate, per link.
  g_obs_mat    <- matrix(NA_real_, nrow = n_dev, ncol = B)
  sigma2_g_mat <- matrix(NA_real_, nrow = n_dev, ncol = B)
  for (k in seq(2L, n_dev)) {
    idx <- which(obs_mask[, k - 1L] & obs_mask[, k] &
                 is.finite(mat_prem[, k - 1L]) & mat_prem[, k - 1L] > 0)
    if (length(idx) == 0L) next
    from_arr <- matrix(arr_alt[idx, k - 1L, ], nrow = length(idx))
    to_arr   <- matrix(arr_alt[idx, k,       ], nrow = length(idx))
    p_prev   <- mat_prem[idx, k - 1L]
    valid <- is.finite(from_arr) & is.finite(to_arr)
    d_arr <- (to_arr - from_arr) * valid
    p_v   <- p_prev * (valid[, 1L])  # premium is constant across B per cohort
    # Use per-(i, b) valid mask combined with per-cohort premium
    p_v_mat <- matrix(p_prev, nrow = length(idx), ncol = B) * valid
    n_valid <- colSums(valid)
    p_sum   <- colSums(p_v_mat)
    g_b <- colSums(d_arr) / p_sum
    g_b[!is.finite(g_b) | p_sum == 0] <- NA_real_
    g_obs_mat[k, ] <- g_b
    if (any(n_valid >= 2L)) {
      pred <- t(t(p_v_mat) * g_b)
      resid_sq <- (d_arr - pred)^2 / pmax(p_v_mat, 1e-12) * valid
      resid_sq[!is.finite(resid_sq)] <- 0
      s2_b <- colSums(resid_sq) / pmax(n_valid - 1L, 1)
      s2_b[n_valid < 2L] <- NA_real_
      sigma2_g_mat[k, ] <- s2_b
    }
  }
  for (k in seq(2L, n_dev)) {
    bad <- !is.finite(sigma2_g_mat[k, ])
    if (any(bad)) sigma2_g_mat[k, bad] <- sigma2_g_mat[k - 1L, bad]
  }

  # ----- Vectorised forward simulation: cell_mean and cell_real ---------
  arr_mean <- array(NA_real_, dim = c(n_coh, n_dev, B))
  arr_real <- array(NA_real_, dim = c(n_coh, n_dev, B))
  # Anchor observed region
  for (i in seq_len(n_coh)) {
    for (k in seq_len(n_dev)) {
      if (obs_mask[i, k]) {
        arr_mean[i, k, ] <- arr_alt[i, k, ]   # alt (perturbed for residual)
        arr_real[i, k, ] <- mat_obs[i, k]      # original observed for chain
      }
    }
  }

  for (k in seq(2L, n_dev)) {
    proj_idx <- which(!obs_mask[, k] & !is.na(last_obs_idx))
    if (length(proj_idx) == 0L) next

    g_b  <- g_obs_mat[k, ]
    s2_b <- sigma2_g_mat[k, ]
    g_b[!is.finite(g_b)]   <- 0
    s2_b[!is.finite(s2_b)] <- 0

    p_prev_vec <- mat_prem[proj_idx, k - 1L]   # [n_proj]
    p_prev_vec[!is.finite(p_prev_vec) | p_prev_vec <= 0] <- 0

    # mean chain: arr_mean[i, k, b] = arr_mean[i, k-1, b] + g_b[b] * p_prev[i]
    base_mean_arr <- matrix(arr_mean[proj_idx, k - 1L, ], nrow = length(proj_idx))
    mean_inc <- outer(p_prev_vec, g_b)   # [n_proj × B]
    arr_mean[proj_idx, k, ] <- base_mean_arr + mean_inc

    # real chain: arr_real[i, k, b] = arr_real[i, k-1, b] + g_b[b] * p_prev[i] + eps
    base_real_arr <- matrix(arr_real[proj_idx, k - 1L, ], nrow = length(proj_idx))
    mu_real <- base_real_arr + outer(p_prev_vec, g_b)
    var_real <- outer(p_prev_vec, s2_b)
    mu_real[!is.finite(mu_real)] <- 0
    var_real[!is.finite(var_real) | var_real < 0] <- 0

    cell_vec <- .boot_draw_noise(as.numeric(mu_real),
                                  as.numeric(var_real),
                                  dist = process_dist)
    cell_vec[is.finite(cell_vec) & cell_vec < 0] <- 0
    arr_real[proj_idx, k, ] <- matrix(cell_vec, nrow = length(proj_idx))
  }

  long <- data.table::data.table(
    cohort    = rep(rep(cohorts, times = n_dev), times = B),
    dev       = rep(rep(devs, each = n_coh),    times = B),
    rep       = rep(seq_len(B), each = n_coh * n_dev),
    cell_mean = as.numeric(arr_mean),
    cell_real = as.numeric(arr_real)
  )

  if (!is.null(grp_vals)) {
    for (col in names(grp_vals)) {
      long[, (col) := grp_vals[[col]]]
    }
    data.table::setcolorder(long, c(names(grp_vals), "cohort", "dev", "rep",
                                     "cell_mean", "cell_real"))
  }

  long[]
}


# Build a per-group lookup `key -> mat_change` from a resolved Maturity
# object. Single-group case uses the sentinel key `"__single__"`.
# Used by `.boot_refit(method = "sa")`.
.boot_maturity_lookup <- function(maturity, grp) {
  mat_dt <- data.table::as.data.table(maturity)
  if (length(grp) == 0L) {
    return(list(`__single__` = mat_dt$change[1L]))
  }
  out <- list()
  for (i in seq_len(nrow(mat_dt))) {
    key <- do.call(paste, c(as.list(mat_dt[i, .SD, .SDcols = grp]),
                            sep = "|"))
    out[[key]] <- mat_dt$change[i]
  }
  out
}


# Per-group SA refit. ED for dev < mat_change, CL for dev >= mat_change.
.boot_refit_sa_one <- function(triangle, alt_long, alpha, grp_vals,
                                mat_change,
                                process_dist = "normal") {

  cohorts <- sort(unique(triangle$cohort))
  devs    <- sort(unique(triangle$dev))
  n_coh   <- length(cohorts)
  n_dev   <- length(devs)
  B       <- max(alt_long$rep)

  if (!is.finite(mat_change)) mat_change <- Inf

  obs_mask <- matrix(FALSE,    nrow = n_coh, ncol = n_dev,
                     dimnames = list(as.character(cohorts),
                                     as.character(devs)))
  mat_obs  <- matrix(NA_real_, nrow = n_coh, ncol = n_dev,
                     dimnames = dimnames(obs_mask))
  mat_prem <- matrix(NA_real_, nrow = n_coh, ncol = n_dev,
                     dimnames = dimnames(obs_mask))

  for (r in seq_len(nrow(triangle))) {
    ci <- match(as.character(triangle$cohort[r]), rownames(obs_mask))
    di <- match(as.character(triangle$dev[r]),    colnames(obs_mask))
    if (!is.na(ci) && !is.na(di)) {
      if (is.finite(triangle$loss[r])) {
        obs_mask[ci, di] <- TRUE
        mat_obs[ci, di]  <- triangle$loss[r]
      }
      mat_prem[ci, di] <- triangle$prem[r]
    }
  }
  for (i in seq_len(n_coh)) {
    last_p <- NA_real_
    for (j in seq_len(n_dev)) {
      if (is.finite(mat_prem[i, j])) {
        last_p <- mat_prem[i, j]
      } else if (is.finite(last_p)) {
        mat_prem[i, j] <- last_p
      }
    }
  }

  last_obs_idx <- apply(obs_mask, 1L, function(row) {
    ok <- which(row)
    if (length(ok) == 0L) NA_integer_ else max(ok)
  })

  data.table::setorderv(alt_long, c("rep", "dev", "cohort"))
  arr_alt <- array(alt_long$loss, dim = c(n_coh, n_dev, B),
                   dimnames = list(as.character(cohorts),
                                   as.character(devs), NULL))

  arr_mean <- array(NA_real_, dim = c(n_coh, n_dev, B))
  arr_real <- array(NA_real_, dim = c(n_coh, n_dev, B))

  # Anchor observed region (vectorised across B)
  for (i in seq_len(n_coh)) {
    for (j in seq_len(n_dev)) {
      if (obs_mask[i, j]) {
        arr_mean[i, j, ] <- arr_alt[i, j, ]
        arr_real[i, j, ] <- mat_obs[i, j]
      }
    }
  }

  # ----- Vectorised refit of f_star (CL) and g_star (ED) per link ------
  f_star_mat <- matrix(NA_real_, nrow = n_dev, ncol = B)
  s2_f_mat   <- matrix(NA_real_, nrow = n_dev, ncol = B)
  g_star_mat <- matrix(NA_real_, nrow = n_dev, ncol = B)
  s2_g_mat   <- matrix(NA_real_, nrow = n_dev, ncol = B)
  for (k in seq(2L, n_dev)) {
    idx <- which(obs_mask[, k - 1L] & obs_mask[, k])
    if (length(idx) == 0L) next
    from_arr <- matrix(arr_alt[idx, k - 1L, ], nrow = length(idx))
    to_arr   <- matrix(arr_alt[idx, k,       ], nrow = length(idx))
    valid_cl <- from_arr > 0 & is.finite(from_arr) & is.finite(to_arr)
    n_cl <- colSums(valid_cl)
    from_v   <- from_arr * valid_cl
    to_v     <- to_arr   * valid_cl
    from_sum <- colSums(from_v)
    fhat_b <- colSums(to_v) / from_sum
    fhat_b[!is.finite(fhat_b) | from_sum == 0] <- NA_real_
    f_star_mat[k, ] <- fhat_b
    if (any(n_cl >= 2L)) {
      pred <- t(t(from_arr) * fhat_b)
      rsq <- (to_arr - pred)^2 / pmax(from_arr, 1e-12) * valid_cl
      rsq[!is.finite(rsq)] <- 0
      s2_b <- colSums(rsq) / pmax(n_cl - 1L, 1)
      s2_b[n_cl < 2L] <- NA_real_
      s2_f_mat[k, ] <- s2_b
    }

    p_prev <- mat_prem[idx, k - 1L]
    valid_ed <- valid_cl & matrix(is.finite(p_prev) & p_prev > 0,
                                  nrow = length(idx), ncol = B)
    if (any(valid_ed)) {
      d_arr <- (to_arr - from_arr) * valid_ed
      p_mat <- matrix(p_prev, nrow = length(idx), ncol = B) * valid_ed
      n_ed  <- colSums(valid_ed)
      p_sum <- colSums(p_mat)
      g_b <- colSums(d_arr) / p_sum
      g_b[!is.finite(g_b) | p_sum == 0] <- NA_real_
      g_star_mat[k, ] <- g_b
      if (any(n_ed >= 2L)) {
        pred_g <- t(t(p_mat) * g_b)
        rsq_g <- (d_arr - pred_g)^2 / pmax(p_mat, 1e-12) * valid_ed
        rsq_g[!is.finite(rsq_g)] <- 0
        s2g_b <- colSums(rsq_g) / pmax(n_ed - 1L, 1)
        s2g_b[n_ed < 2L] <- NA_real_
        s2_g_mat[k, ] <- s2g_b
      }
    }
  }
  for (k in seq(2L, n_dev)) {
    bad <- !is.finite(s2_f_mat[k, ])
    if (any(bad)) s2_f_mat[k, bad] <- s2_f_mat[k - 1L, bad]
    bad <- !is.finite(s2_g_mat[k, ])
    if (any(bad)) s2_g_mat[k, bad] <- s2_g_mat[k - 1L, bad]
  }

  # ----- Vectorised forward simulation, per dev step ------------------
  for (k in seq(2L, n_dev)) {
    proj_idx <- which(!obs_mask[, k] & !is.na(last_obs_idx))
    if (length(proj_idx) == 0L) next

    use_cl <- (devs[k] >= mat_change)

    if (use_cl) {
      f_b  <- f_star_mat[k, ]
      s2_b <- s2_f_mat[k, ]
      f_b[!is.finite(f_b)]   <- 1
      s2_b[!is.finite(s2_b)] <- 0

      base_mean <- matrix(arr_mean[proj_idx, k - 1L, ], nrow = length(proj_idx))
      arr_mean[proj_idx, k, ] <- t(t(base_mean) * f_b)

      base_real <- matrix(arr_real[proj_idx, k - 1L, ], nrow = length(proj_idx))
      mu_r  <- t(t(base_real) * f_b)
      var_r <- t(t(base_real) * s2_b)
      mu_r[!is.finite(mu_r)] <- 0
      var_r[!is.finite(var_r) | var_r < 0] <- 0
    } else {
      g_b  <- g_star_mat[k, ]
      s2_b <- s2_g_mat[k, ]
      g_b[!is.finite(g_b)]   <- 0
      s2_b[!is.finite(s2_b)] <- 0
      p_prev_vec <- mat_prem[proj_idx, k - 1L]
      p_prev_vec[!is.finite(p_prev_vec) | p_prev_vec <= 0] <- 0

      base_mean <- matrix(arr_mean[proj_idx, k - 1L, ], nrow = length(proj_idx))
      arr_mean[proj_idx, k, ] <- base_mean + outer(p_prev_vec, g_b)

      base_real <- matrix(arr_real[proj_idx, k - 1L, ], nrow = length(proj_idx))
      mu_r  <- base_real + outer(p_prev_vec, g_b)
      var_r <- outer(p_prev_vec, s2_b)
      mu_r[!is.finite(mu_r)] <- 0
      var_r[!is.finite(var_r) | var_r < 0] <- 0
    }

    cell_vec <- .boot_draw_noise(as.numeric(mu_r),
                                  as.numeric(var_r),
                                  dist = process_dist)
    cell_vec[is.finite(cell_vec) & cell_vec < 0] <- 0
    arr_real[proj_idx, k, ] <- matrix(cell_vec, nrow = length(proj_idx))
  }

  long <- data.table::data.table(
    cohort    = rep(rep(cohorts, times = n_dev), times = B),
    dev       = rep(rep(devs, each = n_coh),    times = B),
    rep       = rep(seq_len(B), each = n_coh * n_dev),
    cell_mean = as.numeric(arr_mean),
    cell_real = as.numeric(arr_real)
  )

  if (!is.null(grp_vals)) {
    for (col in names(grp_vals)) {
      long[, (col) := grp_vals[[col]]]
    }
    data.table::setcolorder(long, c(names(grp_vals), "cohort", "dev", "rep",
                                     "cell_mean", "cell_real"))
  }

  long[]
}



#' Summarize per-cell bootstrap SE decomposition (method-independent)
#'
#' Aggregates over the `rep` dimension to produce per-cell SE columns
#' matching the existing `target_proc_se` / `target_param_se` /
#' `target_total_se` / `target_total_cv` convention used by `fit_cl()` /
#' `fit_loss()` / `fit_premium()` / `fit_lr()`.
#'
#' Decomposition:
#' \itemize{
#'   \item `param_se` = `sd(cell_mean)` across replicates (Stage 1 spread)
#'   \item `total_se` = `sd(cell_real)` across replicates (Stage 1 + 2)
#'   \item `proc_se`  = `sqrt(max(total_se^2 - param_se^2, 0))`
#' }
#'
#' @param refit_dt A `data.table` with `cell_mean` and `cell_real` columns
#'   (the latter produced by `.boot_add_process_noise()`).
#' @param grp Character vector of group column names (may be `character(0)`).
#'
#' @return A `data.table` keyed by `[grp..], cohort, dev` with columns
#'   `target_proj` (point estimate), `target_proc_se`, `target_param_se`,
#'   `target_total_se`, `target_total_cv`, plus quantile-based 95% CI
#'   columns `target_ci_lo` / `target_ci_hi`.
#'
#' @keywords internal
.boot_summarize_se <- function(refit_dt, grp = character(0)) {
  cell_mean <- cell_real <- NULL  # NSE

  by_cols <- c(grp, "cohort", "dev")

  refit_dt[, {
    cm <- cell_mean
    cr <- cell_real
    cm_ok <- cm[is.finite(cm)]
    cr_ok <- cr[is.finite(cr)]

    proj <- if (length(cm_ok) > 0L) mean(cm_ok) else NA_real_
    param_se <- if (length(cm_ok) >= 2L) stats::sd(cm_ok) else 0
    total_se <- if (length(cr_ok) >= 2L) stats::sd(cr_ok) else 0
    proc_se  <- sqrt(max(total_se^2 - param_se^2, 0))
    total_cv <- if (is.finite(proj) && proj != 0) total_se / proj
                else NA_real_

    qs <- if (length(cr_ok) >= 2L) {
      stats::quantile(cr_ok, probs = c(0.025, 0.975),
                      na.rm = TRUE, names = FALSE)
    } else c(proj, proj)

    list(
      target_proj     = proj,
      target_proc_se  = proc_se,
      target_param_se = param_se,
      target_total_se = total_se,
      target_total_cv = total_cv,
      target_ci_lo    = qs[1L],
      target_ci_hi    = qs[2L]
    )
  }, by = by_cols]
}

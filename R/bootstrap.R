# Bootstrap helpers ---------------------------------------------------------
#
# Triangle-level bootstrap worker. Layer 1 (`bootstrap.Triangle()`)
# performs the data perturbation (Stage 1 pseudo triangles) once; Layer 2
# (refit consumers per method) reuses those pseudo triangles B times. The
# B-dependent inner loop of `residual = "cell"` Stage 1 lives in C
# (`src/bootstrap.c`); R drives the surrounding orchestration.
#
# References:
#   Mack (1993, ASTIN Bull 23/2)        -- sigma_k^2 / f_k variance form.
#   Mack (1999, ASTIN Bull 29/2)        -- sigma^2 extrapolation (tail).
#   England & Verrall (1999, IME 25/3)  -- bootstrap framing.
#   Barnett & Zehnwirth (2007, IW TR)   -- residual diagnostic critique.


# Section 1 -- Argument validation ============================================


#' Validate the bootstrap argument combination
#'
#' Internal helper called by `bootstrap.Triangle()` after `match.arg()`.
#' Enforces the type/residual/process/method/pooling/tail combination
#' matrix and warns when an argument is silently ignored.
#'
#' @param type,residual,process,method,pooling,tail Resolved (post-match.arg) values.
#' @param min_pool,hat_adj,demean,maturity Scalar values to validate.
#' @param residual_set,process_set,pooling_set,tail_set,hat_adj_set,demean_set,min_pool_set
#'   Logicals indicating whether the user explicitly passed each argument
#'   (computed via `match.call()` in the caller).
#'
#' @return `invisible(TRUE)` after raising any errors / warnings.
#'
#' @keywords internal
.validate_bootstrap_args <- function(type, residual, process, method, pooling,
                                     tail, min_pool, hat_adj, demean, maturity,
                                     residual_set, process_set,
                                     pooling_set, tail_set, hat_adj_set,
                                     demean_set, min_pool_set) {

  # `min_pool` must be a single positive integer regardless of type/pooling.
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
    if (pooling_set)
      warning("type = 'parametric' has no residual pool; ",
              "'pooling' argument is ignored.",
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
    if (demean_set)
      warning("'demean' is only defined for residual = 'cell'; ignored.",
              call. = FALSE)
  } else {
    # type == "nonparametric"
    if (identical(residual, "link") && hat_adj_set && isTRUE(hat_adj))
      warning("hat_adj is currently only implemented for residual = ",
              "'cell'. Pinheiro 2003 defines it for link residuals but ",
              "implementation is deferred to a future release. Ignored.",
              call. = FALSE)
    if (identical(residual, "link") && demean_set)
      warning("'demean' is only defined for residual = 'cell'; ignored.",
              call. = FALSE)
    if (identical(residual, "cell") && identical(process, "normal"))
      stop("residual = 'cell' (ODP path, England-Verrall 1999/2002) ",
           "requires a positivity-preserving process distribution. ",
           "Use process = 'gamma' (default) or 'od_pois'; ",
           "'normal' violates the ODP positivity assumption.",
           call. = FALSE)
    if (identical(process, "lognormal"))
      stop("process = 'lognormal' not yet implemented (Phase 5b.3). ",
           "Use 'gamma', 'od_pois', or 'normal'.",
           call. = FALSE)
    if (!identical(pooling, "tail_pooled")) {
      if (tail_set)
        warning("'tail' applies only to pooling = 'tail_pooled'; ignored.",
                call. = FALSE)
      if (min_pool_set)
        warning("'min_pool' applies only to pooling = 'tail_pooled' ",
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
#' that downstream fit functions (`fit_cl` / `fit_ed` / `fit_ratio`) consume to
#' recover parameter and process risk decomposition.
#'
#' This entry point sits at the Triangle level -- it knows nothing about CL,
#' ED, or SA. Each fit method later refits its own model on every alt
#' triangle and adds Stage 2 process noise using its own variance recipe.
#' The same bootstrap object is therefore reusable across all fit methods.
#'
#' Bootstrap proceeds in two conceptual stages (see `dev/BOOTSTRAP.md`):
#'
#' 1. **Stage 1 -- parameter uncertainty**: residual resample (or parametric
#'    Normal draw) propagated through the cumulative loss chain, refitted
#'    factors per replicate. This produces `B` alternative *mean*
#'    predictions per cell.
#' 2. **Stage 2 -- process uncertainty**: added *inside the fit function*
#'    on demand, using the method-specific `sigma^2`. The `process` argument
#'    here is stored as metadata so the consuming fit method knows which
#'    distribution to use.
#'
#' @param x A `Triangle` object.
#' @param type One of `"nonparametric"` or `"parametric"`. `"parametric"`
#'   draws new link factors from `N(f_hat, sqrt(Var(f_hat)))` (Mack 1993
#'   closed-form); `"nonparametric"` resamples standardized residuals and
#'   reconstructs the pseudo triangle (England-Verrall / Pinheiro).
#' @param residual Residual scope for `type = "nonparametric"`. One of
#'   `"cell"` (default -- England-Verrall 1999/2002, Pearson residuals on
#'   incremental cells; ODP GLM equivalent via Renshaw-Verrall 1998) or
#'   `"link"` (Mack 1993 / Pinheiro 2003, Pearson residuals on link
#'   factors).
#' @param hat_adj Logical. Hat-matrix leverage adjustment
#'   (`r_h = r / sqrt(1 - h_ii)`) for the cell residual path. Default
#'   `TRUE` (England-Verrall 2002 Addendum); set `FALSE` to use the
#'   simpler degrees-of-freedom factor `sqrt(n / (n - p))`
#'   (England-Verrall 1999). Only defined for `residual = "cell"`;
#'   warned-ignored otherwise. Note that `hat_adj` drops corner cells
#'   where `h_ii = 1` (always `(I, 1)` and `(1, J)` of the upper
#'   triangle); on small triangles this can be a meaningful pool
#'   reduction -- set `FALSE` if that matters.
#' @param demean Logical. Subtract the per-group residual mean from
#'   each residual in the cell-residual pool before resampling
#'   (`de-` + `mean`: remove the mean, leaving a zero-mean pool).
#'   Default `TRUE`. Shapland (2010, Sec.4.2) discusses this as one option
#'   among others -- see the *Bootstrap SE decomposition* vignette for
#'   the trade-off. Only defined for `residual = "cell"`; warned-ignored
#'   otherwise.
#' @param process One of `"gamma"`, `"od_pois"`, `"normal"`, `"lognormal"`.
#'   Stored as metadata; downstream fit functions read this to choose
#'   the Stage 2 noise distribution. `"gamma"` is the default for
#'   non-negative right-skewed loss data. `"lognormal"` is reserved for
#'   Phase 5b.3 and currently errors.
#' @param method Fit-model paradigm whose lower-triangle forward projection
#'   the bootstrap should produce. One of `"sa"` (stage-adaptive -- ED before
#'   maturity, CL after; default), `"cl"` (chain-ladder multiplicative
#'   recursion across all dev), `"ed"` (exposure-driven additive recursion
#'   across all dev). Mirrors the `loss_method` argument of `fit_ratio()`; the
#'   resulting `BootstrapTriangle` is consumed by the corresponding
#'   `fit_*(..., bootstrap = bt)` branch.
#' @param pooling Residual-pool grouping. One of `"pooled"`, `"separated"`,
#'   `"tail_pooled"`. `"pooled"` shares residuals across all links;
#'   `"separated"` keeps each development link independent (Mack-faithful);
#'   `"tail_pooled"` uses per-link pools before a cut and a single pooled
#'   bucket after.
#' @param tail Tail-cut rule for `pooling = "tail_pooled"`. One of `"auto"`
#'   (cut at the smallest `ata_to` whose residual count drops below
#'   `min_pool`) or `"maturity"` (cut at the resolved `Maturity` change
#'   point).
#' @param min_pool Minimum residual count per per-link pool under
#'   `pooling = "tail_pooled" && tail = "auto"`. Default `5`.
#' @param maturity Required only when `pooling = "tail_pooled" &&
#'   tail = "maturity"`. Four-type dispatch: `NULL`, a `Maturity` object,
#'   the string `"auto"`, or a function `function(tri) -> Maturity`.
#' @param B Number of bootstrap replicates. Default `499` -- the Davison &
#'   Hinkley (1997) convention picks `B` so that `(B + 1) p` is an integer
#'   for the target quantile `p`. With `B = 499` (so `B + 1 = 500`), every
#'   one-sided VaR commonly reported in reserving -- `p = 0.50, 0.75, 0.90,
#'   0.95, 0.99` -- lands on an exact integer ordinal index, so the
#'   empirical CI is exact without interpolation. For Solvency II /
#'   K-ICS 99.5% TVaR reporting pass `B = 1999`; for the gold-standard
#'   published convention pass `B = 999`.
#' @param seed Optional integer seed for reproducibility.
#' @param alpha Variance exponent in Mack's `Var(C_{k+1} | C_k) = sigma_k^2
#'   C_k^alpha`. Default `1` (volume-weighted).
#' @param quantile_ci Logical. Opt-in flag for the empirical percentile
#'   CI columns (`ci_lo` / `ci_hi` = 2.5% / 97.5% quantiles of
#'   `loss_sampled` across replicates, Davison & Hinkley (1997) type=1
#'   ordinal) in the `$summary` slot. Default `FALSE`. The Normal-
#'   approximation CI (`mean_proj +/- 1.96 * total_se`) derivable from
#'   `total_se` is usually enough for interactive use; set `TRUE` for
#'   Solvency II / K-ICS VaR reporting where you need the empirical
#'   tail. The C kernel computes both CI bounds in the same pass as
#'   the SE decomposition (per-cell qsort dominated by Stage 1 work),
#'   so the marginal cost over `FALSE` is small.
#' @param keep_pseudo Logical. Whether to materialise the per-replicate
#'   long-format `pseudo_triangles` slot. Default `FALSE` (changed from
#'   `TRUE` in v0.x for performance). `TRUE` builds the long-format
#'   data.table for diagnostic inspection (e.g. raw replicate
#'   trajectories, custom quantile work). On a typical 4-group monthly
#'   triangle at `B = 999` the reshape costs ~250-300 ms and ~200 MB on
#'   top of `$summary`; users who only consume `$summary` (the common
#'   case) should leave this `FALSE`. `fit_ratio()` / `fit_loss()` /
#'   `fit_exposure()` always pass `FALSE` internally because they only
#'   read `$summary`. Set `TRUE` explicitly if you want to inspect
#'   `$pseudo_triangles` directly.
#' @param ... Reserved for future use.
#'
#' @return An object of class `BootstrapTriangle` (a list) with elements:
#' \describe{
#'   \item{`pseudo_triangles`}{Long-format `data.table` with columns
#'     `[groups]`, `cohort`, `dev`, `rep`, `loss`. `rep` ranges over `1..B`.
#'     Observed-region cells contain residual-perturbed (or original for
#'     `"parametric"`) cumulative loss; the missing region contains
#'     Stage 1 forward projection means.}
#'   \item{`residual_pool`}{`data.table` of the standardized residuals used,
#'     with the `pool_id` column identifying which pool each residual
#'     belongs to (depends on `method`/`tail`). Schema differs by
#'     residual mode: `[groups, cohort, ata_from, ata_to, residual,
#'     pool_id]` for `residual = "link"`, and `[groups, cohort, dev,
#'     residual, pool_id]` for `residual = "cell"`.}
#'   \item{`f_anchor`}{Per-link Mack factor estimates `f_hat` with
#'     `n_cohorts`.}
#'   \item{`sigma2_anchor`}{Per-link Mack `sigma^2` and `Var(f_hat)`.}
#'   \item{`meta`}{`list(type, residual, hat_adj, process, method, pooling,
#'     tail, min_pool, B, seed, alpha, target, groups, maturity)`.}
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
#'   loss     = "incr_loss",
#'   exposure = "incr_exposure"
#' )
#'
#' # Cell-residual bootstrap (default)
#' boots <- bootstrap(tri, type = "nonparametric", residual = "cell",
#'                    hat_adj = TRUE, process = "gamma",
#'                    B = 500, seed = 1)
#' print(boots)
#'
#' # Link-residual bootstrap (Mack 1993 / Pinheiro 2003 path)
#' boots_link <- bootstrap(tri, type = "nonparametric", residual = "link",
#'                         pooling = "separated", process = "gamma",
#'                         B = 500, seed = 1)
#' }
#'

# Section 2 -- Public entry point (S3 generic + Triangle method) ==============

#' @export
bootstrap <- function(x, ...) {
  UseMethod("bootstrap")
}


#' @rdname bootstrap
#' @param target Cumulative metric to perturb. One of `"loss"` (default) or
#'   `"exposure"`. The value column in `$pseudo_triangles` is named after this
#'   target so downstream refit helpers know which column to read.
#' @export
bootstrap.Triangle <- function(x,
                                type        = c("nonparametric", "parametric"),
                                residual    = c("cell", "link"),
                                hat_adj     = TRUE,
                                demean      = TRUE,
                                process     = c("gamma", "od_pois", "normal",
                                                "lognormal"),
                                method      = c("sa", "cl", "ed"),
                                pooling     = c("pooled", "separated",
                                                "tail_pooled"),
                                tail        = c("auto", "maturity"),
                                min_pool    = 5L,
                                maturity    = NULL,
                                target      = c("loss", "exposure"),
                                B           = 499L,
                                seed        = NULL,
                                alpha       = 1,
                                quantile_ci = FALSE,
                                keep_pseudo = FALSE,
                                ...) {

  .assert_class(x, "Triangle")

  # Detect explicitly-passed args (before match.arg() overwrites) so the
  # validator can issue "ignored" warnings only when the user actually
  # supplied a value.
  mc <- match.call()
  residual_set <- "residual" %in% names(mc)
  process_set  <- "process"  %in% names(mc)
  pooling_set  <- "pooling"  %in% names(mc)
  tail_set     <- "tail"     %in% names(mc)
  hat_adj_set  <- "hat_adj"  %in% names(mc)
  demean_set   <- "demean"   %in% names(mc)
  min_pool_set <- "min_pool" %in% names(mc)

  type     <- match.arg(type)
  residual <- match.arg(residual)
  process  <- match.arg(process)
  method   <- match.arg(method)
  pooling  <- match.arg(pooling)
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
    method = method, pooling = pooling, tail = tail,
    min_pool = min_pool, hat_adj = hat_adj, demean = demean,
    maturity = maturity,
    residual_set = residual_set, process_set = process_set,
    pooling_set = pooling_set, tail_set = tail_set,
    hat_adj_set = hat_adj_set, demean_set = demean_set,
    min_pool_set = min_pool_set
  )

  min_pool <- as.integer(min_pool)

  # Parametric path has only one supported process (Mack 1993 closed-form
  # uses Normal). When the user didn't explicitly request a different
  # process, silently coerce to "normal" so meta$process truthfully
  # records what Stage 1 simulated under. (If the user *did* set process
  # to something non-normal, the validator already errored above.)
  if (identical(type, "parametric")) process <- "normal"

  # Resolve maturity when tail_pooled + maturity. Note: for tail = "auto"
  # we don't need a Maturity object -- the cut is derived from residual
  # counts vs `min_pool`.
  if (identical(pooling, "tail_pooled") && identical(tail, "maturity")) {
    maturity <- .resolve_maturity(maturity, x)
    if (is.null(maturity))
      stop("`pooling = 'tail_pooled'` with `tail = 'maturity'` requires a ",
           "maturity. Pass `maturity = 'auto'` for automatic detection, ",
           "or supply a Maturity object.", call. = FALSE)
  } else {
    maturity <- NULL
  }

  grp <- attr(x, "groups")
  if (is.null(grp)) grp <- character(0)

  is_residual_mode <- identical(type, "nonparametric")

  if (is_residual_mode) {
    # 1) Build Link on the chosen target (always -- anchor + cell-mode fitted
    #    means both depend on volume-weighted f_hat per link)
    link <- as_link(x, loss = target, drop_invalid = TRUE)

    # 2) Compute Mack anchor per (group, ata_to)
    anchor <- .boot_anchor(link, grp = grp, alpha = alpha)

    if (identical(residual, "link")) {
      # Pinheiro 2003: standardized link residuals on each Link row
      link <- .boot_attach_residuals(link, anchor = anchor, grp = grp)
      pool <- .boot_build_pool(link, anchor = anchor, grp = grp,
                                pooling = pooling, tail = tail,
                                min_pool = min_pool, maturity = maturity)
    } else {
      # E-V 1999/2002: Pearson residuals on incremental cells, optionally
      # leverage-corrected (hat_adj). Pool keyed by (cohort, dev).
      cell_resid <- .boot_cell_residuals(x, anchor = anchor, grp = grp,
                                          target = target, hat_adj = hat_adj)
      # Extract per-group phi (ODP single scale) BEFORE pool transforms
      # the table -- the pool builder isn't required to preserve attrs.
      phi_dt <- attr(cell_resid, "phi_dt")
      pool <- .boot_build_pool_cell(cell_resid, grp = grp,
                                     pooling = pooling, tail = tail,
                                     min_pool = min_pool, maturity = maturity,
                                     demean = demean)
    }
  } else {
    # parametric path: closed-form simulation, no residual pool needed.
    # We still compute the anchor (f_hat, sigma2, f_var) -- those drive
    # the N(f_hat, sqrt(Var(f_hat))) draws inside .boot_stage1_one.
    link   <- as_link(x, loss = target, drop_invalid = TRUE)
    anchor <- .boot_anchor(link, grp = grp, alpha = alpha)
    pool   <- .boot_empty_pool(grp)
  }

  # phi_dt: cell mode only; otherwise NULL (Mack paradigm uses sigma2).
  if (!(is_residual_mode && identical(residual, "cell"))) {
    phi_dt <- NULL
  }

  # 5) Stage 1 + 2 -- B pseudo triangles (raw 3D arrays only) ----------------
  # `.boot_stage1()` returns the raw C-side 3D arrays + per-group
  # metadata. The long-format pseudo_triangles DT (~5M rows on a typical
  # 4-group monthly triangle) is built lazily by .boot_build_pseudo_long
  # only when the user reads `$pseudo_triangles`.
  stage1_out <- .boot_stage1(
    triangle = x, link = link, anchor = anchor, pool = pool,
    phi_dt = phi_dt,
    grp = grp, is_residual_mode = is_residual_mode, residual = residual,
    process = process, B = B, alpha = alpha, target = target
  )

  summary_dt <- .boot_summary_from_arrays(stage1_out, grp = grp,
                                          target = target,
                                          quantile_ci = quantile_ci)

  # 6) Assemble -------------------------------------------------------------
  # When keep_pseudo = TRUE (opt-in; default is FALSE), eagerly build the
  # long-format pseudo_triangles DT for user inspection. This pays the
  # ~250-300 ms reshape cost up front so subsequent reads are O(1) and
  # the object has no hidden mutation behaviour.
  pseudo_triangles <- if (isTRUE(keep_pseudo))
    .boot_build_pseudo_long(stage1_out, target = target, grp = grp)
  else NULL

  structure(
    list(
      pseudo_triangles = pseudo_triangles,
      summary       = summary_dt,
      residual_pool = pool,
      f_anchor      = anchor[, .SD,
                              .SDcols = c(grp, "ata_from", "ata_to",
                                          "f_hat", "n_cohorts")],
      sigma2_anchor = anchor[, .SD,
                              .SDcols = c(grp, "ata_from", "ata_to",
                                          "sigma2", "f_var")],
      meta = list(
        type        = type,
        residual    = residual,
        hat_adj     = hat_adj,
        demean      = demean,
        process     = process,
        method      = method,
        pooling     = pooling,
        quantile_ci = quantile_ci,
        tail        = if (identical(pooling, "tail_pooled")) tail
                      else NA_character_,
        min_pool    = if (identical(pooling, "tail_pooled") &&
                          identical(tail, "auto")) min_pool
                      else NA_integer_,
        B           = B,
        seed        = seed,
        alpha       = alpha,
        target      = target,
        groups      = grp,
        maturity    = maturity,
        phi_dt      = phi_dt
      )
    ),
    class = c("BootstrapTriangle", "list")
  )
}



# Section 3 -- Anchor + residual pool builders ================================
#   .boot_empty_pool      (parametric path placeholder)
#   .boot_anchor          (per-link f_hat, sigma2, f_var)
#   .boot_fill_sigma2     (Mack tail-rule fill)
#   .boot_attach_residuals (link mode: per-link Mack residuals)
#   .boot_build_pool      (link mode: per-link pool assembly)
#   .boot_fitted_grid     (cell mode: chain-anchored fitted incrementals)
#   .boot_hat_diag        (cell mode: GLM hat matrix leverage)
#   .boot_cell_residuals(_one)  (cell mode: Pearson residuals per cell)
#   .boot_build_pool_cell (cell mode: pool assembly with zero-drop + centering)

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
# Volume-weighted f_hat = sum(loss_to) / sum(loss_from).
# Mack sigma^2_k     = (1/(n-1)) * sum(C_{k-1} * (f_ik - f_hat)^2)
#                     = (1/(n-1)) * sum((loss_to - f_hat*loss_from)^2 / loss_from)
# Var(f_hat)         = sigma^2_k / sum(loss_from)
#
# When n=1 for the last link, use Mack tail rule:
#   sigma^2_K = min(sigma^2_{K-1}^2 / sigma^2_{K-2}, sigma^2_{K-2}, sigma^2_{K-1})
# Simpler fallback when K < 3: sigma^2_K = sigma^2_{K-1}.
.boot_anchor <- function(link, grp, alpha = 1) {
  # data.table NSE
  loss_from <- loss_to <- f_hat <- sigma2 <- f_var <- sum_from <- NULL

  by_cols <- c(grp, "ata_from", "ata_to")

  anchor <- link[is.finite(loss_from) & is.finite(loss_to) & loss_from > 0,
                 {
                   f       <- sum(loss_to) / sum(loss_from)
                   n       <- .N
                   if (n >= 2L) {
                     resid_sq <- (loss_to - f * loss_from)^2 / loss_from
                     s2 <- sum(resid_sq) / (n - 1L)
                   } else {
                     s2 <- NA_real_
                   }
                   list(
                     f_hat     = f,
                     sigma2    = s2,
                     n_cohorts = n,
                     sum_from  = sum(loss_from)
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
# r_ik = (loss_to - f_hat_k * loss_from) / sqrt(sigma2_k * loss_from)
#
# Returns the Link with two new columns: `residual` and `pool_id`. The
# `pool_id` is filled later by .boot_build_pool() (mode-dependent).
.boot_attach_residuals <- function(link, anchor, grp) {
  # NSE
  loss_from <- loss_to <- f_hat <- sigma2 <- residual <- NULL

  by_cols <- c(grp, "ata_from", "ata_to")

  dt <- .copy_dt(link)
  dt <- merge(dt, anchor[, .SD,
                          .SDcols = c(by_cols, "f_hat", "sigma2")],
              by = by_cols, all.x = TRUE, sort = FALSE)

  dt[, residual := data.table::fifelse(
    is.finite(loss_from) & loss_from > 0 &
      is.finite(sigma2) & sigma2 > 0 &
      is.finite(loss_to) & is.finite(f_hat),
    (loss_to - f_hat * loss_from) / sqrt(sigma2 * loss_from),
    NA_real_
  )]

  dt[, c("f_hat", "sigma2") := NULL]
  dt
}


# Internal: build residual pool with `pool_id` per (pooling, tail) --------
.boot_build_pool <- function(link, anchor, grp, pooling, tail, min_pool,
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

  if (identical(pooling, "separated")) {
    dt[, ("pool_id") := paste(grp_key, as.character(ata_to), sep = "|")]
  } else if (identical(pooling, "pooled")) {
    dt[, ("pool_id") := data.table::fifelse(grp_key == "", "all", grp_key)]
  } else if (identical(pooling, "tail_pooled")) {
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


# Internal: fitted incremental means mu_hat_{ij} on the full I x J grid --------
#
# Renshaw-Verrall (1998) ODP MLE equivalence: chain-ladder factors define
# fitted incrementals via back-from-ultimate:
#   1. Project ultimates U_hat_i = C_{i, last_obs_i} * prod_{k=last_obs_i}^{J-1} f_k
#   2. Back-fill cumulative grid: C_hat_{iJ} = U_hat_i; C_hat_{ij} = C_hat_{i,j+1} / f_j
#   3. Differentiate row-wise: mu_hat_{i1} = C_hat_{i1}; mu_hat_{ij} = C_hat_{ij} - C_hat_{i,j-1}
#
# Returns an n_coh x n_dev matrix of fitted incrementals (full grid;
# upper triangle is fit, lower triangle is projection).
.boot_fitted_grid <- function(mat_obs, last_obs_idx, f_hat_vec, link_to_idx,
                              n_coh, n_dev) {
  # Step 1+2: build fitted cumulative grid C_hat
  c_hat <- matrix(NA_real_, nrow = n_coh, ncol = n_dev)

  # Per-cohort: anchor at last observed cumulative, project forward with
  # f_hat (lower triangle), then back-fill earlier devs by dividing by f_hat
  # (using sequential ata_from -> ata_to mapping).
  f_by_to <- rep(NA_real_, n_dev)  # f_hat indexed by ata_to (dev index)
  f_by_to[link_to_idx] <- f_hat_vec

  for (i in seq_len(n_coh)) {
    last_j <- last_obs_idx[i]
    if (is.na(last_j)) next
    base <- mat_obs[i, last_j]
    if (!is.finite(base)) next
    c_hat[i, last_j] <- base
    # Forward (lower triangle)
    if (last_j < n_dev) {
      cur <- base
      for (j in seq(last_j + 1L, n_dev)) {
        f_k <- f_by_to[j]
        if (is.finite(f_k)) cur <- f_k * cur
        c_hat[i, j] <- cur
      }
    }
    # Backward (earlier devs along upper triangle)
    if (last_j > 1L) {
      cur <- base
      for (j in seq(last_j - 1L, 1L)) {
        f_k <- f_by_to[j + 1L]  # f mapping (j) -> (j+1)
        if (is.finite(f_k) && f_k > 0) {
          cur <- cur / f_k
        }
        c_hat[i, j] <- cur
      }
    }
  }

  # Step 3: incremental = row-wise diff
  mu_hat <- matrix(NA_real_, nrow = n_coh, ncol = n_dev)
  mu_hat[, 1L] <- c_hat[, 1L]
  if (n_dev >= 2L) {
    for (j in seq(2L, n_dev)) {
      mu_hat[, j] <- c_hat[, j] - c_hat[, j - 1L]
    }
  }
  mu_hat
}


# Internal: hat-matrix diagonal h_ii via QR ------------------------------
#
# ODP GLM design matrix X for the model log(mu_{ij}) = alpha_i + beta_j with
# corner constraint beta_1 = 0 (drop dev=1 indicator). Columns: I origin
# indicators + (J-1) dev indicators (j = 2..J). One row per observed
# cell; identifiability gives p = I + J - 1.
#
# h_ii = diag(W^{1/2} X (X' W X)^{-1} X' W^{1/2}) with W = diag(mu_hat).
# Computed via QR of W^{1/2} X: h = rowSums(Q^2). Stable and avoids
# explicit inverse.
.boot_hat_diag <- function(mu_hat_obs, coh_idx, dev_idx, n_coh, n_dev) {
  n <- length(mu_hat_obs)
  if (n == 0L) return(numeric(0))
  if (n_dev < 2L) {
    # Only one dev column => degenerate (no beta columns); X reduces to row
    # indicators alone, h = 1 for every cell. Surface this so corner-drop
    # logic excludes everything (caller will fall back to DF correction).
    return(rep(1, n))
  }

  p <- n_coh + n_dev - 1L
  X <- matrix(0, nrow = n, ncol = p)
  for (k in seq_len(n)) {
    X[k, coh_idx[k]] <- 1
    if (dev_idx[k] >= 2L)
      X[k, n_coh + dev_idx[k] - 1L] <- 1
  }

  # W^{1/2} * X (row-scale)
  w_sqrt <- sqrt(pmax(mu_hat_obs, 0))
  WhX <- w_sqrt * X

  # QR; drop zero-weight rows from leverage computation (their h is 0)
  qr_obj <- qr(WhX)
  # rank-deficient guard: if rank < p, use thinned Q
  Q <- qr.Q(qr_obj)[, seq_len(qr_obj$rank), drop = FALSE]
  h <- rowSums(Q^2)
  h
}


# Internal: cell-level Pearson residuals + DF or hat correction -----------
#
# For each group, vectorise observed cells in (cohort, dev) order and
# compute:
#   r_ij^raw = (X_ij - mu_hat_ij) / sqrt(|mu_hat_ij|)
# Apply ONE of (alternatives, not stacked):
#   - hat_adj = TRUE:  r_ij = r_ij^raw / sqrt(1 - h_ii)
#   - hat_adj = FALSE: r_ij = r_ij^raw * sqrt(n / (n - p))  with p = I+J-1
# Drop cells where h_ii >= 1 - eps (corners) when hat_adj = TRUE.
#
# Returns a data.table with columns [grp..., cohort, dev, residual, mu_hat].
.boot_cell_residuals <- function(triangle, anchor, grp, target, hat_adj) {
  # NSE
  cohort <- dev <- NULL

  # Per-group iteration
  if (length(grp) > 0L) {
    grp_vals <- unique(triangle[, .SD, .SDcols = grp])
    single_grp <- nrow(grp_vals) == 1L
    if (single_grp) {
      # Fast path: skip merges, rbindlist, setcolorder for the common
      # single-group input.
      gkey <- grp_vals[1L]
      one <- .boot_cell_residuals_one(triangle, anchor, target, hat_adj)
      phi_one <- attr(one, "phi")
      for (col in names(gkey)) one[, (col) := gkey[[col]]]
      data.table::setcolorder(one, c(grp, "cohort", "dev", "residual", "mu_hat"))
      attr(one, "phi_dt") <- data.table::data.table(gkey, phi = phi_one)
      return(one)
    }
    out_list <- vector("list", nrow(grp_vals))
    phi_list <- vector("list", nrow(grp_vals))
    for (gi in seq_len(nrow(grp_vals))) {
      gkey <- grp_vals[gi]
      tri_g <- merge(triangle, gkey, by = grp, sort = FALSE)
      anc_g <- merge(anchor,   gkey, by = grp, sort = FALSE)
      one <- .boot_cell_residuals_one(tri_g, anc_g, target, hat_adj)
      phi_one <- attr(one, "phi")
      for (col in names(gkey)) one[, (col) := gkey[[col]]]
      out_list[[gi]] <- one
      phi_list[[gi]] <- data.table::data.table(gkey, phi = phi_one)
    }
    res <- data.table::rbindlist(out_list, use.names = TRUE, fill = TRUE)
    data.table::setcolorder(res, c(grp, "cohort", "dev", "residual", "mu_hat"))
    attr(res, "phi_dt") <- data.table::rbindlist(phi_list, use.names = TRUE)
    res
  } else {
    one <- .boot_cell_residuals_one(triangle, anchor, target, hat_adj)
    attr(one, "phi_dt") <- data.table::data.table(phi = attr(one, "phi"))
    one
  }
}


.boot_cell_residuals_one <- function(triangle, anchor, target, hat_adj) {
  cohorts <- sort(unique(triangle$cohort))
  devs    <- sort(unique(triangle$dev))
  n_coh   <- length(cohorts)
  n_dev   <- length(devs)

  # Wide observed cumulative matrix -- vectorised fill via integer index
  mat_obs <- matrix(NA_real_, nrow = n_coh, ncol = n_dev,
                    dimnames = list(as.character(cohorts),
                                    as.character(devs)))
  ci_vec <- match(triangle$cohort, cohorts)
  di_vec <- match(triangle$dev,    devs)
  ok <- !is.na(ci_vec) & !is.na(di_vec)
  if (any(ok)) {
    mat_obs[cbind(ci_vec[ok], di_vec[ok])] <- triangle[[target]][ok]
  }
  last_obs_idx <- apply(mat_obs, 1L, function(row) {
    ok <- which(is.finite(row))
    if (length(ok) == 0L) NA_integer_ else max(ok)
  })

  data.table::setorderv(anchor, "ata_from")
  link_to_idx <- match(anchor$ata_to, devs)
  f_hat_vec   <- anchor$f_hat

  mu_hat_grid <- .boot_fitted_grid(mat_obs, last_obs_idx, f_hat_vec,
                                    link_to_idx, n_coh, n_dev)

  # Observed incrementals: X_ij = C_ij - C_{i,j-1}; X_i1 = C_i1
  x_inc <- matrix(NA_real_, nrow = n_coh, ncol = n_dev)
  x_inc[, 1L] <- mat_obs[, 1L]
  if (n_dev >= 2L) {
    for (j in seq(2L, n_dev)) {
      x_inc[, j] <- mat_obs[, j] - mat_obs[, j - 1L]
    }
  }

  # Vectorise observed cells (i + j is unrestricted; we use is.finite)
  obs_mask <- is.finite(mat_obs) & is.finite(mu_hat_grid)
  cell_rows <- which(obs_mask, arr.ind = TRUE)
  if (nrow(cell_rows) == 0L) {
    return(data.table::data.table(
      cohort   = cohorts[integer(0)],
      dev      = devs[integer(0)],
      residual = numeric(0),
      mu_hat   = numeric(0)
    ))
  }

  coh_idx <- cell_rows[, 1L]
  dev_idx <- cell_rows[, 2L]
  mu_obs  <- mu_hat_grid[obs_mask]
  x_obs   <- x_inc[obs_mask]

  # Raw Pearson residuals (use |mu_hat| for numerical safety on incurred data)
  denom <- sqrt(pmax(abs(mu_obs), .Machine$double.eps))
  r_raw <- (x_obs - mu_obs) / denom
  # Cells with non-positive mu_hat -- set residual to NA (excluded from pool)
  r_raw[!is.finite(r_raw) | mu_obs <= 0] <- NA_real_

  # ODP single dispersion phi = sum r_raw^2 / (n_obs - p). Computed from RAW
  # residuals (pre-adjustment) -- invariant across hat/DF choices. Used by
  # the cell paradigm consumer (C kernel `bootstrap_kernel_cell`) as the
  # process noise scale for forward simulation (England-Verrall 1999).
  n_obs_phi <- sum(is.finite(r_raw))
  p_phi     <- n_coh + n_dev - 1L
  df_phi    <- n_obs_phi - p_phi
  phi_val   <- if (df_phi > 0)
                 sum(r_raw^2, na.rm = TRUE) / df_phi
               else NA_real_

  # Stage correction: hat OR DF (alternatives, not stacked)
  if (isTRUE(hat_adj)) {
    h <- .boot_hat_diag(mu_obs, coh_idx, dev_idx, n_coh, n_dev)
    eps <- 1e-10
    drop <- !is.finite(h) | h >= 1 - eps
    r_adj <- r_raw / sqrt(pmax(1 - h, eps))
    r_adj[drop] <- NA_real_
  } else {
    df_factor <- if (df_phi > 0) sqrt(n_obs_phi / df_phi) else 1
    r_adj <- r_raw * df_factor
  }

  out <- data.table::data.table(
    cohort   = cohorts[coh_idx],
    dev      = devs[dev_idx],
    residual = r_adj,
    mu_hat   = mu_obs
  )
  attr(out, "phi")   <- phi_val
  attr(out, "n_obs") <- n_obs_phi
  attr(out, "p")     <- p_phi
  out
}


# Internal: build cell residual pool with `pool_id` per (pooling, tail) ---
#
# Cell pool schema differs from link pool: residual lives at (cohort, dev)
# not (cohort, ata_from -> ata_to). Pool strategies:
#   - separated: per-dev pool ("grp_key|dev_j")
#   - pooled:    one pool per group ("grp_key" or "all")
#   - tail_pooled: per-dev pre-cut, single "POST" bucket post-cut
.boot_build_pool_cell <- function(cell_resid, grp, pooling, tail, min_pool,
                                   maturity, demean = TRUE) {
  # NSE
  residual <- dev <- mat_change <- grp_key <- N <- below <-
    cut_to <- is_post <- NULL

  # Drop NaN/Inf and exact zeros. Exact zeros arise at corner cells (each
  # cohort's latest-observed dev: fitted = observed, so r = 0). Resampling
  # a 0 makes the corresponding pseudo cell deterministic (= mu_hat), which
  # artificially narrows the bootstrap distribution. Shapland (2010)
  # recommends removing zeros from the pool.
  dt <- cell_resid[is.finite(residual) & residual != 0]

  # demean = TRUE (default): subtract per-group residual mean. Shapland
  # (2010, Sec.4.2 "Negative Incremental Losses") discusses this as one
  # option: "if a zero residual average is desired, then one option is
  # the addition of a single constant to all residuals, such that the
  # sum of the shifted residuals is zero" -- while also noting the
  # counter-view that the non-zero average may be a "characteristic of
  # the data set" and need not be removed. demean = FALSE leaves the
  # raw residuals untouched.
  if (length(grp) > 0L) {
    dt[, ("grp_key") := do.call(paste, c(.SD, sep = "|")), .SDcols = grp]
  } else {
    dt[, ("grp_key") := ""]
  }
  if (isTRUE(demean)) {
    dt[, ("residual") := residual - mean(residual), by = "grp_key"]
  }

  if (identical(pooling, "separated")) {
    dt[, ("pool_id") := paste(grp_key, as.character(dev), sep = "|")]
  } else if (identical(pooling, "pooled")) {
    dt[, ("pool_id") := data.table::fifelse(grp_key == "", "all", grp_key)]
  } else if (identical(pooling, "tail_pooled")) {
    if (identical(tail, "maturity")) {
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
      dt[, ("is_post") := is.finite(mat_change) & dev >= mat_change]
      dt[, ("pool_id") := data.table::fifelse(
        is_post,
        paste(grp_key, "POST", sep = "|"),
        paste(grp_key, as.character(dev), sep = "|")
      )]
      dt[, c("mat_change", "is_post") := NULL]
    } else {
      counts <- dt[, .N, by = c("grp_key", "dev")]
      data.table::setorderv(counts, c("grp_key", "dev"))
      counts[, ("below") := N < min_pool]
      cut_lookup <- counts[, {
        first_below <- which(below)[1L]
        list(cut_to = if (is.na(first_below)) NA_real_
                       else as.numeric(dev[first_below]))
      }, by = "grp_key"]
      dt <- merge(dt, cut_lookup, by = "grp_key", all.x = TRUE, sort = FALSE)
      dt[, ("is_post") := is.finite(cut_to) & dev >= cut_to]
      dt[, ("pool_id") := data.table::fifelse(
        is_post,
        paste(grp_key, "POST", sep = "|"),
        paste(grp_key, as.character(dev), sep = "|")
      )]
      dt[, c("cut_to", "is_post") := NULL]
    }
  }

  dt[, grp_key := NULL]
  keep <- c(grp, "cohort", "dev", "residual", "pool_id")
  dt[, .SD, .SDcols = keep]
}



# Section 4 -- Stage 1: generate B pseudo triangles ===========================
#
# For each group, build B perturbed [cohort x dev] cumulative loss
# triangles. Three modes share the same output shape but use different
# first-stage algorithms:
#
#   residual = "cell":  ODP cell-residual resample -> cumsum -> refit f* ->
#                       forward project. B-loop replaced by a single C
#                       kernel call (see `src/bootstrap.c`).
#   residual = "link":  Mack chain residual chained through the cumulative
#                       recursion alt[i, k+1] = f_k * alt[i, k] +
#                       r* * sqrt(sigma_k^2 * alt[i, k]). Per-replicate
#                       R loop (sequential over k).
#   type = "parametric": Draw f_k* ~ N(f_hat, sqrt(Var(f_hat))) per
#                       replicate; observed cells unchanged; forward
#                       project lower triangle.
#
# Returns long-format data.table [grp..., cohort, dev, rep, <target>].

.boot_stage1 <- function(triangle, link, anchor, pool, phi_dt,
                          grp, is_residual_mode, residual, process,
                          B, alpha, target = "loss") {

  # Per-group iteration
  if (length(grp) > 0L) {
    grp_vals <- unique(triangle[, .SD, .SDcols = grp])
    single_grp <- nrow(grp_vals) == 1L
    if (single_grp) {
      # Fast path: skip merges + rbindlist when only one group is present.
      phi_g <- if (!is.null(phi_dt) && nrow(phi_dt) > 0L)
                 merge(phi_dt, grp_vals[1L], by = grp, sort = FALSE)
               else phi_dt
      return(.boot_stage1_one(
        triangle = triangle, link = link, anchor = anchor, pool = pool,
        phi_dt = phi_g,
        is_residual_mode = is_residual_mode, residual = residual,
        process = process, B = B, alpha = alpha,
        grp_vals = grp_vals[1L], target = target
      ))
    }
    out_list <- vector("list", nrow(grp_vals))
    for (gi in seq_len(nrow(grp_vals))) {
      gkey <- grp_vals[gi]
      tri_g <- merge(triangle, gkey, by = grp, sort = FALSE)
      link_g <- merge(link, gkey, by = grp, sort = FALSE)
      anchor_g <- merge(anchor, gkey, by = grp, sort = FALSE)
      pool_g <- if (nrow(pool) > 0L) merge(pool, gkey, by = grp, sort = FALSE)
                else pool
      phi_g  <- if (!is.null(phi_dt) && nrow(phi_dt) > 0L)
                  merge(phi_dt, gkey, by = grp, sort = FALSE)
                else phi_dt
      out_list[[gi]] <- .boot_stage1_one(
        triangle = tri_g, link = link_g, anchor = anchor_g, pool = pool_g,
        phi_dt = phi_g,
        is_residual_mode = is_residual_mode, residual = residual,
        process = process, B = B, alpha = alpha,
        grp_vals = gkey, target = target
      )
    }
    list(
      cum_mean    = lapply(out_list, `[[`, "cum_mean"),
      cum_sampled = lapply(out_list, `[[`, "cum_sampled"),
      cohorts     = out_list[[1L]]$cohorts,
      devs        = out_list[[1L]]$devs,
      B           = out_list[[1L]]$B,
      grp_vals    = grp_vals,
      n_groups    = nrow(grp_vals)
    )
  } else {
    .boot_stage1_one(
      triangle = triangle, link = link, anchor = anchor, pool = pool,
      phi_dt = phi_dt,
      is_residual_mode = is_residual_mode, residual = residual,
      process = process, B = B, alpha = alpha,
      grp_vals = NULL, target = target
    )
  }
}


# Per-group worker for Stage 1. Returns the raw C-side 3D arrays
# (cum_mean, cum_sampled) plus per-group metadata. The caller
# (`bootstrap.Triangle`) always drives `$summary` straight from these
# arrays via `.boot_summary_from_arrays`; the long-format
# pseudo_triangles data.table is built lazily on first access to
# `$pseudo_triangles` via `.boot_build_pseudo_long()` (and only when
# `keep_pseudo = TRUE` flagged the result for that build).
.boot_stage1_one <- function(triangle, link, anchor, pool, phi_dt = NULL,
                              is_residual_mode, residual = "link",
                              process = "gamma",
                              B, alpha, grp_vals,
                              target = "loss") {

  cohort <- dev <- NULL  # NSE

  # Snapshot cohort x dev cumulative loss matrix
  cohorts <- sort(unique(triangle$cohort))
  devs    <- sort(unique(triangle$dev))
  n_coh   <- length(cohorts)
  n_dev   <- length(devs)

  # Wide observed matrix [cohort x dev] -- vectorised fill via integer index
  mat_obs <- matrix(NA_real_, nrow = n_coh, ncol = n_dev,
                    dimnames = list(as.character(cohorts), as.character(devs)))
  ci_vec <- match(triangle$cohort, cohorts)
  di_vec <- match(triangle$dev,    devs)
  ok <- !is.na(ci_vec) & !is.na(di_vec)
  if (any(ok)) {
    mat_obs[cbind(ci_vec[ok], di_vec[ok])] <- triangle[[target]][ok]
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

  # Pool-id lookup; key column depends on residual mode. Link mode keys
  # by ata_to (the link's destination dev); cell mode keys by dev (the
  # cell's own development period).
  pool_id_by_to  <- character(0)
  pool_id_by_dev <- character(0)
  if (is_residual_mode && nrow(pool) > 0L) {
    if (identical(residual, "link")) {
      pool_lookup <- unique(pool[, .SD, .SDcols = c("ata_to", "pool_id")])
      pool_id_by_to <- setNames(pool_lookup$pool_id,
                                as.character(pool_lookup$ata_to))
    } else {
      pool_lookup <- unique(pool[, .SD, .SDcols = c("dev", "pool_id")])
      pool_id_by_dev <- setNames(pool_lookup$pool_id,
                                  as.character(pool_lookup$dev))
    }
  }

  # Identify, per cohort, the last observed dev index (max j where mat_obs[i, j] is finite)
  last_obs_idx <- apply(mat_obs, 1L, function(row) {
    ok <- which(is.finite(row))
    if (length(ok) == 0L) NA_integer_ else max(ok)
  })

  # Cell mode: precompute fitted incremental means mu_hat_{ij} (full grid).
  # Reused across replicates -- these are the original-data fits, not
  # per-replicate refits.
  if (is_residual_mode && identical(residual, "cell")) {
    mu_hat_grid <- .boot_fitted_grid(mat_obs, last_obs_idx, f_hat_vec,
                                      link_to_idx, n_coh, n_dev)
  }

  # Hoisted lookups used by every branch (kernel-internal vectors require
  # them prebuilt). Avoids per-cell as.character() / match() inside the
  # B * n_cells hot path.
  devs_chr   <- as.character(devs)
  k_idx_by_j <- match(devs, anchor$ata_to)
  pid_by_dev <- if (length(pool_id_by_dev) > 0L) pool_id_by_dev[devs_chr]
                else rep(NA_character_, n_dev)
  pid_by_to  <- if (length(pool_id_by_to)  > 0L) pool_id_by_to[devs_chr]
                else rep(NA_character_, n_dev)

  # Flatten the pool list to CSR-like format reused by cell + link kernels.
  # `pool_pos[name]` maps a pool_id string to its 1-indexed slot; cells /
  # links not mapped to any pool get index 0 (kernel reads as "no draw").
  pool_names <- names(pool_by_id)
  if (length(pool_names) > 0L) {
    pool_lens      <- lengths(pool_by_id)
    pool_starts    <- as.integer(c(0L, cumsum(pool_lens)))
    pool_residuals <- unlist(pool_by_id, use.names = FALSE)
    pool_pos       <- setNames(seq_along(pool_names), pool_names)
  } else {
    pool_starts    <- 0L
    pool_residuals <- numeric(0)
    pool_pos       <- integer(0)
  }

  # ----- Stage 1 -- single native kernel per branch -------------------------
  # Each kernel returns the full [n_coh x n_dev x B] cumulative array
  # (residual resample / parametric draw + per-replicate f* + forward
  # project + clip). Branches share the bootstrap_refit_fstar and
  # bootstrap_fwd_proj_and_clip C helpers; see src/bootstrap.c.
  if (is_residual_mode && identical(residual, "cell")) {
    # Active cell index (upper triangle cap finite mu_hat)
    upper_full <- matrix(FALSE, n_coh, n_dev)
    for (i in seq_len(n_coh)) {
      lj <- last_obs_idx[i]
      if (!is.na(lj) && lj >= 1L) upper_full[i, seq_len(lj)] <- TRUE
    }
    upper_mask       <- upper_full & is.finite(mu_hat_grid)
    cell_active_lin  <- which(upper_mask)
    n_active         <- length(cell_active_lin)
    active_j         <- ((cell_active_lin - 1L) %/% n_coh) + 1L
    cell_active_mu   <- mu_hat_grid[cell_active_lin]
    cell_active_sqrt <- sqrt(abs(cell_active_mu))

    if (length(pool_names) > 0L) {
      cell_pool_idx <- pool_pos[pid_by_dev[active_j]]
      cell_pool_idx[is.na(cell_pool_idx)] <- 0L
      cell_pool_idx <- as.integer(cell_pool_idx)
    } else {
      cell_pool_idx <- integer(n_active)
    }

    # Extract scalar phi for current group (cell ODP dispersion).
    # phi_dt is per-group; .boot_stage1 already subset it to grp_vals.
    phi <- if (!is.null(phi_dt) && nrow(phi_dt) > 0L) {
      phi_dt$phi[1L]
    } else {
      NA_real_
    }
    process_code <- switch(process,
                           gamma   = 1L,
                           od_pois = 2L,
                           normal  = 3L,
                           1L)

    kernel_out <- .Call(
      C_bootstrap_kernel_cell,
      B,
      as.numeric(cell_active_mu),
      as.numeric(cell_active_sqrt),
      as.integer(cell_active_lin),
      cell_pool_idx,
      pool_residuals,
      pool_starts,
      as.integer(last_obs_idx),
      as.integer(link_to_idx),
      as.integer(k_idx_by_j),
      as.numeric(f_hat_vec),
      as.numeric(phi),
      as.numeric(alpha),
      process_code,
      n_coh, n_dev
    )
    # Dual-output: list(cum_mean, cum_sampled).
    out_arr_mean    <- kernel_out$cum_mean
    out_arr_sampled <- kernel_out$cum_sampled

  } else if (is_residual_mode && identical(residual, "link")) {

    if (length(pool_names) > 0L) {
      link_pool_idx <- pool_pos[pid_by_to[link_to_idx]]
      link_pool_idx[is.na(link_pool_idx)] <- 0L
      link_pool_idx <- as.integer(link_pool_idx)
    } else {
      link_pool_idx <- integer(n_links)
    }

    process_code <- switch(process,
                           gamma   = 1L,
                           od_pois = 2L,
                           normal  = 3L,
                           3L)
    kernel_out <- .Call(
      C_bootstrap_kernel_link,
      B,
      as.numeric(mat_obs),
      as.integer(last_obs_idx),
      as.integer(link_to_idx),
      as.integer(k_idx_by_j),
      as.numeric(f_hat_vec),
      as.numeric(sigma2_vec),
      link_pool_idx,
      pool_residuals,
      pool_starts,
      as.numeric(alpha),
      process_code,
      n_coh, n_dev
    )
    out_arr_mean    <- kernel_out$cum_mean
    out_arr_sampled <- kernel_out$cum_sampled

  } else {
    # Parametric: observed cells unchanged; per-replicate f* ~ N(f_hat,
    # sqrt(Var(f_hat))); forward-project + clip; Stage 2 noise via sigma2_k.
    process_code <- switch(process,
                           gamma   = 1L,
                           od_pois = 2L,
                           normal  = 3L,
                           3L)
    kernel_out <- .Call(
      C_bootstrap_kernel_parametric,
      B,
      as.numeric(mat_obs),
      as.integer(last_obs_idx),
      as.integer(k_idx_by_j),
      as.numeric(f_hat_vec),
      as.numeric(fvar_vec),
      as.numeric(sigma2_vec),
      as.numeric(alpha),
      process_code,
      n_coh, n_dev
    )
    out_arr_mean    <- kernel_out$cum_mean
    out_arr_sampled <- kernel_out$cum_sampled
  }

  # Return raw C-side 3D arrays + per-group metadata. The long-format
  # pseudo_triangles DT is built lazily by .boot_build_pseudo_long() in
  # bootstrap.Triangle's $pseudo_triangles accessor, only when the user
  # actually reads that slot. This avoids the ~250 ms rep.int / setDT
  # cost on a 5M-row pseudo_triangles for users who only consume
  # $summary.
  list(
    cum_mean    = out_arr_mean,
    cum_sampled = out_arr_sampled,
    cohorts     = cohorts,
    devs        = devs,
    B           = B,
    grp_vals    = grp_vals
  )
}


# Cohort x dev SE decomposition from the dual-column long-format pseudo_triangles.
#
# Pythagorean decomposition (law of total variance):
#   param_se = sd(loss_mean across rep)           (Stage 1 / parameter)
#   total_se = sd(loss_sampled across rep)        (Stage 1 + Stage 2)
#   proc_se  = sqrt(pmax(total_se^2 - param_se^2, 0))   (Stage 2 / process)
#
# CI uses type = 1 (Davison-Hinkley `(B+1) p in Z` convention) so the
# 0.025/0.975 quantiles land on integer ordinal indices for B = 999, 1999.
# Build $summary directly from the raw 3D arrays produced by
# .boot_stage1() -- both keep_pseudo paths now drive `$summary` through
# this single array-based helper. The keep_pseudo = TRUE path
# additionally exposes the long-format pseudo_triangles DT on
# `stage1_out$pseudo_long` for user inspection, but it never re-enters
# the summary computation.
.boot_summary_from_arrays <- function(stage1_out, grp, target = "loss",
                                      quantile_ci = FALSE) {
  is_multi <- !is.null(stage1_out$grp_vals) &&
              !is.null(stage1_out$n_groups) &&
              stage1_out$n_groups > 0L
  if (is_multi) {
    cum_mean_concat    <- do.call(c, lapply(stage1_out$cum_mean,    as.numeric))
    cum_sampled_concat <- do.call(c, lapply(stage1_out$cum_sampled, as.numeric))
    n_groups <- stage1_out$n_groups
    grp_vals <- stage1_out$grp_vals
  } else {
    # Single group (or no grouping columns) -- stage1_out is the single
    # per-group list as returned by .boot_stage1_one().
    cum_mean_concat    <- as.numeric(stage1_out$cum_mean)
    cum_sampled_concat <- as.numeric(stage1_out$cum_sampled)
    n_groups <- 1L
    grp_vals <- stage1_out$grp_vals
  }
  cohorts <- stage1_out$cohorts
  devs    <- stage1_out$devs
  n_coh   <- length(cohorts)
  n_dev   <- length(devs)

  res <- .Call(C_bootstrap_summary_kernel,
               cum_mean_concat, cum_sampled_concat,
               n_coh, n_dev, as.integer(n_groups),
               as.logical(quantile_ci),
               c(0.025, 0.975))

  cell_n <- n_coh * n_dev
  dt <- data.table::data.table(
    cohort    = rep.int(rep.int(cohorts, n_dev), n_groups),
    dev       = rep.int(rep(devs, each = n_coh), n_groups),
    mean_proj = res$mean_proj,
    param_se  = res$param_se,
    proc_se   = res$proc_se,
    total_se  = res$total_se,
    total_cv  = res$total_cv
  )
  if (length(grp) > 0L && !is.null(grp_vals)) {
    if (is.data.frame(grp_vals) && nrow(grp_vals) == n_groups) {
      for (col in grp)
        dt[, (col) := rep(grp_vals[[col]], each = cell_n)]
    } else {
      # single-group fast path: grp_vals is a length-1 data.frame
      for (col in grp) dt[, (col) := grp_vals[[col]]]
    }
  }

  if (isTRUE(quantile_ci)) {
    # Quantile CI is now C-computed by bootstrap_summary_kernel in the
    # same single .Call above -- just attach the returned ci_lo / ci_hi
    # columns.
    dt[, ci_lo := res$ci_lo]
    dt[, ci_hi := res$ci_hi]
  }

  by_cols  <- c(grp, "cohort", "dev")
  out_cols <- c(by_cols, "mean_proj",
                "param_se", "proc_se", "total_se", "total_cv")
  if (isTRUE(quantile_ci)) out_cols <- c(out_cols, "ci_lo", "ci_hi")
  data.table::setcolorder(dt, out_cols)
  dt[]
}


# Build the long-format pseudo_triangles DT from stage1_out array form
# (single- or multi-group). Used by $.BootstrapTriangle on first access
# to $pseudo_triangles; never called during the summary path. ~250 ms
# on a 4-group, 36 x 36, B=999 triangle, so we pay it only when the
# user actually reads the slot.
.boot_build_pseudo_long <- function(stage1_out, target = "loss", grp = character()) {
  is_multi <- !is.null(stage1_out$grp_vals) &&
              !is.null(stage1_out$n_groups) &&
              stage1_out$n_groups > 0L
  col_mean    <- paste0(target, "_mean")
  col_sampled <- paste0(target, "_sampled")

  build_one <- function(arr_mean, arr_sampled, gkey, cohorts, devs, B) {
    n_coh <- length(cohorts)
    n_dev <- length(devs)
    cohort_cls <- oldClass(cohorts)
    cohort_int <- unclass(cohorts)
    cohort_col <- rep.int(rep.int(cohort_int, n_dev), B)
    if (!is.null(cohort_cls)) oldClass(cohort_col) <- cohort_cls
    dev_col <- rep.int(rep(devs, each = n_coh), B)
    rep_col <- rep(seq_len(B), each = n_coh * n_dev)
    val_mean    <- as.numeric(arr_mean)
    val_sampled <- as.numeric(arr_sampled)
    n_long <- length(val_mean)
    if (is.null(gkey)) {
      cols <- list(cohort = cohort_col, dev = dev_col, rep = rep_col)
    } else {
      cols <- list()
      for (col in names(gkey)) {
        v <- gkey[[col]]
        cols[[col]] <- if (length(v) == n_long) v else rep_len(v, n_long)
      }
      cols$cohort <- cohort_col
      cols$dev    <- dev_col
      cols$rep    <- rep_col
    }
    cols[[col_mean]]    <- val_mean
    cols[[col_sampled]] <- val_sampled
    data.table::setDT(cols)
    cols[]
  }

  if (is_multi) {
    parts <- vector("list", stage1_out$n_groups)
    for (gi in seq_len(stage1_out$n_groups)) {
      parts[[gi]] <- build_one(
        stage1_out$cum_mean[[gi]],
        stage1_out$cum_sampled[[gi]],
        stage1_out$grp_vals[gi],
        stage1_out$cohorts,
        stage1_out$devs,
        stage1_out$B
      )
    }
    data.table::rbindlist(parts, use.names = TRUE)
  } else {
    build_one(
      stage1_out$cum_mean,
      stage1_out$cum_sampled,
      stage1_out$grp_vals,
      stage1_out$cohorts,
      stage1_out$devs,
      stage1_out$B
    )
  }
}


# Section 5 -- BootstrapTriangle S3 methods (print) ===========================

#' Print method for BootstrapTriangle
#' @param x A `BootstrapTriangle` object.
#' @param ... Unused.
#' @method print BootstrapTriangle
#' @export
print.BootstrapTriangle <- function(x, ...) {
  m <- x$meta
  is_param <- identical(m$type, "parametric")
  is_tail  <- identical(m$pooling, "tail_pooled")

  cat("<BootstrapTriangle>\n")
  cat(sprintf("  type     : %s\n", m$type))
  cat(sprintf("  method   : %s\n", m$method))
  if (!is_param) {
    cat(sprintf("  residual : %s\n", m$residual))
    if (identical(m$residual, "cell")) {
      cat(sprintf("  hat_adj  : %s\n", as.character(isTRUE(m$hat_adj))))
      cat(sprintf("  demean   : %s\n", as.character(isTRUE(m$demean))))
    } else {
      cat(sprintf("  hat_adj  : %s\n", as.character(isTRUE(m$hat_adj))))
    }
  }
  cat(sprintf("  process  : %s\n", m$process))
  if (!is_param) {
    cat(sprintf("  pooling  : %s\n", m$pooling))
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
  if (!is.null(x$summary)) {
    has_ci <- "ci_lo" %in% names(x$summary)
    cat(sprintf("  summary  : %d cohort x dev rows (%s)\n",
                nrow(x$summary),
                if (has_ci)
                  "mean_proj, param_se, proc_se, total_se, total_cv, ci_lo, ci_hi"
                else
                  "mean_proj, param_se, proc_se, total_se, total_cv  -- quantile_ci off"))
  }
  if (is.null(x$pseudo_triangles)) {
    cat("  pseudo size : 0 rows (keep_pseudo = FALSE -- long-format not built)\n")
  } else {
    cat(sprintf("  pseudo size : %d rows ([cohort x dev x B] long-format)\n",
                nrow(x$pseudo_triangles)))
  }
  invisible(x)
}


# Section 6 -- Bootstrap argument resolver ====================================
#
# fit_ratio / fit_loss / fit_exposure / backtest pass the user-supplied
# `bootstrap` argument through this single resolver. Output is either
# `NULL` (analytical path) or a `BootstrapTriangle`. The fit functions
# then read `bt$summary` directly -- the SE decomposition + CI columns
# are precomputed by `bootstrap()` itself, so no per-replicate refit
# loop lives in the fit functions (that work is done once inside the
# C kernel during `bootstrap()`).


#' Resolve a bootstrap argument to a BootstrapTriangle (4-type dispatch)
#'
#' Mirrors `.resolve_maturity()` / `.resolve_regime()` pattern. Accepts:
#'
#' \itemize{
#'   \item `NULL` (or `FALSE`, back-compat) -- returns `NULL` (no bootstrap).
#'   \item `TRUE` (back-compat) -- equivalent to `"auto"`.
#'   \item `"auto"` -- internal `bootstrap(tri, ...)` call with supplied
#'     defaults.
#'   \item A `BootstrapTriangle` object -- returned as-is.
#'   \item A function `function(tri) -> BootstrapTriangle` -- invoked on `tri`.
#' }
#'
#' @param arg The bootstrap argument supplied by the user.
#' @param tri A `Triangle` object (the data the bootstrap will be computed on).
#' @param B,seed,type,residual,hat_adj,process,method,pooling,tail,min_pool,maturity,target,alpha
#'   Defaults forwarded to `bootstrap.Triangle()` when `arg` resolves to
#'   `"auto"` or `TRUE`.
#'
#' @return A `BootstrapTriangle` object or `NULL`.
#'
#' @keywords internal
.resolve_bootstrap <- function(arg, tri,
                                B           = 499L,
                                seed        = NULL,
                                type        = "parametric",
                                residual    = "cell",
                                hat_adj     = TRUE,
                                demean      = TRUE,
                                process     = "normal",
                                method      = "sa",
                                pooling     = "pooled",
                                quantile_ci = FALSE,
                                keep_pseudo = TRUE,
                                tail        = "auto",
                                min_pool    = 5L,
                                maturity    = NULL,
                                target      = "loss",
                                alpha       = 1) {
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
    # has no residual pool, so omitting residual/hat_adj/pooling/tail/
    # min_pool/maturity prevents the validator from triggering "ignored"
    # warnings inside fit_loss / fit_exposure / fit_ratio (which always
    # forward `type = "parametric"` for their internal default).
    args <- list(tri,
                 type        = type,
                 method      = method,
                 process     = process,
                 target      = target,
                 B           = B,
                 seed        = seed,
                 alpha       = alpha,
                 quantile_ci = quantile_ci,
                 keep_pseudo = keep_pseudo)
    if (identical(type, "nonparametric")) {
      args <- c(args, list(residual = residual,
                           hat_adj  = hat_adj,
                           demean   = demean,
                           pooling  = pooling,
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


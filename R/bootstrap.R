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
                                     demean_set, min_pool_set,
                                     method_set) {

  # `min_pool` must be a single positive integer regardless of type/pooling.
  if (!is.numeric(min_pool) || length(min_pool) != 1L ||
      is.na(min_pool) || min_pool < 1L ||
      !isTRUE(all.equal(min_pool, round(min_pool))))
    stop("`min_pool` must be a single positive integer.", call. = FALSE)

  if (identical(type, "analytical")) {
    if (process_set && !identical(process, "normal"))
      stop("type = 'analytical' (Mack 1993 closed-form propagation) ",
           "requires process = 'normal'. For other process distributions ",
           "use type = 'nonparametric' or type = 'parametric'.",
           call. = FALSE)
    if (residual_set)
      warning("type = 'analytical' uses closed-form simulation; ",
              "'residual' argument is ignored.",
              call. = FALSE)
    if (pooling_set)
      warning("type = 'analytical' has no residual pool; ",
              "'pooling' argument is ignored.",
              call. = FALSE)
    if (tail_set)
      warning("type = 'analytical' has no residual pool; ",
              "'tail' argument is ignored.",
              call. = FALSE)
    if (min_pool_set)
      warning("type = 'analytical' has no residual pool; ",
              "'min_pool' argument is ignored.",
              call. = FALSE)
    if (hat_adj_set && isTRUE(hat_adj))
      warning("'hat_adj' is only defined for residual = 'cell'; ignored.",
              call. = FALSE)
    if (demean_set)
      warning("'demean' is only defined for residual = 'cell'; ignored.",
              call. = FALSE)
    if (method_set && !identical(method, "cl"))
      stop("type = 'analytical' currently implements only the CL ",
           "closed-form (Mack 1993). method = '", method, "' is not ",
           "yet supported in analytical mode (ED analytical would need ",
           "a closed-form variance for the intensity g_k; SA analytical ",
           "would additionally need a per-cohort stage transition). ",
           "Use method = 'cl', or switch to type = 'nonparametric' / ",
           "'parametric' for resample-based bootstrap.",
           call. = FALSE)
  } else if (identical(type, "parametric")) {
    # Phase 2b: textbook parametric bootstrap (cell-distribution sampling
    # + refit, England-Verrall 1999). All three methods supported (cl, ed,
    # sa). Process must be positivity-preserving for the additive ED /
    # composite SA paradigms; normal is OK for cl but not for ed/sa.
    if (identical(process, "lognormal"))
      stop("process = 'lognormal' not yet implemented (Phase 5b.3). ",
           "Use 'gamma', 'od_pois', or 'normal'.",
           call. = FALSE)
    if ((identical(method, "ed") || identical(method, "sa")) &&
        identical(process, "normal"))
      stop("type = 'parametric' with method = '", method, "' requires a ",
           "positivity-preserving process distribution. ",
           "Use process = 'gamma' (default) or 'od_pois'; ",
           "'normal' violates the additive variance assumption.",
           call. = FALSE)
    if (residual_set)
      warning("type = 'parametric' draws each active cell directly from ",
              "the process distribution; 'residual' argument is ignored.",
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
    if (identical(method, "ed") && identical(residual, "link") && method_set)
      stop("method = 'ed' (ED-paradigm additive recursion) requires ",
           "residual = 'cell' (Pearson residuals on incremental cells). ",
           "ED + link residuals is not implemented; the ED math assumes ",
           "an additive cell-level Pearson decomposition. ",
           "Use residual = 'cell' (default) or switch to method = 'cl'.",
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
#' @param type One of `"parametric"` (default), `"nonparametric"`, or
#'   `"analytical"`.
#'   `"analytical"` draws new link factors from
#'   `N(f_hat, sqrt(Var(f_hat)))` (Mack 1993 closed-form propagation; CL
#'   only). `"nonparametric"` resamples standardized residuals and
#'   reconstructs the pseudo triangle (England-Verrall / Pinheiro).
#'   `"parametric"` draws each active cell directly from
#'   `ProcessDist(mu_hat, phi)` and refits on the synthetic triangle
#'   (textbook England-Verrall 1999 parametric bootstrap; supports all
#'   three methods cl / ed / sa). When `type` is left unset, the function
#'   picks the type that best matches `method`: `cl` defaults to
#'   `"analytical"` (fastest), and `ed` / `sa` default to `"parametric"`
#'   (cleanest for their additive / stage-adaptive variance decomposition).
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
#'   the bootstrap should produce. One of `"ed"` (default -- exposure-driven
#'   additive recursion across all dev; Phase 1 keeps exposure fixed,
#'   projected once via CL), `"cl"` (chain-ladder multiplicative recursion
#'   across all dev), `"sa"` (stage-adaptive -- ED before maturity, CL after;
#'   currently routes through the CL kernel pending Phase 4 SA bootstrap).
#'   Mirrors the `method` argument of `fit_loss()`; the resulting
#'   `BootstrapTriangle` is consumed by the corresponding
#'   `fit_*(..., bootstrap = bt)` branch. `"ed"` requires
#'   `residual = "cell"`; ED + `residual = "link"` is not implemented.
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
#'     `"analytical"`) cumulative loss; the missing region contains
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
                                type        = c("parametric", "nonparametric",
                                                "analytical"),
                                residual    = c("cell", "link"),
                                hat_adj     = TRUE,
                                demean      = TRUE,
                                process     = c("gamma", "od_pois", "normal",
                                                "lognormal"),
                                method      = c("ed", "cl", "sa"),
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
  method_set   <- "method"   %in% names(mc)
  type_set     <- "type"     %in% names(mc)

  type     <- match.arg(type)
  residual <- match.arg(residual)
  process  <- match.arg(process)
  method   <- match.arg(method)
  pooling  <- match.arg(pooling)
  tail     <- match.arg(tail)
  target   <- match.arg(target)

  # Smart default: when type was not explicitly set, pick the type that
  # best matches the chosen method. CL gets analytical (Mack 1993 closed-
  # form, fastest). ED/SA get parametric (textbook England-Verrall 1999
  # cell-distribution sampling; cleanest fit for their additive / stage-
  # adaptive variance decomposition). Explicit residual / pooling / tail /
  # hat_adj / demean / min_pool args are nonparametric-only -- if any is
  # set, fall back to nonparametric to honour the user's intent.
  if (!type_set) {
    nonparam_signal <- residual_set || pooling_set || tail_set ||
                       hat_adj_set || demean_set || min_pool_set
    if (nonparam_signal) {
      type <- "nonparametric"
    } else if (identical(method, "cl")) {
      type <- "analytical"
    } else {
      type <- "parametric"
    }
  }

  # Auto-coerce method to "cl" when user picked link residuals without
  # explicitly setting method. ED + link is mathematically incoherent;
  # the new method default of "ed" would otherwise silently fail validation
  # for legacy `residual = "link"` callers.
  if (!method_set && identical(residual, "link") && identical(method, "ed")) {
    method <- "cl"
  }

  # Auto-coerce method to "cl" when type = "analytical" and the user did
  # not explicitly set method. Only the CL closed-form (Mack 1993) has an
  # analytical kernel; ED / SA analytical are deferred. Without this,
  # the new method default "ed" would silently fall through to the CL
  # analytical kernel and mis-label the result.
  if (!method_set && identical(type, "analytical") && !identical(method, "cl")) {
    method <- "cl"
  }

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
    min_pool_set = min_pool_set,
    method_set = method_set
  )

  min_pool <- as.integer(min_pool)

  # Parametric path has only one supported process (Mack 1993 closed-form
  # uses Normal). When the user didn't explicitly request a different
  # process, silently coerce to "normal" so meta$process truthfully
  # records what Stage 1 simulated under. (If the user *did* set process
  # to something non-normal, the validator already errored above.)
  if (identical(type, "analytical")) process <- "normal"

  # Preserve the user-supplied maturity arg before reassignment -- SA + cell
  # needs it independently of pooling/tail (mathematical input to the stage
  # transition, not just a pool-tail policy).
  user_maturity <- maturity

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

  grp <- .resolve_groups(x)

  is_residual_mode   <- identical(type, "nonparametric")
  is_parametric_mode <- identical(type, "parametric")

  # SA needs a resolved Maturity object to drive the per-cohort stage
  # transition (independent of `pooling`/`tail` -- maturity is a
  # mathematical input to SA, not just a pool-tail policy). Applies to
  # both nonparametric cell + parametric SA branches. Resolution mirrors
  # `.sa_proj`'s `maturity_from = NA` -> all-ED fallback when no Maturity
  # can be resolved (silent for symmetry with fit_loss). When the pool-side
  # resolution above already produced a Maturity object (tail_pooled +
  # maturity), reuse it.
  sa_needs_maturity <-
    (is_residual_mode && identical(residual, "cell") &&
       identical(method, "sa")) ||
    (is_parametric_mode && identical(method, "sa"))
  if (sa_needs_maturity) {
    sa_maturity <- if (inherits(maturity, "Maturity")) maturity else
                     .resolve_maturity(
                       if (is.null(user_maturity)) "auto" else user_maturity,
                       x)
  } else {
    sa_maturity <- maturity
  }

  if (is_residual_mode) {
    # 1) Build Link on the chosen target. ED + cell and SA + cell both need
    #    the dual-variable Link (loss + exposure) so we can read
    #    `exposure_from`; the other branches only need the single-variable
    #    Link (chain ladder anchor).
    if (identical(residual, "cell") &&
        (identical(method, "ed") || identical(method, "sa"))) {
      link <- as_link(x, loss = target, exposure = "exposure",
                      drop_invalid = TRUE)
    } else {
      link <- as_link(x, loss = target, drop_invalid = TRUE)
    }

    # 2) Compute Mack anchor per (group, ata_to). Used by all branches
    #    for the `f_anchor` / `sigma2_anchor` slots; ED additionally
    #    computes its own `g_hat` per link further below.
    anchor <- .boot_anchor_cl(link, groups = grp, alpha = alpha)

    if (identical(residual, "link")) {
      # Pinheiro 2003: standardized link residuals on each Link row
      link <- .boot_attach_residuals_cl(link, anchor = anchor, groups = grp)
      pool <- .boot_build_pool_cl(link, anchor = anchor, groups = grp,
                                pooling = pooling, tail = tail,
                                min_pool = min_pool, maturity = maturity)
    } else if (identical(method, "ed")) {
      # ED-paradigm cell residual (Phase 1, fixed exposure). Pearson
      # residuals follow the additive form:
      #   r_{i, k} = (loss_delta - g_k * exposure_from)
      #              / sqrt(g_k * exposure_from)
      # Pool keyed by (cohort, dev = ata_to) for compatibility with the
      # cell-mode pool builder.
      cell_resid <- .boot_cell_residuals_ed(link, groups = grp)
      phi <- attr(cell_resid, "phi")
      pool <- .boot_build_pool_cell_cl(cell_resid, groups = grp,
                                     pooling = pooling, tail = tail,
                                     min_pool = min_pool, maturity = maturity,
                                     demean = demean)
    } else if (identical(method, "sa")) {
      # SA-paradigm cell residual: dual-pool concat. ED pool covers cells
      # with from-dev < mat_k (early dev); CL pool covers cells with
      # from-dev >= mat_k (mature dev). Each pool keeps its own paradigm-
      # appropriate Pearson scale (sqrt(|g*P|) vs sqrt(|f*C|)), so they
      # CANNOT be merged into one bucket -- they're concat'd into one
      # flat residual vector with `pool_id` prefixes "ed|" / "cl|"
      # ensuring no collision at lookup time. Each ACTIVE cell at Stage 1
      # picks the right bucket via the paradigm match in .boot_stage1_one.
      cell_resid_ed <- .boot_cell_residuals_ed(link, groups = grp)
      cell_resid_cl <- .boot_cell_residuals_cl(x, anchor = anchor, groups = grp,
                                            target = target, hat_adj = hat_adj)
      phi_ed <- attr(cell_resid_ed, "phi")
      phi_cl <- attr(cell_resid_cl, "phi")
      pool_ed <- .boot_build_pool_cell_cl(cell_resid_ed, groups = grp,
                                       pooling = pooling, tail = tail,
                                       min_pool = min_pool, maturity = maturity,
                                       demean = demean)
      pool_cl <- .boot_build_pool_cell_cl(cell_resid_cl, groups = grp,
                                       pooling = pooling, tail = tail,
                                       min_pool = min_pool, maturity = maturity,
                                       demean = demean)
      if (nrow(pool_ed) > 0L)
        pool_ed[, ("pool_id") := paste0("ed|", pool_ed$pool_id)]
      if (nrow(pool_cl) > 0L)
        pool_cl[, ("pool_id") := paste0("cl|", pool_cl$pool_id)]
      pool <- data.table::rbindlist(list(pool_ed, pool_cl),
                                    use.names = TRUE, fill = TRUE)

      # Merge phi tables on group keys so .boot_stage1 per-group subset
      # gets both columns at once.
      if (length(grp) > 0L) {
        phi <- merge(phi_ed, phi_cl, by = grp,
                        suffixes = c("_ed", "_cl"), sort = FALSE)
      } else {
        phi <- data.table::data.table(
          phi_ed = if (nrow(phi_ed) > 0L) phi_ed$phi[1L] else NA_real_,
          phi_cl = if (nrow(phi_cl) > 0L) phi_cl$phi[1L] else NA_real_
        )
      }
    } else {
      # E-V 1999/2002: Pearson residuals on incremental cells, optionally
      # leverage-corrected (hat_adj). Pool keyed by (cohort, dev).
      cell_resid <- .boot_cell_residuals_cl(x, anchor = anchor, groups = grp,
                                          target = target, hat_adj = hat_adj)
      # Extract per-group phi (ODP single scale) BEFORE pool transforms
      # the table -- the pool builder isn't required to preserve attrs.
      phi <- attr(cell_resid, "phi")
      pool <- .boot_build_pool_cell_cl(cell_resid, groups = grp,
                                     pooling = pooling, tail = tail,
                                     min_pool = min_pool, maturity = maturity,
                                     demean = demean)
    }
  } else if (is_parametric_mode) {
    # Textbook parametric path (Phase 2b, England-Verrall 1999):
    #   each active cell is drawn directly from ProcessDist(mu_hat, phi)
    #   per replicate, then cumsum + refit f* / g* + forward project +
    #   Stage 2 noise. No residual pool, but the dispersion phi is the
    #   same ODP / ED / SA-paradigm phi computed from the original-data
    #   Pearson residuals (just like cell-mode), since it's the natural
    #   variance scale for ProcessDist.
    if (identical(method, "ed") || identical(method, "sa")) {
      link <- as_link(x, loss = target, exposure = "exposure",
                      drop_invalid = TRUE)
    } else {
      link <- as_link(x, loss = target, drop_invalid = TRUE)
    }
    anchor <- .boot_anchor_cl(link, groups = grp, alpha = alpha)

    if (identical(method, "ed")) {
      cell_resid <- .boot_cell_residuals_ed(link, groups = grp)
      phi <- attr(cell_resid, "phi")
    } else if (identical(method, "sa")) {
      cell_resid_ed <- .boot_cell_residuals_ed(link, groups = grp)
      cell_resid_cl <- .boot_cell_residuals_cl(x, anchor = anchor, groups = grp,
                                              target = target, hat_adj = hat_adj)
      phi_ed <- attr(cell_resid_ed, "phi")
      phi_cl <- attr(cell_resid_cl, "phi")
      if (length(grp) > 0L) {
        phi <- merge(phi_ed, phi_cl, by = grp,
                        suffixes = c("_ed", "_cl"), sort = FALSE)
      } else {
        phi <- data.table::data.table(
          phi_ed = if (nrow(phi_ed) > 0L) phi_ed$phi[1L] else NA_real_,
          phi_cl = if (nrow(phi_cl) > 0L) phi_cl$phi[1L] else NA_real_
        )
      }
    } else {
      # method = "cl" parametric: ODP cell dispersion via CL Pearson form.
      cell_resid <- .boot_cell_residuals_cl(x, anchor = anchor, groups = grp,
                                            target = target, hat_adj = hat_adj)
      phi <- attr(cell_resid, "phi")
    }
    pool <- .boot_empty_pool(grp)
  } else {
    # analytical path: closed-form simulation, no residual pool needed.
    # We still compute the anchor (f_hat, sigma2, f_var) -- those drive
    # the N(f_hat, sqrt(Var(f_hat))) draws inside .boot_stage1_one.
    link   <- as_link(x, loss = target, drop_invalid = TRUE)
    anchor <- .boot_anchor_cl(link, groups = grp, alpha = alpha)
    pool   <- .boot_empty_pool(grp)
  }

  # phi: cell-mode + parametric only; otherwise NULL (analytical / Mack
  # link path use sigma2 from the anchor).
  if (!(is_residual_mode && identical(residual, "cell")) &&
      !is_parametric_mode) {
    phi <- NULL
  }

  # 5) Stage 1 + 2 -- B pseudo triangles (raw 3D arrays only) ----------------
  # `.boot_stage1()` returns the raw C-side 3D arrays + per-group
  # metadata. The long-format pseudo_triangles DT (~5M rows on a typical
  # 4-group monthly triangle) is built lazily by .boot_build_pseudo_long
  # only when the user reads `$pseudo_triangles`.
  stage1_out <- .boot_stage1(
    triangle = x, link = link, anchor = anchor, pool = pool,
    phi = phi,
    groups = grp, is_residual_mode = is_residual_mode,
    is_parametric_mode = is_parametric_mode,
    residual = residual,
    process = process, method = method, B = B, alpha = alpha,
    target = target, sa_maturity = sa_maturity
  )

  boot_summary <- .boot_summary_from_arrays(stage1_out, groups = grp,
                                          target = target,
                                          quantile_ci = quantile_ci)

  # 6) Assemble -------------------------------------------------------------
  # When keep_pseudo = TRUE (opt-in; default is FALSE), eagerly build the
  # long-format pseudo_triangles DT for user inspection. This pays the
  # ~250-300 ms reshape cost up front so subsequent reads are O(1) and
  # the object has no hidden mutation behaviour.
  pseudo_triangles <- if (isTRUE(keep_pseudo))
    .boot_build_pseudo_long(stage1_out, target = target, groups = grp)
  else NULL

  structure(
    list(
      pseudo_triangles = pseudo_triangles,
      summary       = boot_summary,
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
        maturity    = if (!is.null(sa_maturity)) sa_maturity else maturity,
        phi      = phi
      )
    ),
    class = c("BootstrapTriangle", "list")
  )
}



# Section 3 -- Anchor + residual pool builders ================================
#   .boot_empty_pool             (parametric path placeholder)
#   .boot_volume_weighted_ratio  (sum(num)/sum(den) safety kernel, shared)
#   .boot_anchor_cl              (per-link f_hat, sigma2, f_var)
#   .boot_fill_sigma2            (Mack tail-rule fill)
#   .boot_attach_residuals_cl    (link mode: per-link Mack residuals)
#   .boot_build_pool_cl          (link mode: per-link pool assembly)
#   .boot_fitted_grid            (cell mode: chain-anchored fitted incrementals
#                                 backbone -- takes per-step closures)
#   .boot_steps_cl               (multiplicative fwd/bwd closures for CL)
#   .boot_steps_ed               (additive fwd/bwd closures for ED)
#   .boot_hat_diag_cl            (cell mode: GLM hat matrix leverage)
#   .boot_cell_residuals_cl(_one) (cell mode: Pearson residuals per cell)
#   .boot_build_pool_cell_cl     (cell mode: pool assembly with zero-drop + centering)

# Empty residual pool used by the parametric path so downstream code that
# inspects `pool$residual` / `pool$pool_id` sees a well-formed 0-row table.
.boot_empty_pool <- function(groups) {
  keep <- c(groups, "cohort", "ata_from", "ata_to", "residual", "pool_id")
  out <- data.table::data.table()
  for (col in keep) {
    out[, (col) := if (col == "residual") numeric(0)
                   else if (col %in% c("ata_from", "ata_to")) integer(0)
                   else character(0)]
  }
  out
}


# Internal: volume-weighted ratio sum(num) / sum(den) with the standard
# finiteness/positivity gate. Returns NA_real_ when no row passes the
# gate. Shared kernel for the loss CL, ED intensity, and exposure CL
# anchors.
.boot_volume_weighted_ratio <- function(num, den) {
  ok <- is.finite(num) & is.finite(den) & den > 0
  if (!any(ok)) return(NA_real_)
  s_den <- sum(den[ok])
  if (s_den <= 0) return(NA_real_)
  sum(num[ok]) / s_den
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
.boot_anchor_cl <- function(link, groups, alpha = 1) {
  # data.table NSE
  loss_from <- loss_to <- f_hat <- sigma2 <- f_var <- sum_from <- NULL

  by_cols <- c(groups, "ata_from", "ata_to")

  anchor <- link[is.finite(loss_from) & is.finite(loss_to) & loss_from > 0,
                 {
                   f       <- .boot_volume_weighted_ratio(loss_to, loss_from)
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
  if (length(groups) > 0L) {
    by_grp <- groups
  } else {
    by_grp <- NULL
  }
  data.table::setorderv(anchor, c(groups, "ata_from"))
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
# `pool_id` is filled later by .boot_build_pool_cl() (mode-dependent).
.boot_attach_residuals_cl <- function(link, anchor, groups) {
  # NSE
  loss_from <- loss_to <- f_hat <- sigma2 <- residual <- NULL

  by_cols <- c(groups, "ata_from", "ata_to")

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
.boot_build_pool_cl <- function(link, anchor, groups, pooling, tail, min_pool,
                              maturity) {
  # data.table NSE
  residual <- ata_to <- mat_change <- grp_key <- N <- below <-
    cut_to <- is_post <- NULL

  dt <- link[is.finite(residual)]

  # Build group key string ("g1|g2|...") once
  if (length(groups) > 0L) {
    dt[, ("grp_key") := do.call(paste, c(.SD, sep = "|")), .SDcols = groups]
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
      if (length(groups) > 0L) {
        mat <- data.table::as.data.table(maturity)
        mat <- mat[, .SD, .SDcols = c(groups, "change")]
        data.table::setnames(mat, "change", "mat_change")
        dt <- merge(dt, mat, by = groups, all.x = TRUE, sort = FALSE)
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

  keep <- c(groups, "cohort", "ata_from", "ata_to", "residual", "pool_id")
  dt[, .SD, .SDcols = keep]
}


# Internal: fitted incremental means mu_hat_{ij} on the full I x J grid --------
#
# Chain-anchored fitted incrementals shared backbone for CL (multiplicative)
# and ED (additive) paradigms. Renshaw-Verrall (1998) ODP MLE equivalence on
# the CL side; additive mirror on the ED side. For each cohort i with
# `last_j = last_obs_idx[i]`:
#   1. Anchor at observed cumulative: c_hat[i, last_j] = mat_obs[i, last_j]
#   2. Forward (j > last_j): cur <- step_fwd(cur, i, j)
#   3. Backward (j < last_j): cur <- step_bwd(cur, i, j)
#   4. mu_hat = row-wise diff of c_hat. By construction the upper-triangle
#      partial sums match the observed cumulative at `last_j` exactly.
#
# `step_fwd` / `step_bwd` are paradigm-specific closures built by
# `.boot_steps_cl` (multiplicative) or `.boot_steps_ed` (additive). Returns
# an n_coh x n_dev matrix of fitted incrementals (full grid; upper triangle
# is fit, lower triangle is projection).
.boot_fitted_grid <- function(mat_obs, last_obs_idx, n_coh, n_dev,
                              step_fwd, step_bwd) {
  c_hat <- matrix(NA_real_, nrow = n_coh, ncol = n_dev)
  for (i in seq_len(n_coh)) {
    last_j <- last_obs_idx[i]
    if (is.na(last_j)) next
    base <- mat_obs[i, last_j]
    if (!is.finite(base)) next
    c_hat[i, last_j] <- base
    if (last_j < n_dev) {
      cur <- base
      for (j in seq(last_j + 1L, n_dev)) {
        cur <- step_fwd(cur, i, j)
        c_hat[i, j] <- cur
      }
    }
    if (last_j > 1L) {
      cur <- base
      for (j in seq(last_j - 1L, 1L)) {
        cur <- step_bwd(cur, i, j)
        c_hat[i, j] <- cur
      }
    }
  }
  mu_hat <- matrix(NA_real_, nrow = n_coh, ncol = n_dev)
  mu_hat[, 1L] <- c_hat[, 1L]
  if (n_dev >= 2L) {
    for (j in seq(2L, n_dev)) {
      mu_hat[, j] <- c_hat[, j] - c_hat[, j - 1L]
    }
  }
  mu_hat
}


# Internal: multiplicative CL step closures for `.boot_fitted_grid`.
# `f_by_to[j]` is the chain-ladder factor applied at link (j-1 -> j).
.boot_steps_cl <- function(f_by_to) {
  list(
    fwd = function(cur, i, j) {
      f_k <- f_by_to[j]
      if (is.finite(f_k)) f_k * cur else cur
    },
    bwd = function(cur, i, j) {
      f_k <- f_by_to[j + 1L]
      if (is.finite(f_k) && f_k > 0) cur / f_k else cur
    }
  )
}


# Internal: additive ED step closures for `.boot_fitted_grid`.
# `g_by_to[j]` is the per-link intensity applied at link (j-1 -> j);
# `exposure_obs_mat[i, j-1]` is the FROM-side cumulative exposure for that
# link.
.boot_steps_ed <- function(g_by_to, exposure_obs_mat) {
  list(
    fwd = function(cur, i, j) {
      g_k    <- g_by_to[j]
      e_from <- exposure_obs_mat[i, j - 1L]
      if (is.finite(g_k) && is.finite(e_from)) cur + g_k * e_from else cur
    },
    bwd = function(cur, i, j) {
      g_k    <- g_by_to[j + 1L]
      e_from <- exposure_obs_mat[i, j]
      if (is.finite(g_k) && is.finite(e_from)) cur - g_k * e_from else cur
    }
  )
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
.boot_hat_diag_cl <- function(mu_hat_obs, coh_idx, dev_idx, n_coh, n_dev) {
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
.boot_cell_residuals_cl <- function(triangle, anchor, groups, target, hat_adj) {
  # NSE
  cohort <- dev <- NULL

  # Per-group iteration
  if (length(groups) > 0L) {
    grp_vals <- unique(triangle[, .SD, .SDcols = groups])
    single_grp <- nrow(grp_vals) == 1L
    if (single_grp) {
      # Fast path: skip merges, rbindlist, setcolorder for the common
      # single-group input.
      gkey <- grp_vals[1L]
      one <- .boot_cell_residuals_one_cl(triangle, anchor, target, hat_adj)
      phi_one <- attr(one, "phi")
      for (col in names(gkey)) one[, (col) := gkey[[col]]]
      data.table::setcolorder(one, c(groups, "cohort", "dev", "residual", "mu_hat"))
      attr(one, "phi") <- data.table::data.table(gkey, phi = phi_one)
      return(one)
    }
    out_list <- vector("list", nrow(grp_vals))
    phi_list <- vector("list", nrow(grp_vals))
    for (gi in seq_len(nrow(grp_vals))) {
      gkey <- grp_vals[gi]
      tri_g <- merge(triangle, gkey, by = groups, sort = FALSE)
      anc_g <- merge(anchor,   gkey, by = groups, sort = FALSE)
      one <- .boot_cell_residuals_one_cl(tri_g, anc_g, target, hat_adj)
      phi_one <- attr(one, "phi")
      for (col in names(gkey)) one[, (col) := gkey[[col]]]
      out_list[[gi]] <- one
      phi_list[[gi]] <- data.table::data.table(gkey, phi = phi_one)
    }
    res <- data.table::rbindlist(out_list, use.names = TRUE, fill = TRUE)
    data.table::setcolorder(res, c(groups, "cohort", "dev", "residual", "mu_hat"))
    attr(res, "phi") <- data.table::rbindlist(phi_list, use.names = TRUE)
    res
  } else {
    one <- .boot_cell_residuals_one_cl(triangle, anchor, target, hat_adj)
    attr(one, "phi") <- data.table::data.table(phi = attr(one, "phi"))
    one
  }
}


.boot_cell_residuals_one_cl <- function(triangle, anchor, target, hat_adj) {
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

  f_by_to <- rep(NA_real_, n_dev)
  f_by_to[link_to_idx] <- f_hat_vec
  steps <- .boot_steps_cl(f_by_to)
  mu_hat_grid <- .boot_fitted_grid(mat_obs, last_obs_idx, n_coh, n_dev,
                                   steps$fwd, steps$bwd)

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
  # the cell paradigm consumer (C kernel `bootstrap_kernel_cl_cell`) as the
  # process noise scale for forward simulation (England-Verrall 1999).
  n_obs_phi <- sum(is.finite(r_raw))
  p_phi     <- n_coh + n_dev - 1L
  df_phi    <- n_obs_phi - p_phi
  phi_val   <- if (df_phi > 0)
                 sum(r_raw^2, na.rm = TRUE) / df_phi
               else NA_real_

  # Stage correction: hat OR DF (alternatives, not stacked)
  if (isTRUE(hat_adj)) {
    h <- .boot_hat_diag_cl(mu_obs, coh_idx, dev_idx, n_coh, n_dev)
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


# Internal: ED-paradigm Pearson cell residuals (Phase 1) ------------------
#
# For each link cell (cohort, ata_to) of the dual-variable Link table:
#   mu_ed   = g_k * exposure_from
#   r_raw   = (loss_delta - mu_ed) / sqrt(mu_ed)
# where g_k is the volume-weighted per-link intensity anchor
# (sum(loss_delta) / sum(exposure_from) over observed link rows). Cells
# with non-positive mu_ed or non-finite endpoints are excluded.
#
# The pool builder (`.boot_build_pool_cell_cl`) consumes a (cohort, dev,
# residual, mu_hat) schema, so we publish `dev = ata_to` (the link's
# destination dev = the cell's own dev for the increment to be perturbed)
# and `mu_hat = mu_ed` (kept under the same column name for the shared
# downstream code path).
#
# Hat-matrix / DF adjustment is not applied in Phase 1 -- the ED design
# matrix differs from the ODP GLM and the hat-diagonal formula would need
# its own derivation. The raw Pearson residual is used directly.
#
# `phi` (cell-mode dispersion used for Stage 2 process noise) is computed
# as `sum(r_raw^2) / (n_obs - p)` with `p = n_links` (one parameter per
# link factor `g_k`), matching the ED-paradigm degrees-of-freedom.
.boot_cell_residuals_ed <- function(link, groups) {
  # NSE
  loss_delta <- exposure_from <- ata_to <- residual <- g_hat <- mu_ed <-
    n_obs <- sum_r2 <- n_links_used <- NULL

  by_cols <- c(groups, "ata_to")

  dt <- data.table::copy(link)

  # Per-link g_hat anchor (volume-weighted) on observed link rows.
  link_anchor <- dt[is.finite(loss_delta) & is.finite(exposure_from) &
                     exposure_from > 0,
                   list(g_hat = sum(loss_delta) / sum(exposure_from)),
                   by = by_cols]

  dt <- merge(dt, link_anchor, by = by_cols, all.x = TRUE, sort = FALSE)

  dt[, ("mu_ed") := g_hat * exposure_from]
  dt[, ("residual") := data.table::fifelse(
    is.finite(loss_delta) & is.finite(mu_ed) & mu_ed > 0,
    (loss_delta - mu_ed) / sqrt(mu_ed),
    NA_real_
  )]

  # Per-group phi: ODP-style single dispersion using ED Pearson residuals.
  # Degrees of freedom = n_obs - n_links (one parameter g_k per link).
  if (length(groups) > 0L) {
    by_grp <- groups
  } else {
    by_grp <- NULL
  }
  phi <- dt[is.finite(residual),
               list(
                 n_obs        = .N,
                 sum_r2       = sum(residual^2),
                 n_links_used = data.table::uniqueN(ata_to)
               ),
               by = by_grp]
  phi[, ("phi") := data.table::fifelse(
    is.finite(n_obs) & is.finite(n_links_used) & n_obs > n_links_used,
    sum_r2 / (n_obs - n_links_used),
    NA_real_
  )]
  phi_keep <- c(groups, "phi")
  phi <- phi[, .SD, .SDcols = phi_keep]

  # Reshape to the (cohort, dev, residual, mu_hat) schema expected by
  # `.boot_build_pool_cell_cl` -- dev = ata_to.
  out_keep <- c(groups, "cohort", "ata_to", "residual", "mu_ed")
  out <- dt[, .SD, .SDcols = out_keep]
  data.table::setnames(out, c("ata_to", "mu_ed"), c("dev", "mu_hat"))
  data.table::setattr(out, "phi", phi)
  out
}


# Internal: cumulative exposure observed matrix [n_coh, n_dev] ------------
.ensure_exposure_obs_mat <- function(triangle, cohorts, devs, n_coh, n_dev) {
  mat <- matrix(NA_real_, nrow = n_coh, ncol = n_dev,
                dimnames = list(as.character(cohorts), as.character(devs)))
  ci_vec <- match(triangle$cohort, cohorts)
  di_vec <- match(triangle$dev,    devs)
  ok <- !is.na(ci_vec) & !is.na(di_vec)
  if (any(ok)) {
    mat[cbind(ci_vec[ok], di_vec[ok])] <- triangle[["exposure"]][ok]
  }
  mat
}


# Internal: per-link f_hat anchor on the exposure column ------------------
#
# Standard CL volume-weighted ATA factor on cumulative exposure:
#   f_p_k = sum_i exposure[i, k+1] / sum_i exposure[i, k]
# Returns a list with `f_by_to` (length n_dev; NA for dev = 1) so the
# projector can look up the factor by `to-dev` index.
.boot_anchor_exposure_cl <- function(exp_obs_mat, last_obs_idx,
                                    n_coh, n_dev, devs) {
  f_by_to <- rep(NA_real_, n_dev)
  if (n_dev < 2L) return(list(f_by_to = f_by_to))
  for (j in seq(2L, n_dev)) {
    active <- which(!is.na(last_obs_idx) & last_obs_idx >= j)
    if (length(active) > 0L) {
      f_by_to[j] <- .boot_volume_weighted_ratio(
        exp_obs_mat[active, j],
        exp_obs_mat[active, j - 1L]
      )
    }
  }
  list(f_by_to = f_by_to)
}


# Internal: project exposure forward via CL on the exposure column --------
#
# Phase 1 assumption: exposure is treated as known (a single deterministic
# projection across all B replicates). For each cohort `i`, starting at
# its last observed dev, roll forward with the per-link `f_by_to`. The
# upper-triangle (observed) entries are preserved from `exp_obs_mat`.
.boot_proj_exposure_cl <- function(exp_obs_mat, last_obs_idx,
                                      f_by_to, n_coh, n_dev) {
  out <- exp_obs_mat
  for (i in seq_len(n_coh)) {
    lj <- last_obs_idx[i]
    if (is.na(lj) || lj >= n_dev) next
    base <- out[i, lj]
    if (!is.finite(base)) next
    cur <- base
    for (j in seq(lj + 1L, n_dev)) {
      f_k <- f_by_to[j]
      if (is.finite(f_k)) cur <- f_k * cur
      out[i, j] <- cur
    }
  }
  out
}


# Internal: per-link g_hat anchor (intensity, ED) -------------------------
#
# `link` is a dual-variable Link table (built with `as_link(..., exposure)`)
# whose `intensity` column already encodes `loss_delta / exposure_from`.
# The volume-weighted per-link intensity is
#   g_k = sum_i loss_delta_{i, k} / sum_i exposure_from_{i, k}
# Returned vector aligns with `anchor` row order
# (i.e., `g_hat_vec[k]` matches `anchor$ata_to[k]` and `link_to_idx[k]`).
.boot_anchor_ed <- function(anchor, link, n_links) {
  # NSE
  loss_delta <- exposure_from <- NULL

  g_links <- link[is.finite(loss_delta) & is.finite(exposure_from) &
                 exposure_from > 0,
               list(g_hat = .boot_volume_weighted_ratio(loss_delta,
                                                       exposure_from)),
               by = "ata_to"]
  # Lookup g_hat for each anchor row by `ata_to` (anchor row order is the
  # canonical link order in `.boot_stage1_one`).
  idx <- match(anchor$ata_to, g_links$ata_to)
  out <- g_links$g_hat[idx]
  out[!is.finite(out)] <- 0
  if (length(out) != n_links)
    out <- rep_len(out, n_links)
  out
}


# Internal: build cell residual pool with `pool_id` per (pooling, tail) ---
#
# Cell pool schema differs from link pool: residual lives at (cohort, dev)
# not (cohort, ata_from -> ata_to). Pool strategies:
#   - separated: per-dev pool ("grp_key|dev_j")
#   - pooled:    one pool per group ("grp_key" or "all")
#   - tail_pooled: per-dev pre-cut, single "POST" bucket post-cut
.boot_build_pool_cell_cl <- function(cell_resid, groups, pooling, tail, min_pool,
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
  if (length(groups) > 0L) {
    dt[, ("grp_key") := do.call(paste, c(.SD, sep = "|")), .SDcols = groups]
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
      if (length(groups) > 0L) {
        mat <- data.table::as.data.table(maturity)
        mat <- mat[, .SD, .SDcols = c(groups, "change")]
        data.table::setnames(mat, "change", "mat_change")
        dt <- merge(dt, mat, by = groups, all.x = TRUE, sort = FALSE)
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
  keep <- c(groups, "cohort", "dev", "residual", "pool_id")
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
#   type = "analytical": Draw f_k* ~ N(f_hat, sqrt(Var(f_hat))) per
#                       replicate; observed cells unchanged; forward
#                       project lower triangle. Mack 1993 closed-form
#                       propagation (CL only).
#
# Returns long-format data.table [grp..., cohort, dev, rep, <target>].

.boot_stage1 <- function(triangle, link, anchor, pool, phi,
                          groups, is_residual_mode,
                          is_parametric_mode = FALSE,
                          residual, process,
                          method = "ed",
                          B, alpha, target = "loss",
                          sa_maturity = NULL) {

  # Per-group iteration
  if (length(groups) > 0L) {
    grp_vals <- unique(triangle[, .SD, .SDcols = groups])
    single_grp <- nrow(grp_vals) == 1L
    if (single_grp) {
      # Fast path: skip merges + rbindlist when only one group is present.
      phi_g <- if (!is.null(phi) && nrow(phi) > 0L)
                 merge(phi, grp_vals[1L], by = groups, sort = FALSE)
               else phi
      mat_g <- .boot_subset_maturity(sa_maturity, grp_vals[1L], groups)
      return(.boot_stage1_one(
        triangle = triangle, link = link, anchor = anchor, pool = pool,
        phi = phi_g,
        is_residual_mode = is_residual_mode,
        is_parametric_mode = is_parametric_mode,
        residual = residual,
        process = process, method = method, B = B, alpha = alpha,
        grp_vals = grp_vals[1L], target = target,
        sa_maturity = mat_g
      ))
    }
    out_list <- vector("list", nrow(grp_vals))
    for (gi in seq_len(nrow(grp_vals))) {
      gkey <- grp_vals[gi]
      tri_g <- merge(triangle, gkey, by = groups, sort = FALSE)
      link_g <- merge(link, gkey, by = groups, sort = FALSE)
      anchor_g <- merge(anchor, gkey, by = groups, sort = FALSE)
      pool_g <- if (nrow(pool) > 0L) merge(pool, gkey, by = groups, sort = FALSE)
                else pool
      phi_g  <- if (!is.null(phi) && nrow(phi) > 0L)
                  merge(phi, gkey, by = groups, sort = FALSE)
                else phi
      mat_g  <- .boot_subset_maturity(sa_maturity, gkey, groups)
      out_list[[gi]] <- .boot_stage1_one(
        triangle = tri_g, link = link_g, anchor = anchor_g, pool = pool_g,
        phi = phi_g,
        is_residual_mode = is_residual_mode,
        is_parametric_mode = is_parametric_mode,
        residual = residual,
        process = process, method = method, B = B, alpha = alpha,
        grp_vals = gkey, target = target,
        sa_maturity = mat_g
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
      phi = phi,
      is_residual_mode = is_residual_mode,
      is_parametric_mode = is_parametric_mode,
      residual = residual,
      process = process, method = method, B = B, alpha = alpha,
      grp_vals = NULL, target = target,
      sa_maturity = sa_maturity
    )
  }
}


# Internal: per-group Maturity subset (used only when SA + cell). The full
# Maturity object holds rows for all groups; per-group worker only needs
# its own row to derive `mat_k_vec`. When `mat` is NULL or has no group
# columns, return it unchanged (the .boot_stage1_one branch handles NULL).
.boot_subset_maturity <- function(mat, gkey, groups) {
  if (is.null(mat) || length(groups) == 0L) return(mat)
  if (!is.data.frame(mat)) return(mat)
  if (!all(groups %in% names(mat))) return(mat)
  merge(data.table::as.data.table(mat), gkey, by = groups, sort = FALSE)
}


# Per-group worker for Stage 1. Returns the raw C-side 3D arrays
# (cum_mean, cum_sampled) plus per-group metadata. The caller
# (`bootstrap.Triangle`) always drives `$summary` straight from these
# arrays via `.boot_summary_from_arrays`; the long-format
# pseudo_triangles data.table is built lazily on first access to
# `$pseudo_triangles` via `.boot_build_pseudo_long()` (and only when
# `keep_pseudo = TRUE` flagged the result for that build).
.boot_stage1_one <- function(triangle, link, anchor, pool, phi = NULL,
                              is_residual_mode,
                              is_parametric_mode = FALSE,
                              residual = "link",
                              process = "gamma",
                              method = "ed",
                              B, alpha, grp_vals,
                              target = "loss",
                              sa_maturity = NULL) {

  cohort <- dev <- pool_id <- paradigm <- NULL  # NSE

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

  # Cell-style draw modes: precompute fitted incremental means mu_hat_{ij}
  # (full grid). Reused across replicates -- these are the original-data
  # fits, not per-replicate refits. ED-paradigm builds its own
  # `mu_ed_grid` below from `g_hat * exposure_from`, so it skips this.
  # SA-paradigm needs BOTH grids (CL grid for late-dev cells, ED grid for
  # early-dev cells), so it builds both. Same precompute is needed for
  # the parametric path (cell-distribution sampling needs mu per cell).
  cell_like <- (is_residual_mode && identical(residual, "cell")) ||
                is_parametric_mode
  if (cell_like && !identical(method, "ed")) {
    f_by_to <- rep(NA_real_, n_dev)
    f_by_to[link_to_idx] <- f_hat_vec
    steps <- .boot_steps_cl(f_by_to)
    mu_hat_grid <- .boot_fitted_grid(mat_obs, last_obs_idx, n_coh, n_dev,
                                     steps$fwd, steps$bwd)
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

    if (identical(method, "ed")) {
      # ----- ED-paradigm cell residual (Phase 1: fixed exposure) -------
      # mu_ed is built by `.boot_fitted_grid` with additive ED step
      # closures (`.boot_steps_ed`) -- the additive mirror of the CL
      # multiplicative recursion. Each cohort anchors at its observed
      # cumulative loss at `last_obs_idx`, then back-fills earlier devs
      # and projects later devs by additive increments
      # g_k * exposure_from. The upper-triangle partial sums match the
      # observed cumulative exactly (no anchor drift).
      # Residuals on link cells (j >= 2) come from the ED Pearson form
      # (Delta loss - g_k * P_{k-1}) / sqrt(g_k * P_{k-1}); first-period
      # cells have no link and pass through unperturbed.

      # 1) Observed cumulative exposure matrix + CL forward projection
      #    on the exposure column (projection lives in the lower
      #    triangle; the upper triangle keeps the observed values).
      exp_obs_mat <- .ensure_exposure_obs_mat(triangle, cohorts, devs,
                                              n_coh, n_dev)
      exp_anchor  <- .boot_anchor_exposure_cl(exp_obs_mat, last_obs_idx,
                                              n_coh, n_dev, devs)
      exposure_proj_mat <- .boot_proj_exposure_cl(exp_obs_mat,
                                                     last_obs_idx,
                                                     exp_anchor$f_by_to,
                                                     n_coh, n_dev)

      # 2) Per-link g_hat anchor on the original triangle (intensity
      #    weighted): g_k = sum_i (loss_delta_{i, k}) /
      #                      sum_i (exposure_from_{i, k}). Indexed by
      #    ata_to (one entry per link, aligned with link_to_idx).
      g_hat_vec <- .boot_anchor_ed(anchor, link, n_links)

      # 3) Build mu_ed_grid via chain-anchored ED fit (additive mirror of
      #    the CL multiplicative recursion). Each cohort is anchored at
      #    its observed cumulative loss at `last_obs_idx`; the upper
      #    triangle is back-filled and the lower triangle projected by
      #    additive increments g_k * exposure_from. By construction the
      #    sum of `mu_ed_grid[i, 1:last_j]` matches the observed
      #    cumulative at `last_j` exactly (no anchor drift). The
      #    exposure argument is `exposure_proj_mat` (upper triangle =
      #    observed, lower triangle = CL-projected) so lower-triangle
      #    additive steps have a finite exposure_from to multiply by.
      g_by_to <- rep(NA_real_, n_dev)
      g_by_to[link_to_idx] <- g_hat_vec
      steps      <- .boot_steps_ed(g_by_to, exposure_proj_mat)
      mu_ed_grid <- .boot_fitted_grid(mat_obs, last_obs_idx, n_coh, n_dev,
                                      steps$fwd, steps$bwd)

      upper_mask       <- upper_full & is.finite(mu_ed_grid)
      cell_active_lin  <- which(upper_mask)
      n_active         <- length(cell_active_lin)
      active_j         <- ((cell_active_lin - 1L) %/% n_coh) + 1L
      cell_active_mu   <- mu_ed_grid[cell_active_lin]
      cell_active_sqrt <- sqrt(abs(cell_active_mu))

      if (length(pool_names) > 0L) {
        cell_pool_idx <- pool_pos[pid_by_dev[active_j]]
        cell_pool_idx[is.na(cell_pool_idx)] <- 0L
        cell_pool_idx <- as.integer(cell_pool_idx)
      } else {
        cell_pool_idx <- integer(n_active)
      }

      phi <- if (!is.null(phi) && nrow(phi) > 0L) {
        phi$phi[1L]
      } else {
        NA_real_
      }
      process_code <- switch(process,
                             gamma   = 1L,
                             od_pois = 2L,
                             normal  = 3L,
                             1L)

      kernel_out <- .Call(
        C_bootstrap_kernel_ed_cell,
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
        as.numeric(g_hat_vec),
        as.numeric(exposure_proj_mat),
        as.numeric(phi),
        as.numeric(alpha),
        process_code,
        n_coh, n_dev
      )
      out_arr_mean    <- kernel_out$cum_mean
      out_arr_sampled <- kernel_out$cum_sampled

    } else if (identical(method, "sa")) {
      # ----- SA-paradigm cell residual (Phase 1 dual-pool concat) ------
      # Each active cell is classified by its paradigm:
      #   - ED: from-dev < mat_k_vec[i]  (use mu_ed_grid + ED pool prefix)
      #   - CL: from-dev >= mat_k_vec[i] (use mu_hat_grid + CL pool prefix)
      # The link uses dual-variable form (loss + exposure) so we can read
      # exposure_from in the ED branch.

      # 1) Build per-cohort mat_k_vec (1-indexed from-dev where CL begins).
      #    NA / no-Maturity -> .Machine$integer.max (all-ED fallback).
      mat_k_vec <- rep(.Machine$integer.max, n_coh)
      if (!is.null(sa_maturity)) {
        sa_mat <- data.table::as.data.table(sa_maturity)
        if ("ata_from" %in% names(sa_mat) && nrow(sa_mat) > 0L) {
          # SA + cell is single-cohort-axis within a group: take row 1.
          mfrom <- sa_mat$ata_from[1L]
          if (is.finite(mfrom)) {
            mat_k_vec <- rep(as.integer(mfrom), n_coh)
          }
        }
      }

      # 2) Build the ED-paradigm fitted grid (mirror of .boot_cell_residuals_ed
      #    structure: per-link g_hat anchor + chain-anchored ED projection)
      #    using the SAME helpers as the ED-only branch.
      exp_obs_mat <- .ensure_exposure_obs_mat(triangle, cohorts, devs,
                                              n_coh, n_dev)
      exp_anchor  <- .boot_anchor_exposure_cl(exp_obs_mat, last_obs_idx,
                                              n_coh, n_dev, devs)
      exposure_proj_mat <- .boot_proj_exposure_cl(exp_obs_mat,
                                                     last_obs_idx,
                                                     exp_anchor$f_by_to,
                                                     n_coh, n_dev)
      g_hat_vec <- .boot_anchor_ed(anchor, link, n_links)
      g_by_to   <- rep(NA_real_, n_dev)
      g_by_to[link_to_idx] <- g_hat_vec
      ed_steps   <- .boot_steps_ed(g_by_to, exposure_proj_mat)
      mu_ed_grid <- .boot_fitted_grid(mat_obs, last_obs_idx, n_coh, n_dev,
                                      ed_steps$fwd, ed_steps$bwd)

      # 3) Per-cell paradigm classification + mu / sqrt selection.
      #    active_i is 1-indexed cohort row; active_j is 1-indexed dev col.
      #    Cell paradigm:
      #      ED  iff active_j_from_1based <  mat_k_vec[active_i]
      #          where active_j_from_1based = active_j - 1L (1-indexed
      #          from-dev for the increment landing at cell (i, j)).
      #          Special case: j == 1 has no "from" link -- treat as ED
      #          (residual is the first observed cell against its mu).
      #      CL  otherwise.
      upper_full_mat <- upper_full
      ed_grid_finite <- is.finite(mu_ed_grid)
      cl_grid_finite <- is.finite(mu_hat_grid)

      # Active mask: cell is active for its paradigm iff the relevant mu
      # grid is finite AND the cell is in the upper triangle.
      active_lin_all <- which(upper_full_mat)
      a_i <- ((active_lin_all - 1L) %% n_coh) + 1L
      a_j <- ((active_lin_all - 1L) %/% n_coh) + 1L
      # 1-indexed from-dev for the link landing at (i, j): a_j - 1; for j = 1
      # we set it to 0 (always ED).
      a_from <- pmax(a_j - 1L, 0L)
      is_cl_cell <- a_from >= mat_k_vec[a_i] &
                    mat_k_vec[a_i] != .Machine$integer.max
      # Choose paradigm-appropriate finiteness check
      keep <- ifelse(is_cl_cell,
                     cl_grid_finite[active_lin_all],
                     ed_grid_finite[active_lin_all])
      active_lin_all <- active_lin_all[keep]
      a_i            <- a_i[keep]
      a_j            <- a_j[keep]
      is_cl_cell     <- is_cl_cell[keep]
      n_active       <- length(active_lin_all)

      cell_active_lin  <- active_lin_all
      cell_active_mu   <- ifelse(is_cl_cell,
                                 mu_hat_grid[active_lin_all],
                                 mu_ed_grid[active_lin_all])
      cell_active_sqrt <- sqrt(abs(cell_active_mu))

      # 4) Pool lookup: paradigm prefix decides which bucket. The pool
      #    table has `pool_id` already prefixed "ed|" / "cl|". The cached
      #    `pid_by_dev` lookup collapsed both paradigms onto one slot per
      #    dev (last-one-wins), so build a fresh per-paradigm lookup
      #    directly from the pool here, splitting by prefix.
      if (length(pool_names) > 0L) {
        pools <- unique(pool[, .SD, .SDcols = c("dev", "pool_id")])
        pools[, ("paradigm") := data.table::fifelse(
          startsWith(pool_id, "ed|"), "ed",
          data.table::fifelse(startsWith(pool_id, "cl|"), "cl", NA_character_)
        )]
        ed_lookup <- pools[paradigm == "ed"]
        cl_lookup <- pools[paradigm == "cl"]
        ed_by_dev <- if (nrow(ed_lookup) > 0L)
                       setNames(ed_lookup$pool_id, as.character(ed_lookup$dev))
                     else character(0)
        cl_by_dev <- if (nrow(cl_lookup) > 0L)
                       setNames(cl_lookup$pool_id, as.character(cl_lookup$dev))
                     else character(0)

        a_j_chr <- as.character(a_j)
        ed_lookup_full <- if (length(ed_by_dev) > 0L) ed_by_dev[a_j_chr]
                          else rep(NA_character_, length(a_j_chr))
        cl_lookup_full <- if (length(cl_by_dev) > 0L) cl_by_dev[a_j_chr]
                          else rep(NA_character_, length(a_j_chr))
        full_pid <- ifelse(is_cl_cell, cl_lookup_full, ed_lookup_full)
        cell_pool_idx <- pool_pos[full_pid]
        cell_pool_idx[is.na(cell_pool_idx)] <- 0L
        cell_pool_idx <- as.integer(cell_pool_idx)
      } else {
        cell_pool_idx <- integer(n_active)
      }

      # 5) Per-paradigm phi scalars (from merged phi with phi_ed / phi_cl).
      phi_ed_val <- if (!is.null(phi) && nrow(phi) > 0L &&
                        "phi_ed" %in% names(phi)) phi$phi_ed[1L]
                    else NA_real_
      phi_cl_val <- if (!is.null(phi) && nrow(phi) > 0L &&
                        "phi_cl" %in% names(phi)) phi$phi_cl[1L]
                    else NA_real_

      process_code <- switch(process,
                             gamma   = 1L,
                             od_pois = 2L,
                             normal  = 3L,
                             1L)

      kernel_out <- .Call(
        C_bootstrap_kernel_sa_cell,
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
        as.numeric(g_hat_vec),
        as.numeric(exposure_proj_mat),
        as.integer(mat_k_vec),
        as.numeric(phi_ed_val),
        as.numeric(phi_cl_val),
        as.numeric(alpha),
        process_code,
        n_coh, n_dev
      )
      out_arr_mean    <- kernel_out$cum_mean
      out_arr_sampled <- kernel_out$cum_sampled

    } else {
      # ----- CL-paradigm cell residual (method = "cl" only;
      #       SA now has its own branch above) -----------------
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
      # phi is per-group; .boot_stage1 already subset it to grp_vals.
      phi <- if (!is.null(phi) && nrow(phi) > 0L) {
        phi$phi[1L]
      } else {
        NA_real_
      }
      process_code <- switch(process,
                             gamma   = 1L,
                             od_pois = 2L,
                             normal  = 3L,
                             1L)

      kernel_out <- .Call(
        C_bootstrap_kernel_cl_cell,
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
    }

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
      C_bootstrap_kernel_cl_link,
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

  } else if (is_parametric_mode) {
    # Phase 2b: textbook parametric bootstrap. Each active cell drawn
    # directly from ProcessDist(mu_hat, phi); cumsum -> mask -> refit ->
    # forward project -> Stage 2 noise. Mirrors the cell-residual
    # branches except for Phase (a). Three method-dispatched kernels.
    upper_full <- matrix(FALSE, n_coh, n_dev)
    for (i in seq_len(n_coh)) {
      lj <- last_obs_idx[i]
      if (!is.na(lj) && lj >= 1L) upper_full[i, seq_len(lj)] <- TRUE
    }
    process_code <- switch(process,
                           gamma   = 1L,
                           od_pois = 2L,
                           normal  = 3L,
                           1L)

    if (identical(method, "ed")) {
      # ED parametric: build mu_ed_grid + g_hat_vec + exposure_proj.
      exp_obs_mat <- .ensure_exposure_obs_mat(triangle, cohorts, devs,
                                              n_coh, n_dev)
      exp_anchor  <- .boot_anchor_exposure_cl(exp_obs_mat, last_obs_idx,
                                              n_coh, n_dev, devs)
      exposure_proj_mat <- .boot_proj_exposure_cl(exp_obs_mat,
                                                     last_obs_idx,
                                                     exp_anchor$f_by_to,
                                                     n_coh, n_dev)
      g_hat_vec <- .boot_anchor_ed(anchor, link, n_links)
      g_by_to   <- rep(NA_real_, n_dev)
      g_by_to[link_to_idx] <- g_hat_vec
      ed_steps   <- .boot_steps_ed(g_by_to, exposure_proj_mat)
      mu_ed_grid <- .boot_fitted_grid(mat_obs, last_obs_idx, n_coh, n_dev,
                                      ed_steps$fwd, ed_steps$bwd)

      upper_mask       <- upper_full & is.finite(mu_ed_grid)
      cell_active_lin  <- which(upper_mask)
      cell_active_mu   <- mu_ed_grid[cell_active_lin]

      phi <- if (!is.null(phi) && nrow(phi) > 0L) {
        phi$phi[1L]
      } else {
        NA_real_
      }

      kernel_out <- .Call(
        C_bootstrap_kernel_ed_param,
        B,
        as.numeric(cell_active_mu),
        as.integer(cell_active_lin),
        as.integer(last_obs_idx),
        as.integer(link_to_idx),
        as.integer(k_idx_by_j),
        as.numeric(g_hat_vec),
        as.numeric(exposure_proj_mat),
        as.numeric(phi),
        as.numeric(alpha),
        process_code,
        n_coh, n_dev
      )
      out_arr_mean    <- kernel_out$cum_mean
      out_arr_sampled <- kernel_out$cum_sampled

    } else if (identical(method, "sa")) {
      # SA parametric: per-cell phi via stage classification, plus both
      # f_hat / g_hat / exposure_proj / mat_k_vec for the dual-refit and
      # stage-switch projection.
      mat_k_vec <- rep(.Machine$integer.max, n_coh)
      if (!is.null(sa_maturity)) {
        sa_mat <- data.table::as.data.table(sa_maturity)
        if ("ata_from" %in% names(sa_mat) && nrow(sa_mat) > 0L) {
          mfrom <- sa_mat$ata_from[1L]
          if (is.finite(mfrom)) {
            mat_k_vec <- rep(as.integer(mfrom), n_coh)
          }
        }
      }

      exp_obs_mat <- .ensure_exposure_obs_mat(triangle, cohorts, devs,
                                              n_coh, n_dev)
      exp_anchor  <- .boot_anchor_exposure_cl(exp_obs_mat, last_obs_idx,
                                              n_coh, n_dev, devs)
      exposure_proj_mat <- .boot_proj_exposure_cl(exp_obs_mat,
                                                     last_obs_idx,
                                                     exp_anchor$f_by_to,
                                                     n_coh, n_dev)
      g_hat_vec <- .boot_anchor_ed(anchor, link, n_links)
      g_by_to   <- rep(NA_real_, n_dev)
      g_by_to[link_to_idx] <- g_hat_vec
      ed_steps   <- .boot_steps_ed(g_by_to, exposure_proj_mat)
      mu_ed_grid <- .boot_fitted_grid(mat_obs, last_obs_idx, n_coh, n_dev,
                                      ed_steps$fwd, ed_steps$bwd)

      ed_grid_finite <- is.finite(mu_ed_grid)
      cl_grid_finite <- is.finite(mu_hat_grid)

      active_lin_all <- which(upper_full)
      a_i <- ((active_lin_all - 1L) %% n_coh) + 1L
      a_j <- ((active_lin_all - 1L) %/% n_coh) + 1L
      a_from <- pmax(a_j - 1L, 0L)
      is_cl_cell <- a_from >= mat_k_vec[a_i] &
                    mat_k_vec[a_i] != .Machine$integer.max
      keep <- ifelse(is_cl_cell,
                     cl_grid_finite[active_lin_all],
                     ed_grid_finite[active_lin_all])
      active_lin_all <- active_lin_all[keep]
      is_cl_cell     <- is_cl_cell[keep]

      cell_active_lin <- active_lin_all
      cell_active_mu  <- ifelse(is_cl_cell,
                                mu_hat_grid[active_lin_all],
                                mu_ed_grid[active_lin_all])

      phi_ed_val <- if (!is.null(phi) && nrow(phi) > 0L &&
                        "phi_ed" %in% names(phi)) phi$phi_ed[1L]
                    else NA_real_
      phi_cl_val <- if (!is.null(phi) && nrow(phi) > 0L &&
                        "phi_cl" %in% names(phi)) phi$phi_cl[1L]
                    else NA_real_

      # Per-cell phi via stage dispatch -- matches the Stage-1 mu paradigm.
      cell_active_phi <- data.table::fifelse(is_cl_cell, phi_cl_val, phi_ed_val)

      kernel_out <- .Call(
        C_bootstrap_kernel_sa_param,
        B,
        as.numeric(cell_active_mu),
        as.integer(cell_active_lin),
        as.integer(last_obs_idx),
        as.integer(link_to_idx),
        as.integer(k_idx_by_j),
        as.numeric(f_hat_vec),
        as.numeric(g_hat_vec),
        as.numeric(exposure_proj_mat),
        as.integer(mat_k_vec),
        as.numeric(cell_active_phi),
        as.numeric(phi_ed_val),
        as.numeric(phi_cl_val),
        as.numeric(alpha),
        process_code,
        n_coh, n_dev
      )
      out_arr_mean    <- kernel_out$cum_mean
      out_arr_sampled <- kernel_out$cum_sampled

    } else {
      # method = "cl" parametric: simplest path.
      upper_mask       <- upper_full & is.finite(mu_hat_grid)
      cell_active_lin  <- which(upper_mask)
      cell_active_mu   <- mu_hat_grid[cell_active_lin]

      phi <- if (!is.null(phi) && nrow(phi) > 0L) {
        phi$phi[1L]
      } else {
        NA_real_
      }

      kernel_out <- .Call(
        C_bootstrap_kernel_cl_param,
        B,
        as.numeric(cell_active_mu),
        as.integer(cell_active_lin),
        as.integer(last_obs_idx),
        as.integer(link_to_idx),
        as.integer(k_idx_by_j),
        as.numeric(f_hat_vec),
        as.numeric(phi),
        as.numeric(alpha),
        process_code,
        n_coh, n_dev
      )
      out_arr_mean    <- kernel_out$cum_mean
      out_arr_sampled <- kernel_out$cum_sampled
    }

  } else {
    # Analytical (Mack 1993): observed cells unchanged; per-replicate f* ~
    # N(f_hat, sqrt(Var(f_hat))); forward-project + clip; Stage 2 noise via
    # sigma2_k.
    process_code <- switch(process,
                           gamma   = 1L,
                           od_pois = 2L,
                           normal  = 3L,
                           3L)
    kernel_out <- .Call(
      C_bootstrap_kernel_cl_parametric,
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
.boot_summary_from_arrays <- function(stage1_out, groups, target = "loss",
                                      quantile_ci = FALSE) {
  ci_lo <- ci_hi <- NULL  # suppress R CMD check NOTEs for data.table NSE
  is_multi <- !is.null(stage1_out$grp_vals) &&
              !is.null(stage1_out$n_groups) &&
              stage1_out$n_groups > 0L
  if (is_multi) {
    cum_mean_concat    <- unlist(stage1_out$cum_mean,    use.names = FALSE)
    cum_sampled_concat <- unlist(stage1_out$cum_sampled, use.names = FALSE)
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
  if (length(groups) > 0L && !is.null(grp_vals)) {
    if (is.data.frame(grp_vals) && nrow(grp_vals) == n_groups) {
      for (col in groups)
        dt[, (col) := rep(grp_vals[[col]], each = cell_n)]
    } else {
      # single-group fast path: grp_vals is a length-1 data.frame
      for (col in groups) dt[, (col) := grp_vals[[col]]]
    }
  }

  if (isTRUE(quantile_ci)) {
    # Quantile CI is now C-computed by bootstrap_summary_kernel in the
    # same single .Call above -- just attach the returned ci_lo / ci_hi
    # columns.
    dt[, ci_lo := res$ci_lo]
    dt[, ci_hi := res$ci_hi]
  }

  by_cols  <- c(groups, "cohort", "dev")
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
.boot_build_pseudo_long <- function(stage1_out, target = "loss", groups = character()) {
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
  is_analytical <- identical(m$type, "analytical")
  is_tail       <- identical(m$pooling, "tail_pooled")

  cat("<BootstrapTriangle>\n")
  cat(sprintf("  type     : %s\n", m$type))
  cat(sprintf("  method   : %s\n", m$method))
  if (!is_analytical) {
    cat(sprintf("  residual : %s\n", m$residual))
    if (identical(m$residual, "cell")) {
      cat(sprintf("  hat_adj  : %s\n", as.character(isTRUE(m$hat_adj))))
      cat(sprintf("  demean   : %s\n", as.character(isTRUE(m$demean))))
    } else {
      cat(sprintf("  hat_adj  : %s\n", as.character(isTRUE(m$hat_adj))))
    }
  }
  cat(sprintf("  process  : %s\n", m$process))
  if (!is_analytical) {
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
                                type        = "analytical",
                                residual    = "cell",
                                hat_adj     = TRUE,
                                demean      = TRUE,
                                process     = "normal",
                                method      = "cl",
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
    # Pass only the args that apply to the chosen `type`. Analytical path
    # has no residual pool, so omitting residual/hat_adj/pooling/tail/
    # min_pool/maturity prevents the validator from triggering "ignored"
    # warnings inside fit_loss / fit_exposure / fit_ratio (which always
    # forward `type = "analytical"` for their internal default).
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



#' Overlay bootstrap summary statistics onto a fit's `$full` grid
#'
#' @description
#' The shared core of every bootstrap-CI path (`.lossfit_bootstrap()`,
#' `.exposurefit_bootstrap()`, and the in-worker `fit_sa()` /
#' `fit_ratio()` blocks). Given an already-resolved bootstrap result,
#' it renames the `bootstrap()` summary columns to the caller's
#' `<role>_*` schema, joins them onto `full` by `(groups, cohort, dev)`,
#' and -- on projected cells only -- overlays the bootstrap SE / CV
#' (and quantile CI when present) over the analytical values.
#'
#' Observed cells keep their analytical SE: the upper-triangle
#' perturbation is a parameter-uncertainty tool, not a claim about
#' observed-cell variability.
#'
#' @param full The fit's `$full` `data.table`.
#' @param boots A non-`NULL` resolved bootstrap result; `boots$summary`
#'   carries `mean_proj`, `param_se`, `proc_se`, `total_se`,
#'   `total_cv`, and optionally `ci_lo` / `ci_hi`.
#' @param role Column-name prefix, `"loss"` or `"exposure"`.
#' @param groups Group columns; the join key is
#'   `c(groups, "cohort", "dev")`.
#' @param se_cols Statistic suffixes to overlay -- e.g.
#'   `c("param_se", "proc_se", "total_se", "total_cv")` for loss,
#'   `c("total_se", "total_cv")` for exposure. The point projection is
#'   never overlaid; it stays analytical.
#'
#' @return `full` with the bootstrap values overlaid and the temporary
#'   `_boot` columns dropped.
#'
#' @keywords internal
.apply_bootstrap_overlay <- function(full, boots, role, groups, se_cols) {
  bsum  <- data.table::copy(boots$summary)
  stats <- c("proj", "param_se", "proc_se", "total_se", "total_cv")
  data.table::setnames(
    bsum,
    c("mean_proj", "param_se", "proc_se", "total_se", "total_cv"),
    paste0(role, "_", stats, "_boot")
  )
  has_ci <- all(c("ci_lo", "ci_hi") %in% names(bsum))
  if (has_ci) {
    data.table::setnames(bsum, c("ci_lo", "ci_hi"),
                         paste0(role, c("_ci_lo_boot", "_ci_hi_boot")))
  }

  full <- merge(full, bsum, by = c(groups, "cohort", "dev"),
                all.x = TRUE, sort = FALSE)

  is_proj  <- full$is_observed == FALSE
  overlays <- if (has_ci) c(se_cols, "ci_lo", "ci_hi") else se_cols
  for (sfx in overlays) {
    col  <- paste0(role, "_", sfx)
    vals <- full[[paste0(col, "_boot")]]
    ok   <- is_proj & is.finite(vals)
    full[ok, (col) := vals[ok]]
  }

  drop_boot <- paste0(role, "_", stats, "_boot")
  if (has_ci)
    drop_boot <- c(drop_boot, paste0(role, c("_ci_lo_boot", "_ci_hi_boot")))
  full[, (intersect(drop_boot, names(full))) := NULL]
  full
}


#' Apply bootstrap CI to a CL / ED dispatcher fit
#'
#' @description
#' The CL and ED workers don't run bootstrap natively. The dispatcher
#' calls this helper to map a `bootstrap()` summary onto the worker's
#' analytical `$full` schema -- same shape as the in-worker logic in
#' `fit_sa()`. Premium stays at observed values (loss-only bootstrap;
#' exposure-side uncertainty is layered by `fit_ratio()`).
#'
#' @keywords internal
.lossfit_bootstrap <- function(fit,
                               triangle,
                               bootstrap,
                               B,
                               seed,
                               alpha,
                               conf_level,
                               target = "loss") {

  # data.table NSE bindings
  loss_proj <- loss_total_se <- loss_total_cv <- NULL
  loss_proc_se <- loss_param_se <- NULL
  loss_ci_lo <- loss_ci_hi <- NULL
  loss_proj_boot <- loss_param_se_boot <- loss_proc_se_boot <- NULL
  loss_total_se_boot <- loss_total_cv_boot <- NULL
  loss_ci_lo_boot <- loss_ci_hi_boot <- NULL
  is_observed <- NULL

  boots <- .resolve_bootstrap(
    bootstrap, triangle,
    B           = B,
    seed        = seed,
    type        = "analytical",
    process     = "normal",
    target      = target,
    alpha       = alpha,
    quantile_ci = TRUE,
    keep_pseudo = FALSE
  )

  if (is.null(boots)) {
    fit$ci_type   <- "analytical"
    fit$bootstrap <- NULL
    return(fit)
  }

  grp <- fit$groups
  if (is.null(grp)) grp <- character(0)

  full <- fit$full

  full <- .apply_bootstrap_overlay(
    full, boots, role = "loss", groups = grp,
    se_cols = c("param_se", "proc_se", "total_se", "total_cv"))

  fit$full <- full

  # Rebuild $proj with consistent NA masking
  proj <- data.table::copy(full)
  na_cols <- c(
    "loss_proj", "exposure_proj",
    "incr_loss_proj", "incr_exposure_proj",
    "loss_proc_se2", "loss_param_se2", "loss_total_se2",
    "loss_proc_se",  "loss_param_se",  "loss_total_se",
    "loss_total_cv",
    "loss_ci_lo", "loss_ci_hi"
  )
  na_cols <- intersect(na_cols, names(proj))
  proj[is_observed == TRUE, (na_cols) := NA_real_]
  fit$proj <- proj

  fit$ci_type   <- "bootstrap"
  fit$bootstrap <- list(B = boots$meta$B, seed = boots$meta$seed)
  fit
}

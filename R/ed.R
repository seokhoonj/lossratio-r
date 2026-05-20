# ED Summary ---------------------------------------------------------------

#' Summarise ED intensity statistics
#'
#' @description
#' Internal helper that computes group-wise summary statistics for
#' incremental loss intensity \eqn{g} from a dual-variable `Link` object
#' (built with `exposure` set). Dispatched via [summary.Link()] when
#' `model = "ed"`.
#'
#' Two purposes:
#'
#' \enumerate{
#'   \item \strong{Diagnostics}: provides descriptive statistics
#'     (`mean`, `median`, `wt`, `cv`) that help the user assess the
#'     stability and consistency of observed \eqn{g} values across
#'     cohorts.
#'   \item \strong{Estimation}: fits a no-intercept weighted least
#'     squares model per development link to produce the WLS-estimated
#'     intensity (`g`), its standard error (`g_se`), relative standard
#'     error (`rse`), and residual sigma (`sigma`). These are used
#'     downstream by [fit_ed()].
#' }
#'
#' @section Relationship between `wt` and `g`:
#' Both `wt` and `g` are weighted averages of the observed intensities,
#' but they differ in how weights are assigned:
#'
#' \describe{
#'   \item{`wt`}{Exposure-weighted mean:
#'     \eqn{wt = \sum \Delta C^L_{i,k+1} / \sum C^P_{i,k}}.
#'     Computed from all rows where both values are finite.
#'     Independent of `alpha`.}
#'   \item{`g`}{WLS-estimated intensity from
#'     \code{lm(loss_delta ~ exposure_from + 0)}. Only rows where
#'     `exposure_from > 0` are used. When `alpha = 2`, `g` and `wt`
#'     are numerically equivalent.}
#' }
#'
#' @param object A `Link` object built with `exposure` set,
#'   typically produced by [as_link()].
#' @param alpha Numeric scalar controlling the variance structure in the
#'   WLS fit. Default is `1`.
#' @param digits Number of decimal places to round numeric columns.
#'   Default is `5`. Pass `NULL` to skip rounding.
#' @param ... Additional arguments passed to the internal WLS estimation.
#'
#' @return A `data.table` with class `"EDSummary"` containing one row
#'   per development link with descriptive statistics and WLS estimates.
#'
#' @seealso [as_link()], [summary.Link()], [fit_ed()]
#'
#' @keywords internal
.summarize_link_ed <- function(object,
                               alpha  = 1,
                               digits = 5,
                               ...) {

  .assert_class(object, "Link")

  if (is.null(attr(object, "exposure")))
    stop("`.summarize_link_ed()` requires a Link built with `exposure`.",
         call. = FALSE)

  grp <- .resolve_groups(object)

  dt <- .copy_dt(object)

  has_seg  <- "segment_id" %in% names(dt)
  grp_link <- c(grp, "ata_from", "ata_to", "ata_link",
                if (has_seg) "segment_id")

  # 1) descriptive statistics
  ds <- dt[, {
    vals <- intensity[is.finite(intensity)]
    ef   <- exposure_from
    dl   <- loss_delta
    m    <- mean(vals)

    .(
      mean      = m,
      median    = stats::median(vals),
      wt        = sum(dl, na.rm = TRUE) / sum(ef, na.rm = TRUE),
      cv        = stats::sd(vals, na.rm = TRUE) / abs(m),
      n_cohorts = .N,
      n_valid   = sum(is.finite(intensity)),
      n_inf     = sum(is.infinite(intensity)),
      n_nan     = sum(is.nan(intensity))
    )
  }, by = grp_link]

  ds[, ("valid_ratio") := n_valid / n_cohorts]

  # 2) WLS estimation
  link_factors <- .lm_ed(object, alpha = alpha, ...)

  # 3) join WLS results onto descriptive statistics
  join_cols <- c(grp, "ata_from", "ata_to", "ata_link",
                 if (has_seg) "segment_id")
  ds <- link_factors[
    , .SD,
    .SDcols = c(join_cols, "g", "g_se", "rse", "sigma")
  ][ds, on = join_cols]

  # 4) reorder columns
  col_order <- c(
    c(grp, "ata_from", "ata_to", "ata_link"),
    if (has_seg) "segment_id",
    "mean", "median", "wt", "cv",
    "g", "g_se", "rse", "sigma",
    "n_cohorts", "n_valid", "n_inf", "n_nan", "valid_ratio"
  )
  data.table::setcolorder(ds, col_order)

  ds[, ("ata_link") := factor(ata_link, levels = unique(dt$ata_link))]

  # `digits` is retained for downstream display only (see print.EDSummary).
  # Numeric columns are stored at full precision so callers get raw values.
  if (!is.null(digits)) {
    digits <- suppressWarnings(as.numeric(digits[1L]))
    if (length(digits) == 0L || is.na(digits))
      stop("Non-numeric `digits` specified.", call. = FALSE)
  }

  data.table::setattr(ds, "groups" , grp)
  data.table::setattr(ds, "cohort", attr(object, "cohort"))
  data.table::setattr(ds, "dev"   , attr(object, "dev"))
  data.table::setattr(ds, "loss"      , attr(object, "loss"))
  data.table::setattr(ds, "exposure"  , attr(object, "exposure"))
  data.table::setattr(ds, "digits"    , digits)

  .prepend_class(ds, "EDSummary")
}


#' Print method for `EDSummary`
#'
#' Numeric columns are stored at full double precision; rounding is applied
#' only for display. The default `digits` is taken from the `digits`
#' attribute set by [summary.Link()] (5 unless overridden).
#'
#' @param x An object of class `"EDSummary"`.
#' @param digits Number of decimal places to display. Default uses the
#'   `digits` attribute attached at construction.
#' @param ... Further arguments passed to `print.data.table`.
#'
#' @method print EDSummary
#' @export
print.EDSummary <- function(x, digits = attr(x, "digits"), ...) {
  if (is.null(digits)) {
    NextMethod()
    return(invisible(x))
  }
  y <- data.table::copy(x)
  data.table::setattr(y, "class", setdiff(class(y), "EDSummary"))
  num_cols <- vapply(y, is.numeric, logical(1L))
  for (nm in names(y)[num_cols]) {
    data.table::set(y, j = nm, value = round(y[[nm]], digits))
  }
  print(y, ...)
  invisible(x)
}


# ED Fitting ----------------------------------------------------------------

#' Fit ED intensity factors
#'
#' @description
#' Estimate incremental loss intensities \eqn{g_k} from a `"Triangle"`
#' object and return an `"EDFit"` object that bundles factor summaries,
#' selected intensities, and a cell-level projection of cumulative loss
#' and exposure (`$full`).
#'
#' Returns `g_sel`, `sigma2`, and factor variance
#' \eqn{\mathrm{Var}(\hat{g}_k)} (column `g_var`) in `$selected`.
#'
#' The `$full` projection table holds cumulative loss / exposure
#' projections and their standard errors, computed directly from the
#' Mack-style ED recursion (see `.ed_proj`, `.ed_proc_var`,
#' `.ed_param_var`). To validate an ED projection via [backtest()],
#' call `backtest(tri, target = "ratio", loss_method = "ed")`.
#'
#' @param x A `"Triangle"` object.
#' @param loss Cumulative loss variable. Default `"loss"`.
#'   Forwarded to [as_link()] and to downstream workers.
#' @param exposure Cumulative exposure variable. Default `"exposure"`.
#'   Forwarded to [as_link()] and to downstream workers.
#' @param method Estimation method. Currently only `"mack"` is supported.
#' @param alpha Numeric scalar controlling the variance structure. Default
#'   is `1`.
#' @param na_method Method used to fill `NA` values in `g_sel`. One
#'   of `"zero"` (default, set `NA` to 0 meaning no further development)
#'   or `"locf"` or `"none"`.
#' @inheritParams fit_ata
#' @param recent Optional positive integer. When supplied, only the most
#'   recent `recent` periods are used for estimation. Default is `NULL`.
#' @param regime Optional regime specification for cohort cutoff. Accepts:
#'   `NULL` (default -- no filter), a `"Regime"` object (from
#'   [detect_regime()]), the string `"auto"` (internal
#'   `detect_regime(tri, loss = "ratio")` call), or a function
#'   `function(tri) -> Regime`. Resolved internally via
#'   [.resolve_regime()]. When supplied, cohorts with
#'   `cohort < change_date` are excluded from estimation. Default is `NULL`.
#' @param bootstrap Optional bootstrap specification. Accepts `NULL`
#'   (default, analytical Mack SE only), a `BootstrapTriangle` object
#'   produced by [bootstrap()] (replayed for SE / CI), or the string
#'   `"auto"` to run an internal nonparametric bootstrap at fit time.
#' @param B Integer number of bootstrap replicates when `bootstrap = "auto"`.
#'   Default `999L`.
#' @param seed Optional integer seed for reproducible bootstrap draws.
#'   Default `NULL`.
#' @param conf_level Numeric in `(0, 1)`. Confidence level used for
#'   bootstrap-derived CI columns. Default `0.95`.
#' @param ... Additional arguments passed to [summary.Link()].
#'
#' @return An object of class `"EDFit"` (a named list) with components:
#'   \describe{
#'     \item{`factor`}{`EDSummary` of fitted intensities per development link.}
#'     \item{`selected`}{`data.table` of selected `g_sel`, `sigma2`,
#'       and `g_var`.}
#'     \item{`full`}{`data.table` of per-cell cumulative loss / exposure
#'       projection plus role-prefixed SE / CV columns
#'       (`loss_proj`, `incr_loss_proj`, `exposure_proj`,
#'       `incr_exposure_proj`, `loss_proc_se2`, `loss_param_se2`,
#'       `loss_total_se2`, `loss_proc_se`, `loss_param_se`,
#'       `loss_total_se`, `loss_total_cv`). Available cells include
#'       both observed and projected; `is_observed` flags observed cells.}
#'     \item{`link`}{`Link` object used for factor estimation.}
#'   }
#'
#' @seealso [as_link()], [summary.Link()], [fit_ratio()], [backtest()]
#'
#' @export
fit_ed <- function(x,
                   loss         = "loss",
                   exposure     = "exposure",
                   method       = c("mack"),
                   alpha        = 1,
                   na_method    = c("locf", "zero", "none"),
                   sigma_method = c("locf", "min_last2", "loglinear",
                                    "mack", "none"),
                   recent       = NULL,
                   regime       = NULL,
                   bootstrap    = NULL,
                   B            = 999L,
                   seed         = NULL,
                   conf_level   = 0.95,
                   ...) {

  .assert_triangle_input(x, "fit_ed()")

  regime <- .resolve_regime(regime, x)

  method       <- match.arg(method)
  na_method    <- match.arg(na_method)
  sigma_method <- match.arg(sigma_method)

  # 1) factor-level fit (mirrors fit_cl's use of fit_ata) ------------------
  intensity_fit <- fit_intensity(
    x,
    loss         = loss,
    exposure     = exposure,
    alpha        = alpha,
    na_method    = na_method,
    sigma_method = sigma_method,
    recent       = recent,
    regime       = regime,
    ...
  )

  # 2) compose EDFit from IntensityFit + method metadata -------------------
  # Use intensity_fit's resolved regime (a Regime object or NULL), not the
  # user's original input (which may be "auto" / a function / etc.).
  # Slot layout mirrors CLFit for cross-paradigm symmetry: identical
  # axis / output / config groups, with ED-specific `exposure` +
  # `na_method` (versus CL's `weight` + `tail` / `tail_factor` /
  # `maturity` / `use_maturity`).
  out <- list(
    call         = match.call(),
    data         = x,
    method       = method,
    groups       = intensity_fit$groups,
    cohort       = intensity_fit$cohort,
    dev          = intensity_fit$dev,
    loss         = intensity_fit$loss,
    exposure     = intensity_fit$exposure,
    full         = NULL,
    proj         = NULL,
    link         = intensity_fit$link,
    summary      = NULL,
    factor       = intensity_fit$factor,
    selected     = intensity_fit$selected,
    alpha        = alpha,
    na_method    = na_method,
    sigma_method = sigma_method,
    recent       = recent,
    regime       = intensity_fit$regime
  )
  class(out) <- c("EDFit", "list")

  # 3) compute factor variance (Mack-style -- required by the projection
  # in step 4).
  out$selected <- .ed_g_var(out, alpha = alpha)

  # 4) cell-level projection (standalone worker) --------------------------
  # ED rule: Delta loss_k = g_k * cumulative_exposure_k. Factor pair is
  # fit_intensity (loss-side g_k) + fit_cl on exposure (exposure projection).
  # No fit_ata / CL factor needed -- those are fit_cl's pair.
  grp <- .resolve_groups(x)

  # 4a) exposure projection: Mack CL on the exposure column
  exposure_cl <- fit_cl(
    x,
    method       = "mack",
    loss         = exposure,
    alpha        = 1,
    sigma_method = sigma_method,
    recent       = recent,
    regime       = out$regime
  )
  exposure_ata_fit <- structure(
    list(
      selected     = exposure_cl$selected,
      link         = exposure_cl$link,
      data         = exposure_cl$data,
      method       = "mack",
      alpha        = 1,
      sigma_method = sigma_method,
      maturity     = NULL
    ),
    class = "ATAFit"
  )

  # 4b) expand grid (joins exposure_proj from exposure_ata_fit)
  full <- .expand_grid(
    triangle         = x,
    ed_fit           = out,
    exposure_ata_fit = exposure_ata_fit,
    loss             = loss,
    exposure         = exposure
  )

  # 4c) join ED factors (g_sel, g_sigma2, g_var)
  has_seg <- "segment_id" %in% names(out$selected) &&
             "segment_id" %in% names(full)
  ed_cols <- c(grp, "ata_from",
               if (has_seg) "segment_id",
               "g_sel", "sigma2", "g_var")
  ed_sel  <- out$selected[, .SD, .SDcols = ed_cols]
  data.table::setnames(ed_sel, "ata_from", "dev")
  data.table::setnames(ed_sel, "sigma2", "g_sigma2")
  full <- ed_sel[full, on = c(grp, "dev", if (has_seg) "segment_id")]

  # 4d) last_obs per cohort
  full[, ("last_obs") := {
    idx <- which(is.finite(loss_obs))
    if (length(idx)) max(idx) else 0L
  }, by = c(grp, "cohort")]

  # 4e) loss point projection (ED-only, no maturity switch)
  full[, ("loss_proj") := .ed_proj(
    loss_obs      = loss_obs,
    exposure_proj = exposure_proj,
    g_sel         = g_sel
  ), by = c(grp, "cohort")]

  # 4f) loss variance (ED additive recursion)
  full[, `:=`(
    loss_proc_se2  = .ed_proc_var(
      exposure_proj = exposure_proj,
      g_sigma2      = g_sigma2,
      last_obs      = last_obs[1L],
      alpha         = alpha
    ),
    loss_param_se2 = .ed_param_var(
      exposure_proj = exposure_proj,
      g_var         = g_var,
      last_obs      = last_obs[1L]
    )
  ), by = c(grp, "cohort")]

  full[, ("loss_total_se2") := loss_proc_se2 + loss_param_se2]
  full[, `:=`(
    loss_proc_se  = sqrt(loss_proc_se2),
    loss_param_se = sqrt(loss_param_se2),
    loss_total_se = sqrt(loss_total_se2)
  )]
  full[, ("loss_total_cv") := data.table::fifelse(
    is.finite(loss_proj) & loss_proj != 0,
    loss_total_se / abs(loss_proj), NA_real_
  )]

  # 4g) drop intermediate factor columns
  full[, c("g_sel", "g_sigma2", "g_var", "last_obs") := NULL]

  # 4h) incremental projections (loss + exposure)
  full[, ("incr_loss_proj") := loss_proj -
         data.table::shift(loss_proj, 1L, fill = 0),
       by = c(grp, "cohort")]
  full[, ("incr_exposure_proj") := exposure_proj -
         data.table::shift(exposure_proj, 1L, fill = 0),
       by = c(grp, "cohort")]

  out$full <- full

  # 5) proj: NA out observed cells (mirrors CLFit$proj convention) --------
  proj <- data.table::copy(full)
  na_cols <- c(
    "loss_proj",     "incr_loss_proj",
    "exposure_proj", "incr_exposure_proj",
    "loss_proc_se2", "loss_param_se2", "loss_total_se2",
    "loss_proc_se",  "loss_param_se",  "loss_total_se",
    "loss_total_cv"
  )
  na_cols <- intersect(na_cols, names(proj))
  proj[is_observed == TRUE, (na_cols) := NA_real_]
  out$proj <- proj

  # 6) cohort-level reserve summary (mirrors CLFit$summary) ---------------
  out <- .ed_summary(out)

  # 7) bootstrap overlay (optional, mirrors fit_cl pattern) ---------------
  # When bootstrap is non-NULL / non-FALSE, replace projected-cell SE/CI
  # with bootstrap-derived values. Supports loss = "loss" / "exposure";
  # custom column names fall back to analytical with a warning.
  if (!is.null(bootstrap) &&
      !(is.logical(bootstrap) && length(bootstrap) == 1L &&
        isFALSE(bootstrap))) {
    if (loss %in% c("loss", "exposure")) {
      out <- .lossfit_bootstrap(
        fit        = out,
        triangle   = x,
        bootstrap  = bootstrap,
        B          = B,
        seed       = seed,
        alpha      = alpha,
        conf_level = conf_level,
        target     = loss
      )
    } else {
      warning("Bootstrap is supported for loss = 'loss' or 'exposure' only ",
              "(got '", loss, "'). Falling back to analytical SE.",
              call. = FALSE)
      out$ci_type   <- "analytical"
      out$bootstrap <- NULL
    }
  } else {
    out$ci_type   <- "analytical"
    out$bootstrap <- NULL
  }

  out
}


# ED projection helpers -----------------------------------------------------

#' ED point projection for a single cohort
#'
#' Cumulative loss recursion: `loss_{k+1} = loss_k + g_k * exposure_k`.
#'
#' @keywords internal
.ed_proj <- function(loss_obs, exposure_proj, g_sel) {
  n        <- length(loss_obs)
  last_obs <- max(which(is.finite(loss_obs)), 0L)
  if (last_obs == 0L || last_obs == n) return(loss_obs)

  v <- loss_obs
  for (i in seq(last_obs + 1L, n)) {
    k      <- i - 1L
    v_prev <- v[i - 1L]
    if (!is.finite(v_prev)) next
    g_now <- g_sel[k]
    e_now <- exposure_proj[k]
    if (is.finite(g_now) && is.finite(e_now)) {
      v[i] <- v_prev + g_now * e_now
    }
  }
  v
}


#' ED process variance for a single cohort
#'
#' Additive recursion: `proc_{k+1} = proc_k + sigma^2_{g,k} * (exposure_k)^alpha`.
#'
#' @keywords internal
.ed_proc_var <- function(exposure_proj, g_sigma2, last_obs, alpha = 1) {
  n    <- length(exposure_proj)
  proc <- numeric(n)
  if (last_obs >= n) return(proc)

  for (i in seq(last_obs + 1L, n)) {
    k  <- i - 1L
    s2 <- g_sigma2[k]
    e  <- exposure_proj[k]
    proc[i] <- proc[i - 1L]
    if (is.finite(s2) && is.finite(e) && e > 0) {
      proc[i] <- proc[i] + s2 * e^alpha
    }
  }
  proc
}


#' ED parameter variance for a single cohort
#'
#' Additive recursion: `param_{k+1} = param_k + (exposure_k)^2 * Var(g_k)`.
#'
#' @keywords internal
.ed_param_var <- function(exposure_proj, g_var, last_obs) {
  n     <- length(exposure_proj)
  param <- numeric(n)
  if (last_obs >= n) return(param)

  for (i in seq(last_obs + 1L, n)) {
    k  <- i - 1L
    gv <- g_var[k]
    e  <- exposure_proj[k]
    param[i] <- param[i - 1L]
    if (is.finite(gv) && is.finite(e)) {
      param[i] <- param[i] + e^2 * gv
    }
  }
  param
}

#' Cohort-level reserve summary for an `EDFit`
#'
#' @description
#' Internal helper that derives the per-cohort `latest` / `loss_ult` /
#' `reserve` / process / parameter / total SE table from `x$full` and
#' stores it on `x$summary`. Mirrors [.cl_summary()] for cross-paradigm
#' slot symmetry: both `CLFit$summary` and `EDFit$summary` carry the same
#' columns, so downstream consumers (`summary.CLFit()`, future
#' `summary.EDFit()` reserve view, `fit_ratio()` composition, etc.) read
#' from a uniform layout.
#'
#' @param x An object of class `"EDFit"` with a populated `$full` slot.
#'
#' @return The input `x` with `$summary` filled.
#'
#' @keywords internal
.ed_summary <- function(x) {

  .assert_class(x, "EDFit")

  grp      <- x$groups
  if (is.null(grp)) grp <- character(0)
  loss_col <- x$loss
  full     <- x$full
  is_ratio <- isTRUE(loss_col == "ratio")

  latest_obs <- full[is_observed == TRUE, .SD[.N], by = c(grp, "cohort")]
  ult        <- full[, .SD[.N],           by = c(grp, "cohort")]
  agg <- latest_obs[ult, on = c(grp, "cohort")]

  ult_col <- paste0(loss_col, "_ult")
  agg[, `:=`(
    latest  = loss_proj,
    reserve = if (is_ratio) NA_real_ else i.loss_proj - loss_proj
  )]
  agg[, (ult_col) := i.loss_proj]

  agg[, `:=`(
    loss_proc_se  = i.loss_proc_se,
    loss_param_se = i.loss_param_se,
    loss_total_se = i.loss_total_se,
    loss_total_cv = data.table::fifelse(
      is.finite(i.loss_proj) & i.loss_proj != 0,
      i.loss_total_se / i.loss_proj, NA_real_
    )
  )]
  out_cols <- c(grp, "cohort",
                "latest", ult_col, "reserve",
                "loss_proc_se", "loss_param_se",
                "loss_total_se", "loss_total_cv")

  x$summary <- agg[, .SD, .SDcols = out_cols]
  x
}


#' Summary method for `EDFit`
#'
#' @description
#' Returns the factor-level `EDSummary` carried by the fit, i.e. one row
#' per development link with fitted intensity `g`, standard error, and
#' diagnostic statistics.
#'
#' @param object An object of class `"EDFit"`.
#' @param ... Unused.
#'
#' @return A `data.table` of class `"EDSummary"`.
#'
#' @method summary EDFit
#' @export
summary.EDFit <- function(object, ...) {
  object$factor
}


#' Print an `EDFit` object
#'
#' @param x An object of class `"EDFit"`.
#' @param ... Unused.
#'
#' @method print EDFit
#' @export
print.EDFit <- function(x, ...) {

  grp <- .resolve_groups(x$link)

  cat("<EDFit>\n")
  cat("method      :", x$method,                  "\n")
  cat("loss        :", attr(x$link, "loss"),      "\n")
  cat("exposure    :", attr(x$link, "exposure"),  "\n")
  cat("alpha       :", x$alpha,                   "\n")
  cat("sigma_method:", x$sigma_method,              "\n")
  cat("recent      :",
      if (!is.null(x$recent)) x$recent else "all", "\n")
  cat("regime      :")
  if (is.null(x$regime)) {
    cat(" none\n")
  } else if (inherits(x$regime, "Regime")) {
    cat("\n"); print(x$regime)
  } else {
    cat(" ", format(x$regime), "\n", sep = "")
  }

  if (length(grp)) {
    cat("groups      :", paste(grp, collapse = ", "), "\n")
    cat("n_groups    :",
        nrow(unique(x$factor[, grp, with = FALSE])), "\n")
  } else {
    cat("groups      : none\n")
  }

  cat("links       :", nrow(x$factor), "\n")

  invisible(x)
}


# ____________________________________ ------------------------------------

# Internal helpers --------------------------------------------------------

#' Estimate ED intensity via weighted least squares
#'
#' @description
#' Internal helper that fits one no-intercept weighted linear model per
#' development link:
#'
#' \deqn{\Delta C^L_{i,k+1} = g_k \cdot C^P_{i,k} + \varepsilon_{i,k}}
#'
#' Weights are proportional to \eqn{1 / (C^P_{i,k})^{2 - \alpha}},
#' corresponding to the variance assumption
#' \eqn{\mathrm{Var}(\Delta C^L_{i,k+1}) \propto (C^P_{i,k})^{\alpha}}.
#'
#' @keywords internal
.lm_ed <- function(x,
                   alpha = 1,
                   na_rm = TRUE,
                   tol   = 1e-12) {

  .assert_class(x, "Link")

  # Suppress R CMD check NOTEs for `data.table` temp columns referenced
  # bare inside `j` expressions later in this function.
  .reg_w <- NULL

  if (is.null(attr(x, "exposure")))
    stop("`.lm_ed()` requires a Link built with `exposure`.",
         call. = FALSE)

  if (!is.numeric(alpha) || length(alpha) != 1L || is.na(alpha))
    stop("`alpha` must be a single non-missing numeric value.", call. = FALSE)

  if (!is.logical(na_rm) || length(na_rm) != 1L || is.na(na_rm))
    stop("`na_rm` must be a single non-missing logical value.", call. = FALSE)

  if (!is.numeric(tol) || length(tol) != 1L || is.na(tol) || tol < 0)
    stop("`tol` must be a single non-negative numeric value.", call. = FALSE)

  grp <- .resolve_groups(x)

  dt <- .copy_dt(x)

  # 1) drop invalid rows
  if (na_rm) {
    dt <- dt[is.finite(exposure_from) & is.finite(loss_delta) &
               exposure_from > 0]
  }

  # 2) compute WLS weight
  # Var(loss_delta) ~ exposure_from^alpha
  # => WLS weight = 1 / exposure_from^(2 - alpha)
  delta <- 2 - alpha
  dt[, (".reg_w") := 1 / exposure_from^delta]
  dt[, ("ata_link") := sprintf("%s-%s", ata_from, ata_to)]

  has_seg <- "segment_id" %in% names(dt)
  by_cols <- c(grp, "ata_from", "ata_to", "ata_link",
               if (has_seg) "segment_id")

  # 3) fit one model per link
  res <- dt[, {
    if (.N == 1L) {
      data.table::data.table(
        g         = loss_delta[1L] / exposure_from[1L],
        g_se      = NA_real_,
        sigma     = NA_real_,
        n_cohorts = 1L
      )
    } else {
      fit <- tryCatch(
        stats::lm(loss_delta ~ exposure_from + 0, weights = .reg_w),
        error = function(e) NULL
      )

      if (is.null(fit)) {
        data.table::data.table(
          g = NA_real_, g_se = NA_real_, sigma = NA_real_, n_cohorts = .N
        )
      } else {
        smr <- suppressWarnings(summary(fit))

        g_val     <- unname(stats::coef(fit)[1L])
        g_se_val  <- unname(smr$coef[1L, "Std. Error"])
        sigma_val <- unname(smr$sigma)

        if (is.finite(g_se_val)  && abs(g_se_val)  < tol) g_se_val  <- 0
        if (is.finite(sigma_val) && abs(sigma_val) < tol) sigma_val <- 0

        data.table::data.table(
          g         = g_val,
          g_se      = g_se_val,
          sigma     = sigma_val,
          n_cohorts = .N
        )
      }
    }
  }, keyby = by_cols]

  # 4) compute rse = g_se / |g|
  data.table::set(
    res,
    j     = "rse",
    value = data.table::fifelse(
      is.finite(res$g_se) & is.finite(res$g) & res$g != 0,
      res$g_se / abs(res$g),
      NA_real_
    )
  )

  data.table::setcolorder(res, "rse", before = "sigma")

  res
}



#' Compute ED intensity variance for each development link
#'
#' @description
#' Internal helper computing \eqn{\mathrm{Var}(\hat{g}_k) = \sigma^2_k / W_k}
#' where \eqn{W_k = \sum_i (C^P_{i,k})^{2 - \alpha}}. This is the
#' Buehlmann-Straub (1970) volume-weighted variance applied to the ED
#' intensity \eqn{g_k = \sum_i \Delta L_{i,k} / \sum_i P_{i,k-1}}.
#'
#' Paradigm pairing: the package keeps two natural analytical variance
#' helpers, one per paradigm-target pair: [.mack_f_var()] (CL / Mack 1993
#' applied to f-factor) and `.ed_g_var()` (ED / Buehlmann-Straub 1970
#' applied to g-intensity). The cross-paradigm pairs (`.mack_g_var`,
#' `.bs_f_var`) are algebraically derivable via \eqn{g_k = f_k - 1}
#' (and therefore \eqn{\sigma^2_g = \sigma^2_f}), so are intentionally
#' not provided as separate functions to avoid suggesting paradigm
#' mismatch is encouraged in user code.
#'
#' Conceptually a *factor-level* helper (operates on per-link `$link`
#' and `$selected` slots), parallel to `.mack_f_var(ata_fit: ATAFit)`.
#' Accepts either \code{"IntensityFit"} (the factor-level diagnostic for
#' ED, sibling of \code{"ATAFit"}) or \code{"EDFit"} (projection-level,
#' which exposes the same factor-level slots as a superset). The
#' \code{"IntensityFit"} path is the conceptually clean entry point for
#' factor-level callers; \code{"EDFit"} is accepted for projection-level
#' callers that already hold the fit object.
#'
#' Used by [fit_ed()] when `method = "mack"` and by [fit_ratio()] for the
#' ED component.
#'
#' @param x An object of class `"IntensityFit"` or `"EDFit"`. Either
#'   exposes the `$link` and `$selected` slots used here.
#' @param alpha Numeric scalar. Default is `1`.
#'
#' @return The `$selected` `data.table` with `g_var` column.
#'
#' @references
#' Buehlmann, H. and Straub, E. (1970). Glaubwuerdigkeit fuer
#' Schadensaetze (Credibility for Loss Ratios). *Bulletin of the Swiss
#' Association of Actuaries*, 70, 111-133.
#'
#' Mack, T. (1993). Distribution-free calculation of the standard error
#' of chain ladder reserve estimates. *ASTIN Bulletin*, 23(2), 213-225.
#'
#' @keywords internal
.ed_g_var <- function(x, alpha = 1) {

  if (!inherits(x, c("IntensityFit", "EDFit")))
    stop("`x` must be an `IntensityFit` or `EDFit` object.",
         call. = FALSE)

  # Suppress R CMD check NOTEs for `data.table` temp columns referenced
  # bare inside `j` expressions later in this function.
  .denom <- NULL

  grp <- .resolve_groups(x$link)

  ed_long <- .copy_dt(x$link)
  sel     <- data.table::copy(x$selected)

  if (!"sigma2" %in% names(sel))
    stop("`x$selected` must contain a `sigma2` column.",
         call. = FALSE)

  ed_valid <- ed_long[is.finite(exposure_from) &
                        is.finite(loss_delta) &
                        exposure_from > 0]

  has_seg <- "segment_id" %in% names(ed_valid) &&
             "segment_id" %in% names(sel)
  by_cols <- c(grp, "ata_from", if (has_seg) "segment_id")

  link_weights <- ed_valid[,
                       .(.denom = sum(exposure_from^(2 - alpha), na.rm = TRUE)),
                       by = by_cols
  ]

  sel <- link_weights[sel, on = by_cols]

  sel[, ("g_var") := data.table::fifelse(
    is.finite(sigma2) & is.finite(.denom) & .denom > 0,
    sigma2 / .denom,
    NA_real_
  )]

  sel[, (".denom") := NULL]
  sel[]
}

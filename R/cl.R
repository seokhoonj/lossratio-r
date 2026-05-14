#' Fit chain ladder projection from a `Triangle` object
#'
#' @description
#' Fit a Mack (1993) chain ladder projection from an object of class
#' `"Triangle"`. The function works on long-form cumulative data and does
#' not require a complete triangle. Age-to-age factors are estimated
#' through [as_link()] and [fit_ata()], then applied recursively. The
#' point forecast follows the standard recursion, and prediction
#' uncertainty is decomposed into process variance and parameter variance.
#'
#' When `weight` is supplied (e.g. `"prem"`), age-to-age factors and
#' their variance are estimated using the supplied WLS weights.
#'
#' @param x An object of class `"Triangle"`.
#' @param method One of `"mack"`. Default is `"mack"`. The argument is
#'   retained for future extensibility.
#' @param target A single cumulative target variable (column to project).
#'   Typical choices are `"loss"`, `"prem"`, or `"lr"`.
#' @param weight An optional column name passed to [as_link()] as
#'   the WLS weight variable. Typically `"prem"` when `target = "lr"`.
#'   Default is `NULL`.
#' @param alpha Numeric scalar controlling the variance structure in
#'   [fit_ata()]. Default is `1`.
#' @param sigma_method Sigma extrapolation method passed to [fit_ata()].
#'   One of `"locf"` (default), `"min_last2"`, or `"loglinear"`.
#' @param recent Optional positive integer. When supplied, only the most
#'   recent `recent` periods are used for factor estimation. Default is
#'   `NULL` (use all periods).
#' @param regime Optional regime specification for cohort cutoff. Accepts:
#'   `NULL` (default — no filter), a `Regime` object (from [detect_regime()]
#'   or `regime_at()`), the string `"auto"` (internal
#'   `detect_regime(tri, target = "lr")` call), or a function
#'   `function(tri) -> Regime` for deferred custom-config detection. When
#'   supplied, cohorts strictly before the resolved change date are excluded
#'   from factor estimation.
#' @param maturity Maturity input forwarded to [fit_ata()]. Accepts four
#'   forms:
#'   \describe{
#'     \item{`NULL` (default)}{No maturity filtering.}
#'     \item{`Maturity` object}{Pre-built (e.g. from [detect_maturity()]
#'       or [maturity_at()]) — used as-is.}
#'     \item{`"auto"`}{Internal [detect_maturity()] call with defaults
#'       (target inferred from `target`).}
#'     \item{function `function(tri) -> Maturity`}{Lazy spec, typically
#'       built with [maturity_spec()], invoked on the triangle at fit
#'       time (leakage-safe for [backtest()]).}
#'   }
#' @param tail Logical or numeric. If `FALSE`, no tail factor is applied.
#'   If `TRUE`, a log-linear tail factor is estimated from selected factors.
#'   If numeric, the supplied value is used as the tail factor.
#'
#' @return An object of class `"CLFit"` containing:
#'   \describe{
#'     \item{`call`}{The matched call.}
#'     \item{`data`}{The input `"Triangle"` object.}
#'     \item{`method`}{The method used (`"mack"`).}
#'     \item{`groups`}{Character vector of grouping variable names.}
#'     \item{`cohort`}{Character scalar of period variable name.}
#'     \item{`dev`}{Character scalar of development variable name.}
#'     \item{`target`}{Character scalar of target variable name.}
#'     \item{`full`}{`data.table` with observed and projected values,
#'       including process/parameter SE and CV columns.}
#'     \item{`proj`}{`data.table` identical to `full` with observed cells
#'       set to `NA`.}
#'     \item{`link`}{The `"Link"` object produced by [as_link()].}
#'     \item{`summary`}{Cohort-level summary with latest, ultimate,
#'       reserve, and Mack standard errors.}
#'     \item{`selected`}{`data.table` of selected factors used for
#'       projection.}
#'     \item{`factor`}{`data.table` of fitted factors from [fit_ata()].}
#'     \item{`maturity`}{Maturity diagnostics from [detect_maturity()],
#'       or `NULL` when maturity filtering was not applied.}
#'     \item{`alpha`}{Value of `alpha` used.}
#'     \item{`sigma_method`}{Sigma extrapolation method.}
#'     \item{`weight`}{Weight variable name used, or `NULL`.}
#'     \item{`recent`}{Number of recent periods used, or `NULL`.}
#'     \item{`regime`}{Resolved `Regime` object, or `NULL`.}
#'     \item{`use_maturity`}{Logical; whether maturity filtering was applied.}
#'     \item{`tail`}{Tail factor argument supplied by the user.}
#'     \item{`tail_factor`}{Numeric tail factor applied.}
#'   }
#'
#' @seealso [fit_ata()], [fit_lr()]
#'
#' @examples
#' \dontrun{
#' data(experience)
#' tri <- as_triangle(
#'   experience[coverage == "SUR"],
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "incr_loss",
#'   premium  = "incr_prem"
#' )
#'
#' # Mack chain ladder with process / parameter standard errors
#' cl_mack <- fit_cl(tri, target = "loss", method = "mack")
#' summary(cl_mack)
#' plot(cl_mack)
#'
#' # WLS factors for lr (loss ratio) using prem as the weight
#' cl_clr <- fit_cl(tri, target = "lr", weight = "prem")
#' }
#'
#' @export
fit_cl <- function(x,
                   method       = c("mack"),
                   target       = "loss",
                   weight       = NULL,
                   alpha        = 1,
                   sigma_method = c("locf", "min_last2", "loglinear"),
                   recent       = NULL,
                   regime       = NULL,
                   maturity     = NULL,
                   tail         = FALSE) {

  .assert_triangle_input(x, "fit_cl()")
  method       <- match.arg(method)
  sigma_method <- match.arg(sigma_method)

  if (!is.numeric(alpha) || length(alpha) != 1L ||
      is.na(alpha) || !is.finite(alpha))
    stop("`alpha` must be a single finite numeric value.", call. = FALSE)

  # resolve regime dispatch (NULL / Regime / "auto" / function) to a
  # `Regime` object (or NULL) before forwarding to `fit_ata()`.
  regime <- .resolve_regime(regime, x)

  # 1) resolve variable names -------------------------------------------
  if (!is.character(target) || length(target) != 1L)
    stop("`target` must be a single column name (character).",
         call. = FALSE)
  if (!(target %in% names(x)))
    stop(sprintf("`target` column '%s' not found in `x`.", target),
         call. = FALSE)
  tgt <- target

  grp <- attr(x, "groups")
  coh <- attr(x, "cohort")
  dev <- attr(x, "dev")

  if (is.null(grp)) grp <- character(0)

  if (length(coh) != 1L)
    stop("`x` must contain exactly one `cohort`.", call. = FALSE)
  if (length(dev) != 1L)
    stop("`x` must contain exactly one `dev`.", call. = FALSE)

  # 2) validate weight --------------------------------------------------
  use_external_weight <- !is.null(weight)

  if (use_external_weight) {
    if (!is.character(weight) || length(weight) != 1L)
      stop("`weight` must be a single column name (character).",
           call. = FALSE)
    if (!(weight %in% names(x)))
      stop(sprintf("`weight` column '%s' not found in `x`.", weight),
           call. = FALSE)
    wt <- weight
    if (wt == tgt)
      stop("`weight` must differ from `target`.", call. = FALSE)
  }

  # 3) estimate ata factors (fit_ata builds the Link internally) -------
  ata_fit <- fit_ata(
    x,
    target       = tgt,
    weight       = if (use_external_weight) wt else NULL,
    alpha        = alpha,
    sigma_method = sigma_method,
    recent       = recent,
    regime       = regime,
    maturity     = maturity
  )

  # 4) compute factor variance ------------------------------------------
  ata_fit$selected <- .mack_f_var(
    ata_fit = ata_fit,
    alpha   = alpha
  )

  # 5) compute tail factor ----------------------------------------------
  tail_factor <- .compute_tail_factor(ata_fit$selected, tail)

  # 6) expand triangle to full cohort-by-development-period grid -----------
  full <- .expand_triangle_grid(
    triangle = x,
    ata_fit  = ata_fit,
    target   = tgt
  )

  # 7) join factor columns onto full grid -------------------------------
  has_seg <- "segment_id" %in% names(ata_fit$selected) &&
             "segment_id" %in% names(full)
  factor_cols <- c(grp, "ata_from",
                   if (has_seg) "segment_id",
                   "f_selected", "sigma2", "f_var")
  sel <- ata_fit$selected[, .SD, .SDcols = factor_cols]
  data.table::setnames(sel, "ata_from", "dev")
  full <- sel[full, on = c(grp, "dev", if (has_seg) "segment_id")]

  # 8) join RP scale for process variance when weight is used ---------
  if (use_external_weight) {
    raw <- .copy_dt(x)
    wt_obs <- raw[
      , .(wt_obs = .SD[[wt]]),
      by = c(grp, "cohort", "dev")
    ]
    full <- wt_obs[full, on = c(grp, "cohort", "dev")]
  } else {
    full[, ("wt_obs") := NA_real_]
  }

  # compute last observed index per cohort
  full[, ("last_obs") := {
    idx <- which(is.finite(target_obs))
    if (length(idx)) max(idx) else 0L
  }, by = c(grp, "cohort")]

  # 9) point projection -------------------------------------------------
  full[, ("target_proj") := .cl_proj(
    target_obs = target_obs,
    f_selected = f_selected
  ), by = c(grp, "cohort")]

  # 10) incremental target projection -----------------------------------
  full[, ("incr_target_proj") := target_proj -
         data.table::shift(target_proj, 1L, fill = 0),
       by = c(grp, "cohort")]

  # 11) variance --------------------------------------------------------
  full[, `:=`(
    target_proc_se2  = .mack_proc_var(
      target_proj = target_proj,
      f_selected  = f_selected,
      sigma2      = sigma2,
      last_obs    = last_obs[1L],
      alpha       = alpha,
      scale       = if (use_external_weight) wt_obs[last_obs[1L]] else NULL
    ),
    target_param_se2 = .mack_param_var(
      target_proj = target_proj,
      f_selected  = f_selected,
      f_var       = f_var,
      last_obs    = last_obs[1L]
    )
  ), by = c(grp, "cohort")]

  full[, ("target_total_se2") := target_proc_se2 + target_param_se2]

  full[, `:=`(
    target_proc_se  = sqrt(target_proc_se2),
    target_param_se = sqrt(target_param_se2),
    target_total_se = sqrt(target_total_se2)
  )]

  full[, `:=`(
    target_proc_cv  = data.table::fifelse(
      is.finite(target_proj) & target_proj != 0,
      target_proc_se / target_proj, NA_real_
    ),
    target_param_cv = data.table::fifelse(
      is.finite(target_proj) & target_proj != 0,
      target_param_se / target_proj, NA_real_
    ),
    target_total_cv = data.table::fifelse(
      is.finite(target_proj) & target_proj != 0,
      target_total_se / target_proj, NA_real_
    )
  )]

  # 12) drop intermediate columns ---------------------------------------
  full[, `:=`(
    f_selected = NULL,
    sigma2     = NULL,
    f_var      = NULL,
    wt_obs     = NULL,
    last_obs   = NULL
  )]

  # 13) proj: NA out observed cells -------------------------------------
  proj <- data.table::copy(full)
  na_cols <- c(
    "target_proj", "incr_target_proj",
    "target_proc_se2", "target_param_se2", "target_total_se2",
    "target_proc_se",  "target_param_se",  "target_total_se",
    "target_proc_cv",  "target_param_cv",  "target_total_cv"
  )
  proj[is_observed == TRUE, (na_cols) := NA_real_]

  # 14) assemble output -------------------------------------------------
  out <- list(
    call         = match.call(),
    data         = x,
    method       = method,
    groups       = grp,
    cohort       = coh,
    dev          = dev,
    target       = tgt,
    full         = full,
    proj         = proj,
    link         = ata_fit$link,
    summary      = NULL,
    factor       = ata_fit$factor,
    selected     = ata_fit$selected,
    maturity     = ata_fit$maturity,
    alpha        = alpha,
    sigma_method = sigma_method,
    weight       = if (use_external_weight) wt else NULL,
    recent       = recent,
    regime       = regime,
    use_maturity = ata_fit$use_maturity,
    tail         = tail,
    tail_factor  = tail_factor
  )

  class(out) <- "CLFit"

  # 15) apply tail factor (scales SE columns) ---------------------------
  if (is.finite(tail_factor) && tail_factor > 1) {
    out <- .cl_tail_factor(out)
  }

  # 16) compute cohort-level summary -------------------------------------
  out <- .cl_summary(out)

  out
}


#' Print a `CLFit` object
#'
#' @param x An object of class `"CLFit"`.
#' @param ... Unused.
#'
#' @method print CLFit
#' @export
print.CLFit <- function(x, ...) {

  grp <- x$groups
  if (is.null(grp)) grp <- character(0)

  cat("<CLFit>\n")
  cat("method      :", x$method, "\n")
  cat("target      :", x$target, "\n")
  cat("weight      :",
      if (!is.null(x$weight)) x$weight else "none", "\n")
  cat("alpha       :", x$alpha, "\n")
  cat("sigma_method:", x$sigma_method, "\n")
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
  cat("use_maturity:", x$use_maturity, "\n")
  cat("tail_factor :", x$tail_factor, "\n")

  if (length(grp)) {
    cat("groups      :", paste(grp, collapse = ", "), "\n")
  } else {
    cat("groups      : none\n")
  }

  if (!is.null(x$summary)) {
    cat("periods     :", nrow(x$summary), "\n")
  } else {
    cat("periods     :",
        nrow(unique(x$full[, "cohort", with = FALSE])), "\n")
  }

  invisible(x)
}


# ____________________________________ ------------------------------------

# Internal helpers --------------------------------------------------------

#' Compute chain ladder point projection for a single cohort
#'
#' @description
#' Internal helper that fills in the unobserved development path for a
#' single cohort by applying the selected age-to-age factors recursively:
#'
#' \deqn{\hat{C}_{i,k+1} = \hat{f}_k \cdot \hat{C}_{i,k}}
#'
#' Only cells beyond the last observed value are projected. Observed cells
#' are returned unchanged.
#'
#' @param target_obs Numeric vector of cumulative observed values for a
#'   single cohort, ordered by development period.
#' @param f_selected Numeric vector of selected development factors.
#'
#' @return A numeric vector of the same length as `target_obs` with
#'   unobserved cells filled by recursive chain ladder projection.
#'
#' @keywords internal
.cl_proj <- function(target_obs, f_selected) {

  n        <- length(target_obs)
  last_obs <- max(which(is.finite(target_obs)), 0L)

  if (last_obs == 0L || last_obs == n) return(target_obs)

  v <- target_obs

  for (i in seq(last_obs + 1L, n)) {
    f_now <- f_selected[i - 1L]
    if (is.finite(f_now) && is.finite(v[i - 1L])) {
      v[i] <- v[i - 1L] * f_now
    }
  }

  v
}


#' Expand a `Triangle` object to a full development grid
#'
#' @description
#' Internal helper that constructs a complete cohort-by-development-period grid
#' from an object of class `"Triangle"`, analogous to [base::expand.grid()].
#'
#' @keywords internal
.expand_triangle_grid <- function(triangle, ata_fit, target) {

  grp <- attr(triangle, "groups")

  if (is.null(grp)) grp <- character(0)

  raw <- .copy_dt(triangle)

  obs <- raw[
    , .(target_obs = .SD[[target]]),
    by = c(grp, "cohort", "dev")
  ]

  max_dev <- max(ata_fit$selected$ata_to, na.rm = TRUE)

  full <- unique(obs[, .SD, .SDcols = c(grp, "cohort")])
  full <- full[, .(dev = seq_len(max_dev)), by = c(grp, "cohort")]

  full <- obs[full, on = c(grp, "cohort", "dev")]
  data.table::setorderv(full, c(grp, "cohort", "dev"))

  full[, ("is_observed") := is.finite(target_obs)]

  # When ata_fit was fitted with segment_wise treatment, attach
  # segment_id to each grid row so factor join keys by segment.
  if ("segment_id" %in% names(ata_fit$selected)) {
    grp_dt <- if (length(grp)) full[, grp, with = FALSE] else NULL
    full[, ("segment_id") := .assign_segment(cohort, ata_fit$regime, grp_dt)]
  }

  full
}


#' Compute log-linear tail factor from selected ATA factors
#'
#' @keywords internal
.compute_tail_factor <- function(selected, tail) {

  tail_factor <- 1

  if (isTRUE(tail)) {
    f_vals <- selected[is.finite(f_selected), f_selected]

    if (length(f_vals) >= 3L && all(f_vals > 0, na.rm = TRUE)) {
      idx <- which(f_vals > 1)

      if (length(idx) >= 2L) {
        ff <- f_vals[idx]
        ii <- idx

        if (ff[length(ff) - 1L] * ff[length(ff)] > 1.0001) {
          tail_model  <- stats::lm(log(ff - 1) ~ ii)
          co          <- stats::coef(tail_model)
          future_i    <- seq.int(max(ii) + 1L, max(ii) + 100L)
          future_f    <- exp(co[1L] + future_i * co[2L]) + 1
          tail_factor <- prod(future_f)
          if (!is.finite(tail_factor) || tail_factor > 2) tail_factor <- 1
        }
      }
    }

  } else if (is.numeric(tail) && length(tail) == 1L && !is.na(tail)) {
    tail_factor <- tail
  }

  tail_factor
}


#' Compute Mack's factor variance for each development link
#'
#' @description
#' Internal helper computing:
#'
#' \deqn{\mathrm{Var}(\hat{f}_k) = \frac{\sigma^2_k}{W_k}}
#'
#' where \eqn{W_k = \sum_i w_{i,k} \cdot C_{i,k}^\alpha}. This is consistent
#' with the WLS weight \eqn{w_{i,k} / C_{i,k}^{2-\alpha}} used in `.lm_ata()`.
#'
#' Also used by [fit_lr()] for the CL component.
#'
#' @keywords internal
.mack_f_var <- function(ata_fit, alpha = 1) {

  .assert_class(ata_fit, "ATAFit")

  # Suppress R CMD check NOTEs for `data.table` temp columns referenced
  # bare inside `j` expressions later in this function.
  .wt <- .denom <- NULL

  grp <- attr(ata_fit$link, "groups")
  if (is.null(grp)) grp <- character(0)

  link_long <- .copy_dt(ata_fit$link)
  sel       <- data.table::copy(ata_fit$selected)

  if (!"sigma2" %in% names(sel))
    stop(
      "`ata_fit$selected` must contain a `sigma2` column. ",
      "Run `fit_ata()` first.",
      call. = FALSE
    )

  if ("weight" %in% names(link_long)) {
    link_long[, (".wt") := weight]
  } else {
    link_long[, (".wt") := 1]
  }

  link_long <- link_long[is.finite(.wt) & is.finite(target_to) & target_from > 0]

  has_seg <- "segment_id" %in% names(link_long) &&
             "segment_id" %in% names(sel)
  by_cols <- c(grp, "ata_from", if (has_seg) "segment_id")

  link_weights <- link_long[,
                       .(.denom = sum(.wt * target_from^alpha, na.rm = TRUE)),
                       by = by_cols
  ]

  sel <- link_weights[sel, on = by_cols]

  sel[, ("f_var") := data.table::fifelse(
    is.finite(sigma2) & is.finite(.denom) & .denom > 0,
    sigma2 / .denom,
    NA_real_
  )]

  sel[, (".denom") := NULL]

  sel[]
}


#' Compute Mack process variance for a single cohort
#'
#' @description
#' Internal helper computing:
#'
#' \deqn{
#'   \mathrm{proc}_{i,k+1} =
#'     f_k^2 \cdot \mathrm{proc}_{i,k} +
#'     \sigma^2_k \cdot \hat{C}_{i,k}^{\alpha}
#' }
#'
#' When `scale` is supplied, the increment is divided by `scale`.
#'
#' @keywords internal
.mack_proc_var <- function(target_proj,
                           f_selected,
                           sigma2,
                           last_obs,
                           alpha = 1,
                           scale = NULL) {

  n    <- length(target_proj)
  proc <- numeric(n)

  if (last_obs == n) return(proc)

  use_scale <- !is.null(scale) && is.finite(scale) && scale > 0

  for (i in seq(last_obs + 1L, n)) {
    f_now      <- f_selected[i - 1L]
    sigma2_now <- sigma2[i - 1L]
    v_prev     <- target_proj[i - 1L]

    if (!is.finite(f_now) || !is.finite(v_prev)) next

    proc_prev <- f_now^2 * proc[i - 1L]

    if (is.finite(sigma2_now)) {
      increment <- if (use_scale) {
        (sigma2_now / scale) * v_prev^alpha
      } else {
        sigma2_now * v_prev^alpha
      }
      proc[i] <- proc_prev + increment
    } else {
      proc[i] <- proc_prev
    }
  }

  proc
}


#' Compute Mack parameter variance for a single cohort
#'
#' @description
#' Internal helper computing:
#'
#' \deqn{
#'   \mathrm{param}_{i,k+1} =
#'     f_k^2 \cdot \mathrm{param}_{i,k} +
#'     \hat{C}_{i,k}^2 \cdot \mathrm{Var}(\hat{f}_k)
#' }
#'
#' @keywords internal
.mack_param_var <- function(target_proj,
                            f_selected,
                            f_var,
                            last_obs) {

  n     <- length(target_proj)
  param <- numeric(n)

  if (last_obs == n) return(param)

  for (i in seq(last_obs + 1L, n)) {
    f_now     <- f_selected[i - 1L]
    f_var_now <- f_var[i - 1L]
    v_prev    <- target_proj[i - 1L]

    if (!is.finite(f_now) || !is.finite(v_prev)) next

    param_prev <- f_now^2 * param[i - 1L]

    if (is.finite(f_var_now)) {
      param[i] <- param_prev + v_prev^2 * f_var_now
    } else {
      param[i] <- param_prev
    }
  }

  param
}


#' Apply tail factor to a Mack-fitted `CLFit` object
#'
#' @description
#' Internal helper scaling projected value and Mack variance components by
#' the tail factor for the last development period of each cohort,
#' appending `_tail` suffixed columns.
#'
#' @keywords internal
.cl_tail_factor <- function(x) {

  .assert_class(x, "CLFit")

  grp     <- x$groups
  coh     <- x$cohort
  dev     <- x$dev
  tail_factor <- x$tail_factor
  full        <- x$full

  latest <- full[, .SD[.N], by = c(grp, "cohort")]

  latest[, `:=`(
    target_tail           = target_proj         * tail_factor,
    target_proc_se2_tail  = target_proc_se2     * tail_factor^2,
    target_param_se2_tail = target_param_se2    * tail_factor^2,
    target_total_se2_tail = target_total_se2    * tail_factor^2
  )]

  latest[, `:=`(
    target_proc_se_tail  = sqrt(target_proc_se2_tail),
    target_param_se_tail = sqrt(target_param_se2_tail),
    target_total_se_tail = sqrt(target_total_se2_tail)
  )]

  latest[, `:=`(
    target_proc_cv_tail  = data.table::fifelse(
      is.finite(target_tail) & target_tail != 0,
      target_proc_se_tail / target_tail, NA_real_
    ),
    target_param_cv_tail = data.table::fifelse(
      is.finite(target_tail) & target_tail != 0,
      target_param_se_tail / target_tail, NA_real_
    ),
    target_total_cv_tail = data.table::fifelse(
      is.finite(target_tail) & target_tail != 0,
      target_total_se_tail / target_tail, NA_real_
    )
  )]

  x$full <- latest[full, on = c(grp, "cohort", "dev")]

  x
}


#' Summarise a `CLFit` object by cohort
#'
#' @description
#' Internal helper producing a one-row-per-cohort summary from the full
#' development grid. Contains latest observed, ultimate projection,
#' reserve, process/parameter standard errors, and coefficient of
#' variation.
#'
#' @keywords internal
.cl_summary <- function(x) {

  .assert_class(x, "CLFit")

  grp  <- x$groups
  coh  <- x$cohort
  tgt  <- x$target
  full     <- x$full
  is_ratio <- tgt == "lr"

  latest_obs <- full[is_observed == TRUE, .SD[.N], by = c(grp, "cohort")]
  ult        <- full[, .SD[.N],           by = c(grp, "cohort")]
  agg <- latest_obs[ult, on = c(grp, "cohort")]

  ult_col <- paste0(tgt, "_ult")
  agg[, `:=`(
    latest  = target_proj,
    reserve = if (is_ratio) NA_real_ else i.target_proj - target_proj
  )]
  agg[, (ult_col) := i.target_proj]

  agg[, `:=`(
    target_proc_se  = i.target_proc_se,
    target_param_se = i.target_param_se,
    target_total_se = i.target_total_se,
    target_total_cv = data.table::fifelse(
      is.finite(i.target_proj) & i.target_proj != 0,
      i.target_total_se / i.target_proj, NA_real_
    )
  )]
  out_cols <- c(grp, "cohort",
                "latest", ult_col, "reserve",
                "target_proc_se", "target_param_se",
                "target_total_se", "target_total_cv")

  x$summary <- agg[, .SD, .SDcols = out_cols]
  x
}


#' Summary method for `CLFit`
#'
#' @param object An object of class `"CLFit"`.
#' @param ... Unused.
#'
#' @return A `data.table` with one row per cohort.
#'
#' @method summary CLFit
#' @export
summary.CLFit <- function(object, ...) {
  object$summary
}

# Backtest --------------------------------------------------------------

#' Backtest a loss / prem / loss-ratio projection on existing data
#'
#' @description
#' Hold out the latest `holdout` calendar diagonals from the input
#' `Triangle`, refit a target-specific projection on the earlier
#' portion, project the held-out cells, and compare the projection
#' to the actual values that were withheld.
#'
#' The target is selected with `target`:
#'
#' * `target = "lr"` -- score the loss-ratio projection from
#'   `fit_lr()`.
#' * `target = "loss"` -- score the loss projection from `fit_loss()`.
#' * `target = "premium"` -- score the prem projection from
#'   `fit_premium()`.
#'
#' The A/E Error (`ae_err`) follows the standard actuarial A/E
#' convention and is computed cell-wise as
#' \deqn{ae\_err = \frac{value_{actual}}{value_{proj}} - 1}
#' so that positive values flag under-projection (the model
#' under-estimated; actual exceeded expected) and negative values
#' flag over-projection. Aggregated by development period
#' (`col_summary`) and by calendar diagonal (`diag_summary`).
#'
#' @param x A `"Triangle"` object (or a `"Backtest"` object for the S3
#'   `print()` method).
#' @param object A `"Backtest"` object. Used by the S3 `summary()` method.
#' @param holdout Integer. Number of latest calendar diagonals to mask
#'   before refitting. Default `6L`.
#' @param target Character scalar. Which projection to backtest. One
#'   of `"lr"` (default), `"loss"`, `"premium"`. Determines which
#'   fitter is called on the masked triangle and which column on `x`
#'   is treated as the held-out actual.
#' @param loss_method Method for the loss-side projection. Passed to
#'   `fit_lr()` / `fit_loss()` as their `method` argument. One of
#'   `"sa"`, `"ed"`, `"cl"`. Unused for `target = "premium"`.
#' @param premium_method Method for the prem-side projection.
#'   Passed to `fit_lr()` / `fit_loss()` / `fit_premium()`. One of
#'   `"cl"`, `"ed"`.
#' @param loss_alpha,premium_alpha Mack alpha for loss-side / prem-side
#'   chain-ladder estimation.
#' @param sigma_method Tail sigma extrapolation method. Forwarded to
#'   the underlying fitter.
#' @param recent Calendar-diagonal recency filter forwarded to the
#'   fitter.
#' @param loss_regime,premium_regime Regime spec for the loss / prem
#'   side. Each accepts one of four input types, dispatched by
#'   [`.resolve_regime()`]:
#'   \itemize{
#'     \item `NULL` (default) -- no regime filter.
#'     \item A `Regime` object (e.g. from [detect_regime()]) -- used as-is.
#'     \item The string `"auto"` -- runs `detect_regime()` on the
#'       **masked** triangle (leakage-safe; uses only data available at
#'       the simulated backtest cutoff).
#'     \item A function `function(tri) -> Regime` -- called on the
#'       masked triangle for the same leakage-safe reason.
#'   }
#'   `premium_regime` is resolved independently from `loss_regime`.
#' @param maturity Maturity input. Used only for `target = "lr"` and
#'   `target = "loss"` (stage-adaptive). Accepts one of four input
#'   types, dispatched by [`.resolve_maturity()`]:
#'   \itemize{
#'     \item `NULL` -- skip maturity filtering.
#'     \item A `Maturity` object (e.g. from [detect_maturity()] or
#'       [maturity_at()]) -- used as-is. Caller takes responsibility
#'       for any leakage in their pre-computation.
#'     \item The string `"auto"` (default) -- runs [detect_maturity()]
#'       on the **masked** triangle (last `holdout` calendar diagonals
#'       removed), avoiding look-ahead leakage.
#'     \item A function `function(tri) -> Maturity` (e.g. from
#'       [maturity_spec()]) -- called on the masked triangle for the
#'       same leakage-safe reason.
#'   }
#' @param se_method Standard-error composition for `fit_lr()`. Unused
#'   for `target = "loss"` / `target = "premium"`.
#' @param rho Loss-prem correlation used by `fit_lr()` delta
#'   method. Unused for `target = "loss"` / `target = "premium"`.
#' @param conf_level Confidence level for `fit_lr()` / `fit_loss()`
#'   intervals. Unused for `target = "premium"`.
#' @param bootstrap,B,seed Bootstrap controls forwarded to `fit_lr()`.
#'   `bootstrap = NULL` (default) defers to `fit_lr`'s method-dependent
#'   resolution (bootstrap for `"sa"`/`"ed"`, analytical for `"cl"`).
#'   Unused for `target = "loss"` / `target = "premium"`.
#' @param ... Additional arguments passed to the underlying fitter.
#'
#' @return An object of class `"Backtest"` with components:
#'   \describe{
#'     \item{`call`}{Matched call.}
#'     \item{`data`}{Original `Triangle`.}
#'     \item{`masked`}{Triangle used for fitting (with held-out cells
#'       removed).}
#'     \item{`fit`}{The fit object returned by the target-specific
#'       fitter.}
#'     \item{`ae_err`}{`data.table` of held-out cells with columns
#'       `(group, cohort, dev, actual, expected, aeg, ae_err,
#'       incr_actual, incr_expected, incr_aeg, incr_ae_err,
#'       cal_idx)`. `aeg = actual - expected` (signed
#'       error in target units); `ae_err = actual / expected - 1`
#'       (relative error). `incr_` siblings are the same metrics
#'       on the incremental view.}
#'     \item{`col_summary`}{Per-`dev` aggregate A/E Error and AEG
#'       (mean / median / weighted) with `incr_` variants and `n`.}
#'     \item{`diag_summary`}{Per-calendar-diagonal aggregate A/E
#'       Error and AEG (same columns as `col_summary`, keyed by
#'       `cal_idx`).}
#'     \item{`target`, `holdout`, `dispatcher`}{Call metadata.}
#'     \item{`groups`, `cohort`, `dev`}{Variable name relays
#'       from `x`.}
#'   }
#'
#' @seealso [fit_lr()], [fit_loss()], [fit_premium()], [plot.Backtest()]
#'
#' @examples
#' \dontrun{
#' data(experience)
#' tri <- as_triangle(
#'   experience,
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "incr_loss",
#'   premium  = "incr_prem"
#' )
#'
#' bt_lr      <- backtest(tri, holdout = 6L, target = "lr")
#' bt_loss    <- backtest(tri, holdout = 6L, target = "loss")
#' bt_prem <- backtest(tri, holdout = 6L, target = "premium")
#'
#' print(bt_lr)
#' summary(bt_lr)
#' plot(bt_lr)
#' }
#'
#' @export
backtest <- function(x,
                     holdout        = 6L,
                     target         = c("lr", "loss", "premium"),
                     loss_method    = c("sa", "ed", "cl"),
                     premium_method = c("cl", "ed"),
                     loss_alpha     = 1,
                     premium_alpha  = 1,
                     sigma_method   = c("locf", "min_last2", "loglinear"),
                     recent         = NULL,
                     loss_regime    = NULL,
                     premium_regime = NULL,
                     maturity       = "auto",
                     se_method      = c("fixed", "delta"),
                     rho            = 0.95,
                     conf_level     = 0.95,
                     bootstrap      = NULL,
                     B              = 999,
                     seed           = NULL,
                     ...) {

  .assert_triangle_input(x, "backtest()")

  # Suppress R CMD check NOTEs for `data.table` temp columns referenced
  # bare inside `j` expressions later in this function.
  .coh_rank <- .cal_idx <- .max_cal <- .is_held_out <- NULL

  target         <- match.arg(target)
  loss_method    <- match.arg(loss_method)
  premium_method <- match.arg(premium_method)
  sigma_method   <- match.arg(sigma_method)
  se_method      <- match.arg(se_method)

  if (!is.numeric(holdout) || length(holdout) != 1L ||
      is.na(holdout) || holdout < 1L)
    stop("`holdout` must be a single positive integer.", call. = FALSE)
  holdout <- as.integer(holdout)

  # Map full-word target arg -> bare column key for fit-output lookup.
  # User-facing arg is full English (`"lr"` / `"loss"` / `"premium"`)
  # but the actual `$full` columns use the short `prem` convention, so
  # `target = "premium"` reads `prem_proj` / `incr_prem_proj`.
  col_key <- switch(target,
                    lr      = "lr",
                    loss    = "loss",
                    premium = "prem")

  actual_cum  <- col_key
  actual_incr <- paste0("incr_", col_key)
  proj_cum    <- paste0(col_key, "_proj")
  proj_incr   <- paste0("incr_", col_key, "_proj")
  dispatcher <- switch(target,
                        lr      = "fit_lr",
                        loss    = "fit_loss",
                        premium = "fit_premium")

  for (col in c(actual_cum, actual_incr)) {
    if (!(col %in% names(x)))
      stop(sprintf("column '%s' not found in `x`.", col), call. = FALSE)
  }

  # If a pre-computed Maturity object carries a coarser `groups`
  # partition, rebucket the triangle up-front so backtest's
  # actual/held-out tagging and the downstream fit operate on the same
  # partition (otherwise `grp` captured from the original triangle
  # won't match the rebucketed `fit_obj$full` columns).
  if (inherits(maturity, "Maturity")) {
    mat_groups <- attr(maturity, "groups")
    if (!is.null(mat_groups))
      x <- .rebucket_triangle_groups(x, mat_groups)
  }

  grp <- attr(x, "groups")
  coh <- attr(x, "cohort")
  dev <- attr(x, "dev")

  # 1) Tag held-out cells on the original (long-format) triangle ----------
  full <- .copy_dt(x)
  full[, (".coh_rank") := data.table::frank(cohort, ties.method = "dense"),
       by = grp]
  full[, (".cal_idx") := .coh_rank + dev - 1L]
  full[, (".max_cal") := max(.cal_idx, na.rm = TRUE), by = grp]
  full[, (".is_held_out") := .cal_idx > .max_cal - holdout]

  if (!any(full$.is_held_out))
    stop("`holdout` exceeds available calendar diagonals.", call. = FALSE)

  # 2) Build masked triangle via the shared `mask_triangle()` helper ----
  masked <- mask_triangle(x, holdout = holdout)

  if (!nrow(masked))
    stop("After masking, no observations remain. Reduce `holdout`.",
         call. = FALSE)

  # 2a) Resolve maturity against the MASKED triangle (no look-ahead) ----
  # `.resolve_maturity()` dispatches on input type:
  #   NULL          -> NULL
  #   Maturity      -> pass-through
  #   "auto"        -> detect_maturity(masked_tri)  (leakage-safe)
  #   function(tri) -> fn(masked_tri)               (leakage-safe)
  maturity <- .resolve_maturity(maturity, tri = x, masked_tri = masked)

  # 2b) Resolve regime specs against the MASKED triangle (no look-ahead) ---
  # `.resolve_regime()` dispatches on input type:
  #   NULL          -> NULL
  #   Regime        -> pass-through
  #   "auto"        -> detect_regime(masked_tri)   (leakage-safe)
  #   function(tri) -> fn(masked_tri)              (leakage-safe)
  # Passing `masked` as `masked_tri` ensures "auto" and closure forms
  # never see the held-out diagonals.
  loss_regime    <- .resolve_regime(loss_regime,    tri = x, masked_tri = masked)
  premium_regime <- .resolve_regime(premium_regime, tri = x, masked_tri = masked)

  # 3) Fit on masked ----------------------------------------------------
  fit_obj <- switch(target,
    lr = fit_lr(
      masked,
      method         = loss_method,
      loss_alpha     = loss_alpha,
      loss_regime    = loss_regime,
      premium_method = premium_method,
      premium_alpha  = premium_alpha,
      premium_regime = premium_regime,
      sigma_method   = sigma_method,
      recent         = recent,
      maturity       = maturity,
      se_method      = se_method,
      rho            = rho,
      conf_level     = conf_level,
      bootstrap      = bootstrap,
      B              = B,
      seed           = seed,
      ...
    ),
    loss = fit_loss(
      masked,
      method         = loss_method,
      alpha          = loss_alpha,
      regime         = loss_regime,
      premium_method = premium_method,
      premium_alpha  = premium_alpha,
      sigma_method   = sigma_method,
      recent         = recent,
      maturity       = maturity,
      conf_level     = conf_level,
      ...
    ),
    premium = fit_premium(
      masked,
      method       = premium_method,
      alpha        = premium_alpha,
      sigma_method = sigma_method,
      recent       = recent,
      regime       = premium_regime,
      ...
    )
  )

  if (!("full" %in% names(fit_obj)) ||
      !all(c("cohort", "dev", proj_cum, proj_incr) %in% names(fit_obj$full)))
    stop(sprintf(
      "fitter output must contain `$full` with `cohort`, `dev`, `%s`, `%s` columns.",
      proj_cum, proj_incr
    ), call. = FALSE)

  # 4) Compare projected (from fit) to actual (from original x) for
  # both cumulative and incremental views -----------------------------
  proj <- fit_obj$full[, .SD,
    .SDcols = c(grp, "cohort", "dev", proj_cum, proj_incr)]

  obs <- full[.is_held_out == TRUE,
    .SD,
    .SDcols = c(grp, "cohort", "dev", actual_cum, actual_incr, ".cal_idx")]
  data.table::setnames(obs,
    c(actual_cum, actual_incr, ".cal_idx"),
    c("actual", "incr_actual", "cal_idx")
  )

  ae_err <- proj[obs,
                 on      = c(grp, "cohort", "dev"),
                 nomatch = NULL]
  data.table::setnames(ae_err,
    c(proj_cum, proj_incr),
    c("expected", "incr_expected")
  )

  # Drop cells the masked fit cannot reach (cumulative side); the
  # incremental columns may still be NA on those edges, which is fine.
  ae_err <- ae_err[is.finite(expected)]

  # Cumulative: raw signed gap (target units) + relative error
  ae_err[, ("aeg")    := actual - expected]
  ae_err[, ("ae_err") := data.table::fifelse(
    is.finite(expected) & expected != 0,
    actual / expected - 1,
    NA_real_
  )]

  # Incremental: raw signed gap + relative error
  ae_err[, ("incr_aeg")    := incr_actual - incr_expected]
  ae_err[, ("incr_ae_err") := data.table::fifelse(
    is.finite(incr_expected) & incr_expected != 0,
    incr_actual / incr_expected - 1,
    NA_real_
  )]

  data.table::setcolorder(ae_err, c(
    grp, "cohort", "dev",
    "actual",      "expected",      "aeg",      "ae_err",
    "incr_actual", "incr_expected", "incr_aeg", "incr_ae_err",
    "cal_idx"
  ))
  data.table::setorderv(ae_err, c(grp, "cohort", "dev"))

  # 5) Summaries (per dev and per calendar diagonal) -- both views ----
  col_by       <- c(grp, "dev")
  diag_by      <- c(grp, "cal_idx")
  col_summary  <- .backtest_aggregate(ae_err, col_by)
  diag_summary <- .backtest_aggregate(ae_err, diag_by)

  # 6) Usage map. Mirrors `fit_loss()$usage` but additionally tags the
  # held-out diagonal cells. Computed from the *pre-mask* triangle so
  # the heatmap shows the full footprint (training / held-out /
  # regime-excluded / future).
  usage_metric <- switch(target,
                         lr = "loss", loss = "loss",
                         premium = "prem")
  usage <- .build_usage(
    x,
    regime   = loss_regime,
    recent   = recent,
    holdout  = holdout,
    maturity = maturity,
    metric   = usage_metric
  )

  # 7) Assemble output --------------------------------------------------
  out <- list(
    call         = match.call(),
    data         = x,
    masked       = masked,
    fit          = fit_obj,
    ae_err       = ae_err,
    col_summary  = col_summary,
    diag_summary = diag_summary,
    target       = target,
    holdout      = holdout,
    dispatcher   = dispatcher,
    groups       = grp,
    cohort       = coh,
    dev          = dev,
    usage        = usage
  )
  class(out) <- "Backtest"
  out
}


# Internal: aggregation helper for backtest summaries ---------------------

# `col_summary` and `diag_summary` use the same statistics list -- only
# the `by =` columns differ. Centralising the expression keeps the two
# views provably aligned and shaves out 20+ duplicate lines.
.backtest_aggregate <- function(ae_err, by_cols) {
  out <- ae_err[, .(
    n                = sum(is.finite(ae_err)),
    aeg_mean         = mean(aeg, na.rm = TRUE),
    aeg_med          = stats::median(aeg, na.rm = TRUE),
    ae_err_mean      = mean(ae_err, na.rm = TRUE),
    ae_err_med       = stats::median(ae_err, na.rm = TRUE),
    ae_err_wt        = sum(actual - expected, na.rm = TRUE) /
                       sum(expected, na.rm = TRUE),
    incr_aeg_mean    = mean(incr_aeg, na.rm = TRUE),
    incr_aeg_med     = stats::median(incr_aeg, na.rm = TRUE),
    incr_ae_err_mean = mean(incr_ae_err, na.rm = TRUE),
    incr_ae_err_med  = stats::median(incr_ae_err, na.rm = TRUE),
    incr_ae_err_wt   = sum(incr_actual - incr_expected, na.rm = TRUE) /
                       sum(incr_expected, na.rm = TRUE)
  ), by = by_cols]
  data.table::setorderv(out, by_cols)
  out
}


# Print / summary ---------------------------------------------------------

#' @rdname backtest
#' @method print Backtest
#' @export
print.Backtest <- function(x, ...) {
  cat("<Backtest>\n")
  cat(sprintf("  dispatcher: %s\n", x$dispatcher))
  cat(sprintf("  target    : %s\n", x$target))
  cat(sprintf("  holdout   : %d diagonals (%d cells)\n",
              x$holdout, nrow(x$ae_err)))
  err <- x$ae_err$ae_err
  err <- err[is.finite(err)]
  if (length(err)) {
    cat(sprintf("  A/E Error : mean %.2f%% / median %.2f%%\n",
                mean(err) * 100, stats::median(err) * 100))
  } else {
    cat("  A/E Error : (no finite values)\n")
  }
  invisible(x)
}


#' @rdname backtest
#' @method summary Backtest
#' @export
summary.Backtest <- function(object, ...) {
  out <- list(
    dispatcher   = object$dispatcher,
    target       = object$target,
    holdout      = object$holdout,
    n_held_out   = nrow(object$ae_err),
    col_summary  = object$col_summary,
    diag_summary = object$diag_summary
  )
  class(out) <- "summary.Backtest"
  out
}


#' @rdname backtest
#' @method print summary.Backtest
#' @export
print.summary.Backtest <- function(x, ...) {
  cat("Backtest summary\n")
  cat(sprintf("  dispatcher: %s\n", x$dispatcher))
  cat(sprintf("  target    : %s\n", x$target))
  cat(sprintf("  holdout   : %d diagonals (%d cells)\n\n",
              x$holdout, x$n_held_out))

  cat("By dev:\n")
  print(x$col_summary)
  cat("\nBy calendar diagonal:\n")
  print(x$diag_summary)
  invisible(x)
}

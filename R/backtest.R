# Backtest --------------------------------------------------------------

#' Backtest a loss / premium / loss-ratio projection on existing data
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
#' * `target = "premium"` -- score the premium projection from
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
#' @param premium_method Method for the premium-side projection.
#'   Passed to `fit_lr()` / `fit_loss()` / `fit_premium()`. One of
#'   `"cl"`, `"ed"`.
#' @param loss_alpha,premium_alpha Mack alpha for loss-side / premium-side
#'   chain-ladder estimation.
#' @param sigma_method Tail sigma extrapolation method. Forwarded to
#'   the underlying fitter.
#' @param recent Calendar-diagonal recency filter forwarded to the
#'   fitter.
#' @param loss_regime_break,premium_regime_break Cohort-axis regime
#'   break(s) for loss / premium estimation. `premium_regime_break`
#'   defaults to `loss_regime_break`. Cannot be combined with
#'   `auto_detect_regime = TRUE`.
#' @param auto_detect_regime Logical. When `TRUE`, [detect_regime()] is
#'   run *inside* the backtest loop on the **masked** triangle (i.e.,
#'   the data the analyst would have at the simulated cutoff) and the
#'   result is used for both `loss_regime_break` and
#'   `premium_regime_break`. Avoids the look-ahead bias of detecting
#'   regimes on the full triangle (including the held-out diagonals)
#'   before backtesting. Mutually exclusive with an explicit
#'   `loss_regime_break`. Default `FALSE`.
#' @param maturity_args Maturity-detection args. Used only for
#'   `target = "lr"` and `target = "loss"` (stage-adaptive).
#' @param se_method Standard-error composition for `fit_lr()`. Unused
#'   for `target = "loss"` / `target = "premium"`.
#' @param rho Loss-premium correlation used by `fit_lr()` delta
#'   method. Unused for `target = "loss"` / `target = "premium"`.
#' @param conf_level Confidence level for `fit_lr()` / `fit_loss()`
#'   intervals. Unused for `target = "premium"`.
#' @param bootstrap,B,seed Bootstrap controls for `fit_lr()`. Unused
#'   for `target = "loss"` / `target = "premium"`.
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
#'       `(group, cohort, dev, value_actual, value_proj, aeg, ae_err,
#'       value_actual_incr, value_proj_incr, aeg_incr, ae_err_incr,
#'       calendar_idx)`. `aeg = value_actual - value_proj` (signed
#'       error in target units); `ae_err = value_actual / value_proj
#'       - 1` (relative error). `_incr` siblings are the same metrics
#'       on the incremental view.}
#'     \item{`col_summary`}{Per-`dev` aggregate A/E Error and AEG
#'       (mean / median / weighted) with `_incr` variants and `n`.}
#'     \item{`diag_summary`}{Per-calendar-diagonal aggregate A/E
#'       Error and AEG (same columns as `col_summary`, keyed by
#'       `calendar_idx`).}
#'     \item{`target`, `holdout`, `fit_fn_name`}{Call metadata.}
#'     \item{`groups`, `cohort`, `dev`}{Variable name relays
#'       from `x`.}
#'   }
#'
#' @seealso [fit_lr()], [fit_loss()], [fit_premium()], [plot.Backtest()]
#'
#' @examples
#' \dontrun{
#' data(experience)
#' tri <- build_triangle(
#'   experience,
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "loss_incr",
#'   premium  = "premium_incr"
#' )
#'
#' bt_lr      <- backtest(tri, holdout = 6L, target = "lr")
#' bt_loss    <- backtest(tri, holdout = 6L, target = "loss")
#' bt_premium <- backtest(tri, holdout = 6L, target = "premium")
#'
#' print(bt_lr)
#' summary(bt_lr)
#' plot(bt_lr)
#' }
#'
#' @export
backtest <- function(x,
                     holdout              = 6L,
                     target               = c("lr", "loss", "premium"),
                     loss_method          = c("sa", "ed", "cl"),
                     premium_method       = c("cl", "ed"),
                     loss_alpha           = 1,
                     premium_alpha        = 1,
                     sigma_method         = c("locf", "min_last2", "loglinear"),
                     recent               = NULL,
                     loss_regime_break    = NULL,
                     premium_regime_break = NULL,
                     auto_detect_regime   = FALSE,
                     maturity_args        = NULL,
                     se_method            = c("fixed", "delta"),
                     rho                  = 0.95,
                     conf_level           = 0.95,
                     bootstrap            = FALSE,
                     B                    = 1000,
                     seed                 = NULL,
                     ...) {

  .assert_triangle_input(x, "backtest()")

  target         <- match.arg(target)
  loss_method    <- match.arg(loss_method)
  premium_method <- match.arg(premium_method)
  sigma_method   <- match.arg(sigma_method)
  se_method      <- match.arg(se_method)

  if (!is.numeric(holdout) || length(holdout) != 1L ||
      is.na(holdout) || holdout < 1L)
    stop("`holdout` must be a single positive integer.", call. = FALSE)
  holdout <- as.integer(holdout)

  if (!is.logical(auto_detect_regime) || length(auto_detect_regime) != 1L ||
      is.na(auto_detect_regime))
    stop("`auto_detect_regime` must be a single non-missing logical.",
         call. = FALSE)
  if (auto_detect_regime && !is.null(loss_regime_break))
    stop("`auto_detect_regime = TRUE` cannot be combined with an explicit ",
         "`loss_regime_break` -- pick one or the other.", call. = FALSE)

  # Map target -> bare column key (`lr` / `loss` / `premium`). The fit
  # output's `$full` has both cumulative (`<key>_proj`) and incremental
  # (`<key>_incr_proj`) projections, and the raw Triangle has both
  # `<key>` and `<key>_incr` columns -- so a single backtest call yields
  # both views (`plot.Backtest(cell_type = ...)` selects which to show).
  actual_cum  <- target
  actual_incr <- paste0(target, "_incr")
  proj_cum    <- paste0(target, "_proj")
  proj_incr   <- paste0(target, "_incr_proj")
  fit_fn_name <- switch(target,
                        lr      = "fit_lr",
                        loss    = "fit_loss",
                        premium = "fit_premium")

  for (col in c(actual_cum, actual_incr)) {
    if (!(col %in% names(x)))
      stop(sprintf("column '%s' not found in `x`.", col), call. = FALSE)
  }

  grp <- attr(x, "groups")
  coh <- attr(x, "cohort")
  dev <- attr(x, "dev")

  # 1) Tag held-out cells on the original (long-format) triangle ----------
  full <- .ensure_dt(x)
  full[, .coh_rank := data.table::frank(cohort, ties.method = "dense"),
       by = grp]
  full[, .cal_idx := .coh_rank + dev - 1L]
  full[, .max_cal := max(.cal_idx, na.rm = TRUE), by = grp]
  full[, .is_held_out := .cal_idx > .max_cal - holdout]

  if (!any(full$.is_held_out))
    stop("`holdout` exceeds available calendar diagonals.", call. = FALSE)

  # 2) Build masked triangle via the shared `mask_triangle()` helper ----
  masked <- mask_triangle(x, holdout = holdout)

  if (!nrow(masked))
    stop("After masking, no observations remain. Reduce `holdout`.",
         call. = FALSE)

  # 2b) Auto-detect regime on the MASKED triangle (no look-ahead) -----
  # When `auto_detect_regime = TRUE`, run `detect_regime()` on the
  # masked triangle so the break date only uses information available
  # at the simulated backtest cutoff. Skipping this and passing a
  # `Regime` detected on the full triangle would leak future data into
  # the held-out evaluation.
  if (auto_detect_regime) {
    detected <- tryCatch(
      detect_regime(masked, target = "lr"),
      error = function(e) NULL
    )
    if (!is.null(detected)) {
      # Only set loss-side break -- auto-applying the same break to
      # premium often filters premium too aggressively (thin post-break
      # data -> factor estimation fails -> projection NA -> backtest
      # coverage collapses). User can pass `premium_regime_break`
      # explicitly when premium really shifts too.
      loss_regime_break <- detected
    }
  }

  # 3) Fit on masked ----------------------------------------------------
  fit_obj <- switch(target,
    lr = fit_lr(
      masked,
      method               = loss_method,
      loss_alpha           = loss_alpha,
      loss_regime_break    = loss_regime_break,
      premium_method       = premium_method,
      premium_alpha        = premium_alpha,
      premium_regime_break = premium_regime_break,
      sigma_method         = sigma_method,
      recent               = recent,
      maturity_args        = maturity_args,
      se_method            = se_method,
      rho                  = rho,
      conf_level           = conf_level,
      bootstrap            = bootstrap,
      B                    = B,
      seed                 = seed,
      ...
    ),
    loss = fit_loss(
      masked,
      method               = loss_method,
      alpha                = loss_alpha,
      loss_regime_break    = loss_regime_break,
      premium_method       = premium_method,
      premium_alpha        = premium_alpha,
      premium_regime_break = premium_regime_break,
      sigma_method         = sigma_method,
      recent               = recent,
      maturity_args        = maturity_args,
      conf_level           = conf_level,
      ...
    ),
    premium = fit_premium(
      masked,
      method       = premium_method,
      alpha        = premium_alpha,
      sigma_method = sigma_method,
      recent       = recent,
      regime_break = premium_regime_break,
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
    c("value_actual", "value_actual_incr", "calendar_idx")
  )

  ae_err <- proj[obs,
                 on      = c(grp, "cohort", "dev"),
                 nomatch = NULL]
  data.table::setnames(ae_err,
    c(proj_cum, proj_incr),
    c("value_proj", "value_proj_incr")
  )

  # Drop cells the masked fit cannot reach (cumulative side); the
  # incremental columns may still be NA on those edges, which is fine.
  ae_err <- ae_err[is.finite(value_proj)]

  # Cumulative ae_err / aeg
  ae_err[, aeg := value_actual - value_proj]
  ae_err[, ae_err := data.table::fifelse(
    is.finite(value_proj) & value_proj != 0,
    value_actual / value_proj - 1,
    NA_real_
  )]

  # Incremental ae_err / aeg
  ae_err[, aeg_incr := value_actual_incr - value_proj_incr]
  ae_err[, ae_err_incr := data.table::fifelse(
    is.finite(value_proj_incr) & value_proj_incr != 0,
    value_actual_incr / value_proj_incr - 1,
    NA_real_
  )]

  data.table::setcolorder(ae_err, c(
    grp, "cohort", "dev",
    "value_actual",      "value_proj",      "aeg",      "ae_err",
    "value_actual_incr", "value_proj_incr", "aeg_incr", "ae_err_incr",
    "calendar_idx"
  ))
  data.table::setorderv(ae_err, c(grp, "cohort", "dev"))

  # 5) Summaries (per dev and per calendar diagonal) -- both views ----
  col_by   <- c(grp, "dev")
  col_summary <- ae_err[, .(
    n                = sum(is.finite(ae_err)),
    aeg_mean         = mean(aeg, na.rm = TRUE),
    aeg_med          = stats::median(aeg, na.rm = TRUE),
    ae_err_mean      = mean(ae_err, na.rm = TRUE),
    ae_err_med       = stats::median(ae_err, na.rm = TRUE),
    ae_err_wt        = sum(value_actual - value_proj, na.rm = TRUE) /
                       sum(value_proj, na.rm = TRUE),
    aeg_incr_mean    = mean(aeg_incr, na.rm = TRUE),
    aeg_incr_med     = stats::median(aeg_incr, na.rm = TRUE),
    ae_err_incr_mean = mean(ae_err_incr, na.rm = TRUE),
    ae_err_incr_med  = stats::median(ae_err_incr, na.rm = TRUE),
    ae_err_incr_wt   = sum(value_actual_incr - value_proj_incr, na.rm = TRUE) /
                       sum(value_proj_incr, na.rm = TRUE)
  ), by = col_by]
  data.table::setorderv(col_summary, col_by)

  diag_by <- c(grp, "calendar_idx")
  diag_summary <- ae_err[, .(
    n                = sum(is.finite(ae_err)),
    aeg_mean         = mean(aeg, na.rm = TRUE),
    aeg_med          = stats::median(aeg, na.rm = TRUE),
    ae_err_mean      = mean(ae_err, na.rm = TRUE),
    ae_err_med       = stats::median(ae_err, na.rm = TRUE),
    ae_err_wt        = sum(value_actual - value_proj, na.rm = TRUE) /
                       sum(value_proj, na.rm = TRUE),
    aeg_incr_mean    = mean(aeg_incr, na.rm = TRUE),
    aeg_incr_med     = stats::median(aeg_incr, na.rm = TRUE),
    ae_err_incr_mean = mean(ae_err_incr, na.rm = TRUE),
    ae_err_incr_med  = stats::median(ae_err_incr, na.rm = TRUE),
    ae_err_incr_wt   = sum(value_actual_incr - value_proj_incr, na.rm = TRUE) /
                       sum(value_proj_incr, na.rm = TRUE)
  ), by = diag_by]
  data.table::setorderv(diag_summary, diag_by)

  # 6) Assemble output --------------------------------------------------
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
    fit_fn_name  = fit_fn_name,
    groups       = grp,
    cohort       = coh,
    dev          = dev
  )
  class(out) <- "Backtest"
  out
}


# Print / summary ---------------------------------------------------------

#' @rdname backtest
#' @method print Backtest
#' @export
print.Backtest <- function(x, ...) {
  cat("<Backtest>\n")
  cat(sprintf("  fit_fn   : %s\n", x$fit_fn_name))
  cat(sprintf("  target   : %s\n", x$target))
  cat(sprintf("  holdout  : %d diagonals (%d cells)\n",
              x$holdout, nrow(x$ae_err)))
  err <- x$ae_err$ae_err
  err <- err[is.finite(err)]
  if (length(err)) {
    cat(sprintf("  A/E Error: mean %.2f%% / median %.2f%%\n",
                mean(err) * 100, stats::median(err) * 100))
  } else {
    cat("  A/E Error: (no finite values)\n")
  }
  invisible(x)
}


#' @rdname backtest
#' @method summary Backtest
#' @export
summary.Backtest <- function(object, ...) {
  out <- list(
    fit_fn_name  = object$fit_fn_name,
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
  cat(sprintf("  fit_fn  : %s\n", x$fit_fn_name))
  cat(sprintf("  target  : %s\n", x$target))
  cat(sprintf("  holdout : %d diagonals (%d cells)\n\n",
              x$holdout, x$n_held_out))

  cat("By dev:\n")
  print(x$col_summary)
  cat("\nBy calendar diagonal:\n")
  print(x$diag_summary)
  invisible(x)
}

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
#'   defaults to `loss_regime_break`.
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
#'       `(group_var, cohort, dev, value_actual, value_pred, ae_err,
#'       calendar_idx)`.}
#'     \item{`col_summary`}{Per-`dev` aggregate A/E Error (mean /
#'       median / weighted / n).}
#'     \item{`diag_summary`}{Per-calendar-diagonal aggregate A/E Error.}
#'     \item{`target`, `holdout`, `fit_fn_name`}{Call metadata.}
#'     \item{`group_var`, `cohort_var`, `dev_var`}{Variable name relays
#'       from `x`.}
#'   }
#'
#' @seealso [fit_lr()], [fit_loss()], [fit_premium()], [plot.Backtest()]
#'
#' @examples
#' \dontrun{
#' data(experience)
#' tri <- build_triangle(experience, groups = coverage)
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
                     premium_regime_break = loss_regime_break,
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

  # Map target -> (actual column on x, score column on fit$full,
  # fitter name).
  score_col <- switch(target,
                      lr      = "lr_proj",
                      loss    = "loss_proj",
                      premium = "premium_proj")
  fit_fn_name <- switch(target,
                        lr      = "fit_lr",
                        loss    = "fit_loss",
                        premium = "fit_premium")

  # The actual column on the raw triangle is the bare target name.
  if (!(target %in% names(x)))
    stop(sprintf("`target` = '%s' not found in `x`.", target),
         call. = FALSE)

  grp <- attr(x, "group_var")
  coh <- attr(x, "cohort_var")
  dev <- attr(x, "dev_var")

  # 1) Tag held-out cells on the original (long-format) triangle ----------
  full <- .ensure_dt(x)
  full[, .coh_rank := data.table::frank(cohort, ties.method = "dense"),
       by = grp]
  full[, .cal_idx := .coh_rank + dev - 1L]
  full[, .max_cal := max(.cal_idx, na.rm = TRUE), by = grp]
  full[, .is_held_out := .cal_idx > .max_cal - holdout]

  if (!any(full$.is_held_out))
    stop("`holdout` exceeds available calendar diagonals.", call. = FALSE)

  # 2) Build masked triangle -------------------------------------------
  dm <- full[.is_held_out == FALSE]
  dm[, c(".coh_rank", ".cal_idx", ".max_cal", ".is_held_out") := NULL]

  if (!nrow(dm))
    stop("After masking, no observations remain. Reduce `holdout`.",
         call. = FALSE)

  masked <- dm
  data.table::setattr(masked, "class", class(x))
  for (a in c("group_var", "cohort_var",
              "dev_var", "longer")) {
    av <- attr(x, a, exact = TRUE)
    if (!is.null(av)) data.table::setattr(masked, a, av)
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
      !all(c("cohort", "dev", score_col) %in% names(fit_obj$full)))
    stop(sprintf(
      "fitter output must contain `$full` with `cohort`, `dev`, and `%s` columns.",
      score_col
    ), call. = FALSE)

  # 4) Compare predicted (from fit) to actual (from original x) -------
  pred <- fit_obj$full[, .SD,
    .SDcols = c(grp, "cohort", "dev", score_col)]

  obs <- full[.is_held_out == TRUE,
    .SD,
    .SDcols = c(grp, "cohort", "dev", target, ".cal_idx")]
  data.table::setnames(obs, target, "value_actual")
  data.table::setnames(obs, ".cal_idx", "calendar_idx")

  ae_err <- pred[obs,
                 on = c(grp, "cohort", "dev"),
                 nomatch = NULL]
  data.table::setnames(ae_err, score_col, "value_pred")

  # Drop cells the masked fit cannot reach (no projection produced)
  ae_err <- ae_err[is.finite(value_pred)]

  ae_err[, ae_err := data.table::fifelse(
    is.finite(value_pred) & value_pred != 0,
    value_actual / value_pred - 1,
    NA_real_
  )]

  data.table::setcolorder(ae_err, c(grp, "cohort", "dev",
                                    "value_actual", "value_pred",
                                    "ae_err", "calendar_idx"))
  data.table::setorderv(ae_err, c(grp, "cohort", "dev"))

  # 5) Summaries --------------------------------------------------------
  col_by   <- c(grp, "dev")
  col_summary <- ae_err[, .(
    n           = sum(is.finite(ae_err)),
    ae_err_mean = mean(ae_err, na.rm = TRUE),
    ae_err_med  = stats::median(ae_err, na.rm = TRUE),
    ae_err_wt   = sum(value_actual - value_pred, na.rm = TRUE) /
                  sum(value_pred, na.rm = TRUE)
  ), by = col_by]
  data.table::setorderv(col_summary, col_by)

  diag_by <- c(grp, "calendar_idx")
  diag_summary <- ae_err[, .(
    n           = sum(is.finite(ae_err)),
    ae_err_mean = mean(ae_err, na.rm = TRUE),
    ae_err_med  = stats::median(ae_err, na.rm = TRUE),
    ae_err_wt   = sum(value_actual - value_pred, na.rm = TRUE) /
                  sum(value_pred, na.rm = TRUE)
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
    group_var    = grp,
    cohort_var   = coh,
    dev_var      = dev
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

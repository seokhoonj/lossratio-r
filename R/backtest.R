# Backtest --------------------------------------------------------------

# Map (fit_obj class, metric) -> projection column on fit_obj$full.
.backtest_proj_col <- function(fit_obj, metric) {
  if (inherits(fit_obj, "CLFit")) return("value_proj")
  if (inherits(fit_obj, "LRFit")) {
    lr_map <- c(loss = "loss_proj", premium = "premium_proj", lr = "lr_proj")
    if (!(metric %in% names(lr_map)))
      stop(sprintf(
        "For `fit_lr`, `metric` must be one of %s; got '%s'.",
        paste(sprintf("'%s'", names(lr_map)), collapse = ", "),
        metric
      ), call. = FALSE)
    return(unname(lr_map[metric]))
  }
  if (inherits(fit_obj, "EDFit")) {
    ed_map <- c(loss = "loss_proj", premium = "premium_proj", lr = "lr_proj")
    if (!(metric %in% names(ed_map)))
      stop(sprintf(
        "For `fit_ed`, `metric` must be one of %s; got '%s'.",
        paste(sprintf("'%s'", names(ed_map)), collapse = ", "),
        metric
      ), call. = FALSE)
    return(unname(ed_map[metric]))
  }
  stop(sprintf(
    "Unsupported fit class: %s. Supported: 'CLFit', 'LRFit', 'EDFit'.",
    paste(class(fit_obj), collapse = "/")
  ), call. = FALSE)
}

#' Backtest a loss-ratio / chain ladder fit on existing data
#'
#' @description
#' Hold out the latest `holdout` calendar diagonals from the input
#' `Triangle`, refit the model on the earlier portion, project the
#' held-out cells, and compare the projection to the actual values
#' that were withheld.
#'
#' The A/E Error (`ae_err`) follows the standard actuarial A/E
#' convention and is computed cell-wise as
#' \deqn{ae\_err = \frac{value_{actual}}{value_{proj}} - 1}
#' so that positive values flag under-projection (the model
#' under-estimated; actual exceeded expected) and negative values
#' flag over-projection. Aggregated by
#' development period (`col_summary`) and by calendar diagonal
#' (`diag_summary`).
#'
#' @param x A `"Triangle"` object (or a `"Backtest"` object for the S3
#'   `print()` method).
#' @param object A `"Backtest"` object. Used by the S3 `summary()` method.
#' @param holdout Integer. Number of latest calendar diagonals to mask
#'   before refitting. Default `6L`.
#' @param fit_fn Fitting function. Default `fit_lr` (stage-adaptive
#'   loss-ratio projection); also supports `fit_cl` for single-column
#'   chain ladder and `fit_ed` for exposure-driven projection. If
#'   `fit_fn` does not have a `loss_var` formal (as is the case for
#'   `fit_lr` and `fit_ed`), `metric` is used only to select the
#'   comparison column on the fit's `$full` table; arguments for the
#'   fitter itself (e.g., `loss_var`, `premium_var`, `method`) are
#'   passed through `...`.
#' @param metric Character scalar. The **score column** for the
#'   backtest — the column whose held-out actual values are compared
#'   against the corresponding model projection cell-by-cell. One of
#'   `"lr"` (default), `"loss"`, or `"premium"`.
#'
#'   With `fit_fn = fit_cl`, `backtest()` forwards `metric` to
#'   `fit_cl()`'s `loss_var` argument (because `fit_cl` has its own
#'   `loss_var` formal that selects which triangle column to
#'   accumulate), so the score column and the chain-ladder
#'   accumulation column coincide.
#'
#'   With `fit_fn = fit_lr` (default), `fit_lr()` does not take a
#'   `metric` argument — it always projects `loss`, `premium`, and
#'   `lr` jointly. Here `metric` is used purely to pick which
#'   projection column on `fit_lr$full` is treated as the prediction
#'   for scoring. The three valid values map to `loss_proj`,
#'   `premium_proj`, and `lr_proj` respectively.
#' @param ... Additional arguments passed to `fit_fn` (e.g., `method`,
#'   `alpha`, `recent`, `tail`).
#'
#' @details
#' The `metric` argument plays two slightly different roles
#' depending on the fitter, summarised below. In every case `metric`
#' is the column that drives the A/E Error comparison; the difference is
#' whether the fitter consumes the same name as input or whether the
#' name is only resolved against the fit's projection table.
#'
#' \tabular{lllll}{
#'   \strong{`fit_fn`} \tab \strong{Valid `metric`} \tab
#'     \strong{Forwarded to fitter?} \tab
#'     \strong{Compared column on `fit$full`} \tab \strong{Notes} \cr
#'   `fit_cl` \tab any numeric column in `x` \tab yes (as `loss_var`)
#'     \tab `value_proj` \tab Score column equals the column being
#'     accumulated by chain ladder. \cr
#'   `fit_lr` \tab `"loss"`, `"premium"`, `"lr"` \tab no (fit_lr ignores
#'     `metric`) \tab `loss_proj`, `premium_proj`, `lr_proj`
#'     respectively \tab Fitter projects all three jointly; `metric`
#'     only selects the scoring lane. \cr
#'   `fit_ed` \tab `"loss"`, `"premium"`, `"lr"` \tab no (fit_ed ignores
#'     `metric`) \tab `loss_proj`, `premium_proj`, `lr_proj`
#'     respectively \tab Pure exposure-driven projection (additive
#'     \eqn{g_k \cdot C^P_k}); `metric` only selects the scoring lane.
#' }
#'
#' This means that `backtest(..., metric = "loss")` paired with
#' `fit_lr` is *not* the same operation as `fit_cl(loss_var = "loss")`
#' under the hood, even though both use the string `"loss"`. The
#' former scores the loss projection that came out of a stage-adaptive
#' loss-ratio fit; the latter scores a chain ladder applied directly
#' to cumulative loss.
#'
#' @return An object of class `"Backtest"` with components:
#'   \describe{
#'     \item{`call`}{Matched call.}
#'     \item{`data`}{Original `Triangle`.}
#'     \item{`masked`}{Triangle used for fitting (with held-out cells
#'       removed).}
#'     \item{`fit`}{The fit object returned by `fit_fn`.}
#'     \item{`ae_err`}{`data.table` of held-out cells with columns
#'       `(group_var, cohort, dev, value_actual, value_pred, ae_err,
#'       calendar_idx)`.}
#'     \item{`col_summary`}{Per-`dev` aggregate A/E Error (mean /
#'       median / weighted / n).}
#'     \item{`diag_summary`}{Per-calendar-diagonal aggregate A/E Error.}
#'     \item{`metric`, `holdout`, `fit_fn_name`}{Call metadata.}
#'     \item{`group_var`, `cohort_var`, `dev_var`}{Variable name relays
#'       from `x`.}
#'   }
#'
#' @seealso [fit_lr()], [fit_cl()], [fit_ed()], [plot.Backtest()]
#'
#' @examples
#' \dontrun{
#' data(experience)
#' tri <- build_triangle(experience, group_var = coverage)
#' bt <- backtest(tri, holdout = 6L)
#' print(bt)
#' summary(bt)
#' plot(bt)
#' }
#'
#' @export
backtest <- function(x,
                     holdout    = 6L,
                     fit_fn     = fit_lr,
                     metric     = "lr",
                     ...) {

  .assert_triangle_input(x, "backtest()")

  if (!is.numeric(holdout) || length(holdout) != 1L ||
      is.na(holdout) || holdout < 1L)
    stop("`holdout` must be a single positive integer.", call. = FALSE)
  holdout <- as.integer(holdout)

  if (!is.function(fit_fn))
    stop("`fit_fn` must be a function (e.g., `fit_cl`).", call. = FALSE)

  # fit_lr / fit_ed always project loss/premium jointly through the same
  # ratio-fit. The only natural scoring lane for the backtest is `lr`;
  # comparing the underlying loss / premium projections is a different
  # question best served by `fit_cl` directly.
  fit_formals <- names(formals(fit_fn))
  is_ratio_fit <- "premium_var" %in% fit_formals
  if (is_ratio_fit && !identical(metric, "lr"))
    stop(
      "`fit_fn` is a ratio-fit (fit_lr / fit_ed); only `metric = \"lr\"`",
      " is supported. To backtest loss or premium projections, call",
      " `backtest(..., fit_fn = fit_cl, metric = \"loss\")` instead.",
      call. = FALSE
    )

  grp_var <- attr(x, "group_var")
  coh_var <- attr(x, "cohort_var")
  dev_var <- attr(x, "dev_var")

  if (!(metric %in% names(x)))
    stop(sprintf("`metric` = '%s' not found in `x`.", metric),
         call. = FALSE)

  # 1) Tag held-out cells on the original (long-format) triangle ----------
  full <- .ensure_dt(x)
  full[, .coh_rank := data.table::frank(cohort, ties.method = "dense"),
       by = grp_var]
  full[, .cal_idx := .coh_rank + dev - 1L]
  full[, .max_cal := max(.cal_idx, na.rm = TRUE), by = grp_var]
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
  # Forward `metric` only to single-column fitters that take a
  # `loss_var` formal but no `premium_var` (i.e., `fit_cl`). For
  # dual-arg fitters like fit_lr / fit_ed, `metric` here is just the
  # scoring lane and must not override the fitter's loss numerator
  # (would conflict with the default `premium_var`).
  fit_formals <- names(formals(fit_fn))
  if ("loss_var" %in% fit_formals && !("premium_var" %in% fit_formals)) {
    fit_obj <- fit_fn(masked, loss_var = metric, ...)
  } else {
    fit_obj <- fit_fn(masked, ...)
  }

  proj_col <- .backtest_proj_col(fit_obj, metric)

  if (!("full" %in% names(fit_obj)) ||
      !all(c("cohort", "dev", proj_col) %in% names(fit_obj$full)))
    stop(sprintf(
      "`fit_fn` output must contain `$full` with `cohort`, `dev`, and `%s` columns.",
      proj_col
    ), call. = FALSE)

  # 4) Compare predicted (from fit) to actual (from original x) -------
  pred <- fit_obj$full[, .SD,
    .SDcols = c(grp_var, "cohort", "dev", proj_col)]

  obs <- full[.is_held_out == TRUE,
    .SD,
    .SDcols = c(grp_var, "cohort", "dev", metric, ".cal_idx")]
  data.table::setnames(obs, metric, "value_actual")
  data.table::setnames(obs, ".cal_idx", "calendar_idx")

  ae_err <- pred[obs,
                 on = c(grp_var, "cohort", "dev"),
                 nomatch = NULL]
  data.table::setnames(ae_err, proj_col, "value_pred")

  # Drop cells the masked fit cannot reach (no projection produced)
  ae_err <- ae_err[is.finite(value_pred)]

  ae_err[, ae_err := data.table::fifelse(
    is.finite(value_pred) & value_pred != 0,
    value_actual / value_pred - 1,
    NA_real_
  )]

  data.table::setcolorder(ae_err, c(grp_var, "cohort", "dev",
                                    "value_actual", "value_pred",
                                    "ae_err", "calendar_idx"))
  data.table::setorderv(ae_err, c(grp_var, "cohort", "dev"))

  # 5) Summaries --------------------------------------------------------
  col_by   <- c(grp_var, "dev")
  col_summary <- ae_err[, .(
    n           = sum(is.finite(ae_err)),
    ae_err_mean = mean(ae_err, na.rm = TRUE),
    ae_err_med  = stats::median(ae_err, na.rm = TRUE),
    ae_err_wt   = sum(value_actual - value_pred, na.rm = TRUE) /
                  sum(value_pred, na.rm = TRUE)
  ), by = col_by]
  data.table::setorderv(col_summary, col_by)

  diag_by <- c(grp_var, "calendar_idx")
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
    metric    = metric,
    holdout      = holdout,
    fit_fn_name  = deparse(substitute(fit_fn)),
    group_var    = grp_var,
    cohort_var   = coh_var,
    dev_var      = dev_var
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
  cat(sprintf("  metric : %s\n", x$metric))
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
    metric    = object$metric,
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
  cat(sprintf("  metric: %s\n", x$metric))
  cat(sprintf("  holdout : %d diagonals (%d cells)\n\n",
              x$holdout, x$n_held_out))

  cat("By dev:\n")
  print(x$col_summary)
  cat("\nBy calendar diagonal:\n")
  print(x$diag_summary)
  invisible(x)
}

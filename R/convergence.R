# Loss-ratio stability ----------------------------------------------------

#' Robust cross-cohort dispersion of incremental loss ratio
#'
#' @description
#' Internal helper. For each (group, dev) cell of a `Triangle`, computes a
#' robust scale-invariant dispersion of incremental loss ratio across
#' cohorts:
#'
#' \deqn{\mathrm{dispersion} = \frac{1.4826 \cdot \mathrm{MAD}_i(lr_{i,v})}{|\mathrm{median}_i(lr_{i,v})|}}
#'
#' Operating on incremental LR keeps the metric inertia-free.
#'
#' @param triangle A `Triangle` object.
#' @param min_n_cohorts Minimum number of cohorts required to compute the
#'   dispersion; below this threshold the row is flagged `"sparse"` and
#'   `dispersion` is `NA`. Default `5L`.
#'
#' @return data.table with columns `dev`, `n_cohorts`, `lr_median`,
#'   `lr_mad`, `dispersion`, `flag` (and grouping columns when present).
#'
#' @keywords internal
.compute_dispersion <- function(triangle, min_n_cohorts = 5L) {

  # data.table NSE NULL bindings for bare column refs in `j` below.
  lr <- lr_median <- lr_mad <- n_cohorts <- flag <- NULL

  .assert_class(triangle, "Triangle")
  grp <- attr(triangle, "groups")
  near_zero_floor <- 1e-8

  dt <- .copy_dt(triangle)
  dt <- dt[!is.na(dt[["lr"]])]

  by_cols <- c(grp, "dev")

  out <- dt[, list(
    n_cohorts = .N,
    lr_median = stats::median(lr),
    lr_mad    = stats::mad(lr, constant = 1.4826)
  ), by = by_cols]

  out[, ("flag") := data.table::fifelse(
    n_cohorts < min_n_cohorts, "sparse",
    data.table::fifelse(abs(lr_median) < near_zero_floor,
                        "near_zero_median", "ok")
  )]

  .denom <- pmax(abs(out$lr_median), near_zero_floor)
  out[, ("dispersion") := data.table::fifelse(
    flag == "sparse", NA_real_, lr_mad / .denom)]

  data.table::setcolorder(out, c(by_cols, "n_cohorts", "lr_median",
                                 "lr_mad", "dispersion", "flag"))
  out[]
}


#' Extract portfolio-level projected loss ratio from a Backtest fit object
#'
#' Aggregates per-cohort projected ultimate to a single portfolio LR via
#' exposure-weighting: \eqn{\sum_i loss_{ult,i} / \sum_i premium_{ult,i}}.
#'
#' @param bt A `Backtest` object (result of `backtest()`).
#'
#' @return Numeric scalar. `NA_real_` when fields missing.
#' @keywords internal
.extract_portfolio_lr <- function(bt) {
  if (is.null(bt) || is.null(bt$fit) || is.null(bt$fit$summary))
    return(NA_real_)
  s <- data.table::as.data.table(bt$fit$summary)
  needed <- c("loss_ult", "premium_ult")
  if (!all(needed %in% names(s))) return(NA_real_)
  total_loss <- sum(s$loss_ult,    na.rm = TRUE)
  total_exp  <- sum(s$premium_ult, na.rm = TRUE)
  if (!is.finite(total_exp) || total_exp <= 0) return(NA_real_)
  total_loss / total_exp
}


#' Find the development period at which the loss ratio estimate stabilises
#'
#' @description
#' Identify the first dev \eqn{k^{**}} from which the projected
#' portfolio loss ratio is observed to be stable up to the maximum
#' available development period \eqn{V}. Three complementary stability
#' criteria are computed on the LR backtest path; the user selects
#' which one defines \eqn{k^{**}} via `method =`.
#'
#' *Notation mapping (code <-> math)*:
#'
#' Standard chain-ladder convention: \eqn{i} indexes cohort (origin
#' period), \eqn{k} indexes development period. The maturity point
#' \eqn{k^*} and convergence point \eqn{k^{**}} live on the \eqn{k}
#' axis. Earlier paper drafts used \eqn{v} (valuation) for the same
#' index in Section 11; we unify on \eqn{k} for consistency.
#'
#' \tabular{lll}{
#'   `dev_max`  \tab \eqn{K_{\max}}                \tab Maximum observable dev (a scalar) \cr
#'   `dev_cand` \tab \eqn{k \in [k^*, K_{\max}-2]} \tab Integer vector of candidate dev points \cr
#'   `lr[i]`    \tab \eqn{LR_k}                    \tab Portfolio LR projection at dev = `dev_cand[i]` \cr
#'   `revision[i]` \tab \eqn{R_k = |LR_k - LR_{k-1}|} \tab Adjacent-step revision (diagnostic) \cr
#'   `drift_window[i]` \tab \eqn{\max - \min} of \eqn{LR} over \eqn{[k, k+W-1]}     \tab Local window range \cr
#'   `drift_tail[i]`   \tab \eqn{\max - \min} of \eqn{LR} over \eqn{[k, K_{\max}]}  \tab Tail range \cr
#'   `slope[i]`        \tab \eqn{\hat\beta_k}, OLS slope of \eqn{LR \sim k} on \eqn{[k, K_{\max}]} \tab Trend test \cr
#'   `dispersion[i]`   \tab \eqn{\hat{D}_k}                                         \tab Robust cross-cohort spread of incremental LR
#' }
#'
#' Stability methods (which sequence drives `pass`):
#'
#' \describe{
#'   \item{`"window"`}{Local stability:
#'     \code{drift_window[i] < max_drift}. Fast, but misses a slow
#'     monotone drift that fits under `max_drift` per step.}
#'   \item{`"tail"`}{(default, *reserving-safe*) Global stability:
#'     \code{drift_tail[i] < max_drift}. Catches monotone drift. The
#'     first passing dev is later (more conservative) than `"window"`.}
#'   \item{`"slope"`}{Trend test: \code{|slope[i]| < max_slope}.
#'     Explicit no-trend check; sensitive to non-linear trajectories.}
#'   \item{`"all"`}{Strictest: all three pass simultaneously.}
#' }
#'
#' All four pass vectors (`pass_window`, `pass_tail`, `pass_slope`,
#' `pass`) and the underlying diagnostic series are returned
#' regardless of the chosen `method`, so the analyst can inspect every
#' criterion and re-decide.
#'
#' Across all methods, a cross-cohort agreement clause
#' \code{dispersion[i] < max_dispersion} is required in addition.
#'
#' This replaces an earlier formulation \eqn{R_k < c \cdot
#' \hat{SE}^{param}_k} (paper Section 11). The paper's SE-normalised
#' form is asymptotically broken on large portfolios:
#' \eqn{\hat{SE}^{param}} shrinks as \eqn{1/\sqrt{n}} while \eqn{R_k}
#' has a structural noise floor, so the ratio diverges and the
#' criterion never fires.
#'
#' **Caveat (reserving)**: detected `conv_k` reflects stability *up
#' to* `dev_max` (\eqn{K_{\max}}) only -- it is *not* an asymptotic
#' guarantee that the projection will not drift past
#' \eqn{K_{\max}}. Treat `conv_k` as a diagnostic for "from here on,
#' what we observe is stable", not as a guarantee of future
#' stability. For reserving applications, prefer `method = "tail"` or
#' `"all"` over `"window"`, attach an IBNR margin via
#' `fit_lr$summary` SE/CI columns, and weigh the *evidence span*
#' (`dev_max - conv_k`): a `conv_k` near `dev_max` has thin evidence.
#'
#' @param triangle A `Triangle` object (typically from [as_triangle()]).
#' @param method Which stability criterion defines `conv_k`. One of
#'   `"tail"` (default), `"window"`, `"slope"`, or `"all"`. See the
#'   description for semantics and the reserving caveat.
#' @param max_drift Upper bound on the drift metric (window or tail),
#'   in LR units. Default `0.01` (1pp). Raise for noisier or
#'   longer-tail books.
#' @param max_slope Upper bound on \code{|slope[i]|}, the OLS slope of
#'   \eqn{LR \sim k} on \eqn{[k, K_{\max}]}, in LR-per-dev units.
#'   Default `1e-3` (0.1pp per dev). Used by `method = "slope"` /
#'   `"all"`.
#' @param max_dispersion Upper bound on the cross-cohort dispersion
#'   \eqn{\hat{D}_k}. Default `0.15`.
#' @param window Drift window length \eqn{W} (in dev steps): the
#'   number of consecutive valuations used by the `"window"` method to
#'   compute `drift_window`. Default `5L`. Note: other functions in the
#'   package also expose a `window` argument (e.g. `detect_regime()`
#'   for e-divisive segment width); here it controls *only* the drift
#'   metric, not the e-divisive algorithm.
#' @param mat_k Pre-computed maturity point. When `NULL`, computed via
#'   [detect_maturity()] applied to an lr-based ATA.
#' @param holdout_max Maximum holdout depth used for the rolling
#'   backtest. When `NULL`, set to
#'   `max(window, floor((dev_max - mat_k) / 2))`.
#' @param min_n_cohorts Minimum number of cohorts required to compute
#'   \eqn{\hat{D}_v}. Default `5L`.
#' @param ... Additional arguments forwarded to `backtest()` (and thence
#'   to `fit_lr()`), e.g. `loss_method`, `recent`, `loss_regime`.
#'
#' @return An object of class `Convergence` (named list). Includes the
#'   slots tabulated in the notation mapping above
#'   (`dev_max`, `dev_cand`, `lr`, `revision`, `drift_window`,
#'   `drift_tail`, `slope`, `dispersion`), per-method pass vectors
#'   (`pass_window`, `pass_tail`, `pass_slope`, `pass`), the threshold
#'   parameters, and metadata attributes (`groups`, `target`,
#'   `dispatcher`).
#'
#' @seealso [detect_maturity()], [backtest()], [fit_lr()]
#'
#' @export
detect_convergence <- function(triangle,
                              method        = c("tail", "window",
                                                "slope", "all"),
                              max_drift     = 0.01,
                              max_slope     = 1e-3,
                              max_dispersion        = 0.15,
                              window        = 5L,
                              mat_k        = NULL,
                              holdout_max   = NULL,
                              min_n_cohorts = 5L,
                              ...) {

  # LR convergence detection always backtests the LR projection from
  # fit_lr; the dispatcher is fixed (no `target=` dispatch).
  dispatcher <- "fit_lr"

  # 1) validate inputs -------------------------------------------------
  .assert_class(triangle, "Triangle")
  method <- match.arg(method)

  if (!is.numeric(max_drift) || length(max_drift) != 1L ||
      is.na(max_drift) || max_drift <= 0)
    stop("`max_drift` must be a single positive numeric value.",
         call. = FALSE)
  if (!is.numeric(max_slope) || length(max_slope) != 1L ||
      is.na(max_slope) || max_slope <= 0)
    stop("`max_slope` must be a single positive numeric value.",
         call. = FALSE)
  if (!is.numeric(max_dispersion)  || length(max_dispersion)  != 1L ||
      is.na(max_dispersion)  || max_dispersion  <= 0)
    stop("`max_dispersion` must be a single positive numeric value.",
         call. = FALSE)
  if (!is.numeric(window) || length(window) != 1L ||
      is.na(window) || window < 2)
    stop("`window` must be a single integer >= 2.", call. = FALSE)
  window <- as.integer(window)

  grp <- attr(triangle, "groups")
  if (is.null(grp)) grp <- character(0)
  dev <- attr(triangle, "dev")

  # 2) resolve mat_k --------------------------------------------------
  if (is.null(mat_k)) {
    mat    <- detect_maturity(triangle, target = "lr", weight = "premium")
    mat_k  <- suppressWarnings(min(mat$change, na.rm = TRUE))
    if (!is.finite(mat_k))
      stop("`detect_maturity(target = \"lr\")` returned no mature link ",
           "for this triangle, so `mat_k` cannot be auto-resolved. ",
           "Possible causes: too few cohorts, ATA factors that fail the ",
           "`max_cv` / `max_rse` thresholds, or a triangle with too few ",
           "dev periods. Supply `mat_k` explicitly (e.g. ",
           "`detect_convergence(triangle, mat_k = 4L)`) to bypass auto-detection.",
           call. = FALSE)
  }
  mat_k <- as.integer(mat_k)

  # 3) determine dev_max (max observable dev) + holdout window --------
  dev_max <- max(triangle$dev, na.rm = TRUE)
  if (is.null(holdout_max)) {
    holdout_max <- max(window, as.integer(floor((dev_max - mat_k) / 2)))
  }
  holdout_max <- as.integer(holdout_max)

  # candidate dev sequence: [mat_k, dev_max - 2] so at least 2 points
  # fit in a tail / slope window (window method narrows further below).
  dev_cand <- if (dev_max - 2L >= mat_k)
    seq.int(mat_k, dev_max - 2L) else integer(0)

  if (!length(dev_cand))
    warning(sprintf(
      "No candidate dev points: `mat_k` (%d) + 2 > `dev_max` (%d). ",
      mat_k, dev_max),
      "Need at least `mat_k + 2 <= dev_max` for convergence detection. ",
      "Returning `conv_k = NA`.",
      call. = FALSE)

  # 4) compute `lr` at each candidate dev via cached backtest ----------
  # `lr[i]` is the portfolio-level projected ultimate LR when fitting
  # with data through dev = dev_cand[i] (i.e. holdout = dev_max -
  # dev_cand[i]). The backtest call is cached per holdout depth so we
  # don't redo work.
  lr <- rep(NA_real_, length(dev_cand))

  lr_cache <- numeric(0)
  cache_holdout <- integer(0)

  .get_lr <- function(h) {
    idx <- match(h, cache_holdout)
    if (!is.na(idx)) return(lr_cache[idx])
    bt <- tryCatch(
      backtest(triangle, holdout = h, target = "lr", ...),
      error = function(e) NULL
    )
    val <- .extract_portfolio_lr(bt)
    cache_holdout <<- c(cache_holdout, h)
    lr_cache      <<- c(lr_cache,      val)
    val
  }

  for (i in seq_along(dev_cand)) {
    h <- dev_max - dev_cand[i]
    if (h < 1L || h > holdout_max) next
    lr[i] <- .get_lr(h)
  }

  # 5) adjacent-step revision (diagnostic only) ------------------------
  revision <- c(NA_real_, abs(diff(lr)))

  # 6) window drift -- range of `lr` over [i, i + window - 1] ----------
  drift_window <- rep(NA_real_, length(dev_cand))
  for (i in seq_along(dev_cand)) {
    j <- i + window - 1L
    if (j > length(dev_cand)) break
    w <- lr[i:j]
    if (all(is.finite(w)))
      drift_window[i] <- max(w) - min(w)
  }

  # 7) tail drift -- range of `lr` over [i, end] -----------------------
  drift_tail <- rep(NA_real_, length(dev_cand))
  for (i in seq_along(dev_cand)) {
    w <- lr[i:length(dev_cand)]
    w <- w[is.finite(w)]
    if (length(w) >= 2L)
      drift_tail[i] <- max(w) - min(w)
  }

  # 8) slope -- OLS slope of `lr ~ dev` on [i, end] --------------------
  slope <- rep(NA_real_, length(dev_cand))
  for (i in seq_along(dev_cand)) {
    y <- lr[i:length(dev_cand)]
    x <- dev_cand[i:length(dev_cand)]
    ok <- is.finite(y)
    if (sum(ok) >= 2L) {
      yo <- y[ok]; xo <- x[ok]
      vx <- stats::var(xo)
      if (is.finite(vx) && vx > 0)
        slope[i] <- stats::cov(xo, yo) / vx
    }
  }

  # 9) cross-cohort dispersion at each candidate dev -------------------
  dispersion <- rep(NA_real_, length(dev_cand))
  if (length(dev_cand)) {
    disp_tbl <- .compute_dispersion(triangle, min_n_cohorts = min_n_cohorts)
    if (length(grp)) {
      # collapse across groups: take median across groups at each dev
      disp_tbl <- disp_tbl[, list(
        dispersion = stats::median(dispersion, na.rm = TRUE)
      ), by = "dev"]
    }
    dispersion <- disp_tbl$dispersion[match(dev_cand, disp_tbl$dev)]
  }

  # 10) per-method pass tests ------------------------------------------
  pass_d      <- is.finite(dispersion) & (dispersion < max_dispersion)
  pass_window <- is.finite(drift_window) & (drift_window < max_drift) & pass_d
  pass_tail   <- is.finite(drift_tail)   & (drift_tail   < max_drift) & pass_d
  pass_slope  <- is.finite(slope)        & (abs(slope)   < max_slope) & pass_d
  pass_all    <- pass_window & pass_tail & pass_slope

  pass <- switch(method,
                 window = pass_window,
                 tail   = pass_tail,
                 slope  = pass_slope,
                 all    = pass_all)

  # 11) first passing dev ----------------------------------------------
  conv_k <- if (any(pass, na.rm = TRUE))
    dev_cand[which(pass)[1L]] else NA_integer_

  # 12) assemble return object -----------------------------------------
  out <- list(
    call          = match.call(),
    conv_k        = conv_k,
    method        = method,
    mat_k        = mat_k,
    dev_max       = dev_max,
    dev_cand      = dev_cand,
    lr            = lr,
    revision      = revision,
    drift_window  = drift_window,
    drift_tail    = drift_tail,
    slope         = slope,
    dispersion    = dispersion,
    pass_window   = pass_window,
    pass_tail     = pass_tail,
    pass_slope    = pass_slope,
    pass          = pass,
    max_drift     = max_drift,
    max_slope     = max_slope,
    max_dispersion        = max_dispersion,
    window        = window,
    holdout_max   = holdout_max,
    min_n_cohorts = min_n_cohorts
  )

  data.table::setattr(out, "groups",     grp)
  data.table::setattr(out, "target",     "lr")
  data.table::setattr(out, "dispatcher", dispatcher)
  data.table::setattr(out, "dev",        dev)
  class(out) <- "Convergence"
  out
}


# S3 methods --------------------------------------------------------------

#' @method print Convergence
#' @export
print.Convergence <- function(x, ...) {
  n        <- length(x$dev_cand)
  n_win    <- sum(x$pass_window, na.rm = TRUE)
  n_tail   <- sum(x$pass_tail,   na.rm = TRUE)
  n_slope  <- sum(x$pass_slope,  na.rm = TRUE)
  n_all    <- sum(x$pass_window & x$pass_tail & x$pass_slope, na.rm = TRUE)
  span     <- if (is.finite(x$conv_k)) x$dev_max - x$conv_k else NA_integer_
  mark     <- function(m) if (identical(x$method, m)) "  <- method" else ""

  # Build aligned criterion strings: `_d` = display, `_p` = padded.
  drift_d  <- format(x$max_drift,      nsmall = 0, scientific = FALSE)
  slope_d  <- format(x$max_slope,      nsmall = 0, scientific = FALSE)
  disp_d   <- format(x$max_dispersion, nsmall = 0, scientific = FALSE)
  thr_w    <- max(nchar(drift_d), nchar(slope_d))
  drift_p  <- formatC(drift_d, width = thr_w, flag = "-")
  slope_p  <- formatC(slope_d, width = thr_w, flag = "-")

  fmt_line <- function(label, n_pass, metric, thr) {
    sprintf("    %-7s: %2d/%-2d (%-12s < %s & dispersion < %s)%s",
            label, n_pass, n, metric, thr, disp_d, mark(label))
  }

  cat("<Convergence>\n")
  cat(sprintf("  method     : %s\n", x$method))
  cat(sprintf("  conv_k     : %s%s\n",
              if (is.finite(x$conv_k)) x$conv_k else "NA",
              if (is.finite(span))
                sprintf("   (evidence span dev_max - conv_k = %d)", span)
              else ""))
  cat(sprintf("  mat_k      : %d\n", x$mat_k))
  cat(sprintf("  dev_max    : %d\n", x$dev_max))
  cat(sprintf("  candidates : %d\n", n))
  cat("  passes :\n")
  cat(fmt_line("window", n_win,   "drift_window", drift_p), "\n", sep = "")
  cat(fmt_line("tail",   n_tail,  "drift_tail",   drift_p), "\n", sep = "")
  cat(fmt_line("slope",  n_slope, "|slope|",      slope_p), "\n", sep = "")
  cat(sprintf("    all    : %2d/%-2d (window AND tail AND slope)%s\n",
              n_all, n, mark("all")))
  invisible(x)
}

#' @method summary Convergence
#' @export
summary.Convergence <- function(object, ...) {
  data.table::data.table(
    dev          = object$dev_cand,
    lr           = object$lr,
    revision     = object$revision,
    drift_window = object$drift_window,
    drift_tail   = object$drift_tail,
    slope        = object$slope,
    dispersion   = object$dispersion,
    pass_window  = object$pass_window,
    pass_tail    = object$pass_tail,
    pass_slope   = object$pass_slope,
    pass         = object$pass
  )
}

#' Plot the Convergence diagnostic
#'
#' @description
#' Four-panel diagnostic showing the LR backtest path and each
#' stability metric vs. its threshold:
#' \itemize{
#'   \item Top: `lr` (the portfolio LR projection at each valuation).
#'   \item Then for each of `drift_window`, `drift_tail`, `|slope|`,
#'     `dispersion`: the metric over `v` with a dashed horizontal
#'     line at the threshold (`max_drift`, `max_slope`, or `max_dispersion`).
#' }
#' Vertical guides mark `mat_k` (dashed) and the detected `conv_k`
#' for the chosen `method` (solid). The chosen-method panel title is
#' annotated.
#'
#' @param x An object of class `Convergence`.
#' @param theme String passed to [.switch_theme()].
#' @param ... Additional arguments passed to [.switch_theme()].
#'
#' @return A `ggplot` object.
#'
#' @method plot Convergence
#' @export
plot.Convergence <- function(x,
                             theme = c("view", "save", "shiny"),
                             ...) {
  .assert_class(x, "Convergence")
  theme <- match.arg(theme)

  panels <- c("lr", "drift_window", "drift_tail", "|slope|", "dispersion")
  long <- data.table::rbindlist(list(
    data.table::data.table(dev = x$dev_cand, metric = "lr",
                           value = x$lr,           threshold = NA_real_),
    data.table::data.table(dev = x$dev_cand, metric = "drift_window",
                           value = x$drift_window, threshold = x$max_drift),
    data.table::data.table(dev = x$dev_cand, metric = "drift_tail",
                           value = x$drift_tail,   threshold = x$max_drift),
    data.table::data.table(dev = x$dev_cand, metric = "|slope|",
                           value = abs(x$slope),   threshold = x$max_slope),
    data.table::data.table(dev = x$dev_cand, metric = "dispersion",
                           value = x$dispersion,   threshold = x$max_dispersion)
  ))
  long[, ("metric") := factor(metric, levels = panels)]

  thr_tbl <- data.table::data.table(
    metric    = factor(c("drift_window", "drift_tail", "|slope|", "dispersion"),
                       levels = panels),
    threshold = c(x$max_drift, x$max_drift, x$max_slope, x$max_dispersion)
  )

  p <- ggplot2::ggplot(
    long,
    ggplot2::aes(x = .data[["dev"]], y = .data[["value"]])
  ) +
    ggplot2::geom_hline(
      data     = thr_tbl,
      mapping  = ggplot2::aes(yintercept = .data[["threshold"]]),
      linetype = "dashed",
      color    = "#d62728"
    ) +
    ggplot2::geom_vline(
      xintercept = x$mat_k,
      linetype   = "dotted",
      color      = "grey40"
    ) +
    ggplot2::geom_line(linewidth = 0.6, color = "#1f77b4") +
    ggplot2::geom_point(size = 1.6, color = "#1f77b4") +
    ggplot2::facet_wrap(
      ggplot2::vars(.data[["metric"]]),
      ncol = 1, scales = "free_y"
    ) +
    ggplot2::labs(
      title    = "LR stability diagnostic",
      subtitle = sprintf(
        "method = %s   mat_k = %s   conv_k = %s   (max_drift = %s, max_slope = %s, max_dispersion = %s, window = %d)",
        x$method,
        x$mat_k,
        ifelse(is.na(x$conv_k), "NA", x$conv_k),
        x$max_drift, x$max_slope, x$max_dispersion, x$window
      ),
      x = .pretty_var_label(attr(x, "dev")),
      y = NULL
    )

  if (!is.na(x$conv_k)) {
    p <- p + ggplot2::geom_vline(
      xintercept = x$conv_k,
      linetype   = "solid",
      color      = "#2ca02c",
      linewidth  = 0.8
    )
  }

  p + .switch_theme(theme = theme, ...)
}

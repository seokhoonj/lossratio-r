#' Detect an optimal trajectory window `window` for e-divisive regime detection
#'
#' @description
#' Run [detect_regime()] with `method = "e_divisive"` across a sequence
#' of trajectory windows `window_seq`, then recommend an "optimal" `window` based
#' on the *elbow* (knee point) of the *break count vs window* curve.
#'
#' Intuition: small `window` is over-sensitive (early-dev noise produces
#' spurious breaks), large `window` is under-sensitive (high-dim noise
#' obscures real shifts). The break count typically drops sharply at
#' small `window` and plateaus once `window` reaches the genuine information
#' window — that elbow is a reasonable choice.
#'
#' @param x A `"Triangle"` object.
#' @param by Grouping column(s) for per-combination detection, passed
#'   through to [detect_regime()]. `NULL` (default) pools all cohorts.
#' @param window_seq Integer vector of trajectory windows to sweep. Default
#'   `2:24` — typical actuarial range. Each `window` becomes one
#'   `detect_regime()` call.
#' @param target Trajectory variable. Passed to [detect_regime()].
#' @param method Elbow-detection method. Currently only `"elbow"` is
#'   supported (Kneedle algorithm on `break_count` vs `window`). Reserved
#'   for future extensions (Jaccard stability, BIC, etc.).
#' @param sig_level Significance level for `e_divisive`. Default `0.05`.
#' @param min_size Minimum segment size. Default `3L`.
#'
#' @return An object of class `"RegimeOptimalWindow"` (named list):
#'   \describe{
#'     \item{`optimal_window`}{Recommended `window` (scalar integer) via the
#'       Kneedle elbow heuristic on `break_count` vs `window`.}
#'     \item{`diagnostics`}{`data.table` with one row per `window` and (when
#'       grouped) per combo: `[by..., window, n_cohorts, break_count,
#'       mean_magnitude]`. Missing window (too few cohorts, etc.) are
#'       omitted.}
#'     \item{`details`}{Named list of `Regime` objects keyed by `window`
#'       (preserved for downstream inspection / plotting).}
#'     \item{`call`}{Matched call.}
#'     \item{`window_seq`}{Sweep grid actually attempted.}
#'   }
#'
#' @seealso [detect_regime()]
#'
#' @keywords internal
#' @noRd
detect_regime_optimal_window <- function(x,
                                    by        = NULL,
                                    window_seq     = 2:24,
                                    method    = c("elbow"),
                                    target    = "lr",
                                    sig_level = 0.05,
                                    min_size  = 3L) {

  .assert_triangle_input(x, "detect_regime_optimal_window()")
  method <- match.arg(method)

  window_seq <- as.integer(window_seq)
  if (length(window_seq) < 2L || any(is.na(window_seq)) || any(window_seq < 2L))
    stop("`window_seq` must be at least two integers, all >= 2.", call. = FALSE)

  call_obj <- match.call()

  # 1) Run detect_regime over the window grid. Errors (e.g., not enough
  # cohorts at large window) are swallowed and the window is dropped from the
  # diagnostics table.
  details <- vector("list", length(window_seq))
  names(details) <- paste0("window=", window_seq)

  for (i in seq_along(window_seq)) {
    k <- window_seq[i]
    res <- tryCatch(
      suppressWarnings(detect_regime(
        x,
        target    = target,
        by        = by,
        window         = k,
        method    = "e_divisive",
        sig_level = sig_level,
        min_size  = min_size
      )),
      error = function(e) NULL
    )
    details[i] <- list(res)
  }

  # 2) Diagnostics — break_count + mean_magnitude per (combo, window).
  diag_rows <- lapply(seq_along(window_seq), function(i) {
    res <- details[[i]]
    if (is.null(res)) return(NULL)
    bp <- res$breakpoints
    if (length(by) > 0L) {
      bp_split <- split(bp, by = by, drop = FALSE, sorted = TRUE)
      rows <- lapply(names(bp_split), function(combo_key) {
        bpg <- bp_split[[combo_key]]
        head_row <- bpg[1L, by, with = FALSE]
        data.table::data.table(
          head_row,
          window              = window_seq[i],
          break_count    = nrow(bpg),
          mean_magnitude = if (nrow(bpg)) mean(bpg$magnitude, na.rm = TRUE) else NA_real_
        )
      })
      data.table::rbindlist(rows)
    } else {
      data.table::data.table(
        window              = window_seq[i],
        break_count    = nrow(bp),
        mean_magnitude = if (nrow(bp)) mean(bp$magnitude, na.rm = TRUE) else NA_real_
      )
    }
  })
  diagnostics <- data.table::rbindlist(
    diag_rows[!vapply(diag_rows, is.null, logical(1L))]
  )

  if (!nrow(diagnostics))
    stop("No window in `window_seq` produced a usable detection.", call. = FALSE)

  # 3) Elbow heuristic — Kneedle on (window, break_count). For grouped input,
  # aggregate break_count across combos (sum) so the elbow reflects the
  # whole portfolio response. Users who want per-group elbows can call
  # this function once per group.
  agg <- diagnostics[, .(break_count = sum(break_count, na.rm = TRUE)),
                     by = "window"]
  data.table::setorderv(agg, "window")
  optimal_window <- .kneedle_elbow(agg$window, agg$break_count)

  out <- list(
    call        = call_obj,
    optimal_window   = optimal_window,
    diagnostics = diagnostics,
    details     = details,
    window_seq       = window_seq
  )
  class(out) <- "RegimeOptimalWindow"
  out
}


#' Kneedle elbow heuristic for a decreasing curve.
#'
#' Implements the Kneedle algorithm (Satopaa et al., 2011) restricted
#' to the *decreasing convex* shape we expect for break_count vs window:
#' normalise both axes to `[0, 1]`, find the index with maximum
#' distance from the diagonal `y = 1 - x`, return the corresponding `window`.
#'
#' Returns `NA_integer_` when the curve is flat (no variation) or has
#' fewer than 3 points.
#'
#' @keywords internal
.kneedle_elbow <- function(window, break_count) {
  n <- length(window)
  if (n < 3L) return(NA_integer_)
  rng_y <- range(break_count, na.rm = TRUE)
  if (!is.finite(diff(rng_y)) || diff(rng_y) == 0) return(NA_integer_)

  k_norm  <- (window - min(window)) / (max(window) - min(window))
  bc_norm <- (break_count - rng_y[1L]) / (rng_y[2L] - rng_y[1L])

  # For a decreasing curve, the expected line from (0, 1) to (1, 0) is
  # y_line = 1 - x. The elbow is the point with maximum positive vertical
  # *deficit* below that line (i.e. the curve dips fastest before
  # plateauing).
  deficit <- (1 - k_norm) - bc_norm
  idx <- which.max(deficit)
  as.integer(window[idx])
}


#' @method print RegimeOptimalWindow
#' @export
print.RegimeOptimalWindow <- function(x, ...) {
  cat("<RegimeOptimalWindow>\n")
  cat(sprintf("  window_seq        : %d..%d (%d values)\n",
              min(x$window_seq), max(x$window_seq), length(x$window_seq)))
  cat(sprintf("  optimal_window    : %s\n",
              if (is.na(x$optimal_window)) "<flat curve>" else x$optimal_window))
  cat(sprintf("  diagnostics  : %d rows\n", nrow(x$diagnostics)))
  invisible(x)
}


#' @method summary RegimeOptimalWindow
#' @export
summary.RegimeOptimalWindow <- function(object, ...) {
  print(object, ...)
  cat("\n# Break count by window (aggregated):\n")
  agg <- object$diagnostics[
    , .(break_count = sum(break_count, na.rm = TRUE),
        mean_magnitude = mean(mean_magnitude, na.rm = TRUE)),
    by = "window"
  ]
  data.table::setorderv(agg, "window")
  print(agg)
  invisible(object)
}


#' Plot break-count vs window with the elbow marker
#'
#' @description
#' Diagnostic plot for a `detect_regime_optimal_window()` result: shows
#' `break_count` (and optionally `mean_magnitude`) against the
#' trajectory window `window`, with a vertical line at `optimal_window`.
#'
#' @param x A `"RegimeOptimalWindow"` object.
#' @param show_magnitude Logical; if `TRUE` (default), overlay
#'   `mean_magnitude` on a secondary y axis (right). Set `FALSE` for
#'   a cleaner break-count-only plot.
#' @param theme A string passed to [.switch_theme()].
#' @param ... Additional arguments passed to [.switch_theme()].
#'
#' @return A `ggplot` object.
#'
#' @method plot RegimeOptimalWindow
#' @export
plot.RegimeOptimalWindow <- function(x,
                                show_magnitude = TRUE,
                                theme          = c("view", "save", "shiny"),
                                ...) {
  .assert_class(x, "RegimeOptimalWindow")
  theme <- match.arg(theme)

  # Aggregate diagnostics across groups (sum break_count, mean magnitude)
  # so the plot mirrors the elbow-detection input.
  agg <- x$diagnostics[
    , .(break_count    = sum(break_count, na.rm = TRUE),
        mean_magnitude = mean(mean_magnitude, na.rm = TRUE)),
    by = "window"
  ]
  data.table::setorderv(agg, "window")

  bc_max <- max(agg$break_count, na.rm = TRUE)
  mag_max <- if (show_magnitude) {
    max(agg$mean_magnitude, na.rm = TRUE)
  } else {
    NA_real_
  }

  p <- ggplot2::ggplot(agg, ggplot2::aes(x = window)) +
    ggplot2::geom_line(ggplot2::aes(y = break_count),
                       linewidth = 0.7, color = "#1f77b4") +
    ggplot2::geom_point(ggplot2::aes(y = break_count),
                        size = 2, color = "#1f77b4")

  if (show_magnitude && is.finite(mag_max) && mag_max > 0) {
    scale_factor <- bc_max / mag_max
    p <- p +
      ggplot2::geom_line(
        ggplot2::aes(y = mean_magnitude * scale_factor),
        linewidth = 0.6, color = "#d62728", linetype = "dashed"
      ) +
      ggplot2::geom_point(
        ggplot2::aes(y = mean_magnitude * scale_factor),
        size = 1.5, color = "#d62728"
      ) +
      ggplot2::scale_y_continuous(
        name     = "break count",
        sec.axis = ggplot2::sec_axis(
          ~ . / scale_factor, name = "mean magnitude"
        )
      )
  } else {
    p <- p + ggplot2::ylab("break count")
  }

  if (!is.na(x$optimal_window)) {
    p <- p +
      ggplot2::geom_vline(xintercept = x$optimal_window,
                          linetype = "dotted", color = "grey30") +
      ggplot2::annotate(
        "text", x = x$optimal_window, y = bc_max,
        label = sprintf("optimal window = %d", x$optimal_window),
        hjust = -0.1, vjust = 1, color = "grey30"
      )
  }

  p +
    ggplot2::scale_x_continuous(breaks = unique(agg$window)) +
    ggplot2::labs(
      title    = "Optimal window for e-divisive regime detection",
      subtitle = "Elbow on break-count vs trajectory window window",
      x        = "window (trajectory window)"
    ) +
    .switch_theme(theme, ...)
}

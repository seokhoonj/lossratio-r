# Loss-ratio stability ----------------------------------------------------

#' Robust cross-cohort dispersion of incremental loss ratio
#'
#' @description
#' Internal helper. For each (group, dev) cell of a `Triangle`, computes a
#' robust scale-invariant dispersion of incremental loss ratio across
#' cohorts:
#'
#' \deqn{\hat{D}_v = \frac{1.4826 \cdot \mathrm{MAD}_i(lr_{i,v})}{|\mathrm{median}_i(lr_{i,v})|}}
#'
#' Operating on `lr` (incremental) rather than `clr` keeps the metric
#' inertia-free.
#'
#' @param triangle A `Triangle` object.
#' @param min_n_cohorts Minimum number of cohorts required to compute
#'   `D_v`; below this threshold the row is flagged `"sparse"` and `D_v`
#'   is `NA`. Default `5L`.
#'
#' @return data.table with columns `dev`, `n_cohorts`, `median_lr`,
#'   `mad_lr`, `D_v`, `flag` (and grouping columns when present).
#'
#' @keywords internal
.compute_dv <- function(triangle, min_n_cohorts = 5L) {

  .assert_class(triangle, "Triangle")
  grp_var <- attr(triangle, "group_var")
  near_zero_floor <- 1e-8

  dt <- .ensure_dt(triangle)
  dt <- dt[!is.na(dt$lr)]

  by_cols <- c(grp_var, "dev")

  out <- dt[, list(
    n_cohorts = .N,
    median_lr = stats::median(lr),
    mad_lr    = stats::mad(lr, constant = 1.4826)
  ), by = by_cols]

  out[, flag := data.table::fifelse(
    n_cohorts < min_n_cohorts, "sparse",
    data.table::fifelse(abs(median_lr) < near_zero_floor,
                        "near_zero_median", "ok")
  )]

  denom <- pmax(abs(out$median_lr), near_zero_floor)
  out[, D_v := data.table::fifelse(flag == "sparse", NA_real_, mad_lr / denom)]

  data.table::setcolorder(out, c(by_cols, "n_cohorts", "median_lr",
                                 "mad_lr", "D_v", "flag"))
  out[]
}


#' Extract portfolio-level projected loss ratio from a Backtest fit object
#'
#' Aggregates per-cohort projected ultimate to a single portfolio LR via
#' exposure-weighting: \eqn{\sum_i loss_{ult,i} / \sum_i exposure_{ult,i}}.
#'
#' @param bt A `Backtest` object (result of `backtest()`).
#'
#' @return Numeric scalar. `NA_real_` when fields missing.
#' @keywords internal
.extract_portfolio_lr <- function(bt) {
  if (is.null(bt) || is.null(bt$fit) || is.null(bt$fit$summary))
    return(NA_real_)
  s <- data.table::as.data.table(bt$fit$summary)
  needed <- c("ultimate", "exposure_ult")
  if (!all(needed %in% names(s))) return(NA_real_)
  total_loss <- sum(s$ultimate,     na.rm = TRUE)
  total_exp  <- sum(s$exposure_ult, na.rm = TRUE)
  if (!is.finite(total_exp) || total_exp <= 0) return(NA_real_)
  total_loss / total_exp
}


#' Extract portfolio-level parameter SE on the LR scale
#'
#' Aggregates per-cohort parameter SE (on loss scale) to portfolio-level
#' SE on the LR scale assuming inter-cohort independence:
#'
#' \deqn{SE^{param}(LR_{portfolio}) = \sqrt{\sum_i (param\_se_i)^2} / \sum_i exposure_{ult,i}}
#'
#' @param bt A `Backtest` object.
#' @return Numeric scalar. `NA_real_` when fields missing.
#' @keywords internal
.extract_portfolio_se_param <- function(bt) {
  if (is.null(bt) || is.null(bt$fit) || is.null(bt$fit$summary))
    return(NA_real_)
  s <- data.table::as.data.table(bt$fit$summary)
  needed <- c("param_se", "exposure_ult")
  if (!all(needed %in% names(s))) return(NA_real_)
  total_exp <- sum(s$exposure_ult, na.rm = TRUE)
  if (!is.finite(total_exp) || total_exp <= 0) return(NA_real_)
  ss <- s$param_se
  ss <- ss[is.finite(ss)]
  if (length(ss) == 0L) return(NA_real_)
  sqrt(sum(ss^2)) / total_exp
}


#' Find the development period at which the loss ratio estimate stabilises
#'
#' @description
#' Identify the first valuation \eqn{k^{**}} from which the projected
#' loss ratio is *predictively* stable, in the sense of the paper's
#' Section 11 \eqn{k^{**}} criterion:
#'
#' \deqn{k^{**} = \min\{v \in [k^*, V - M] : R_v < c \cdot \hat{SE}^{param}_v \text{ and } \hat{D}_v < \tau, \text{ for } M \text{ consecutive valuations}\}}
#'
#' where \eqn{R_v} is the predictive revision in the projected loss ratio
#' when calendar diagonal \eqn{D_v} is added, \eqn{\hat{SE}^{param}_v}
#' is the parameter component of the Mack standard error of the
#' projection, \eqn{\hat{D}_v} is the robust cross-cohort dispersion
#' of incremental loss ratios at \eqn{v}, and \eqn{k^*} is the
#' age-to-age maturity point from [find_maturity()].
#'
#' Both clauses guard against complementary failure modes:
#' \eqn{R_v < c \cdot \hat{SE}^{param}_v} requires the projection to
#' stop responding to new diagonals at a scale-relevant magnitude;
#' \eqn{\hat{D}_v < \tau} requires cross-cohort agreement on the
#' incremental-LR level (inertia-free per-period quantity).
#'
#' This function corresponds to the paper's *convergence point*
#' \eqn{k^{**}}, paired with \eqn{k^*} (maturity point).
#'
#' @param triangle A `Triangle` object (typically from [build_triangle()]).
#' @param fit_fn Fitting function used to project. Default [fit_lr].
#'   [fit_cl] is also accepted but `fit_lr` is recommended because it
#'   exposes both loss and exposure projections required for portfolio LR.
#' @param c Multiplier on \eqn{\hat{SE}^{param}_v}. Default `0.5`.
#' @param tau Upper bound on \eqn{\hat{D}_v}. Default `0.15`.
#' @param M Required run length of consecutive passing periods. Default
#'   `3L`.
#' @param k_star Pre-computed maturity point. When `NULL`, computed via
#'   [find_maturity()] applied to a clr-based ATA.
#' @param holdout_max Maximum holdout depth used for the rolling
#'   backtest. When `NULL`, set to `max(M, floor((V - k_star) / 2))`.
#' @param min_n_cohorts Minimum number of cohorts required to compute
#'   \eqn{\hat{D}_v}. Default `5L`.
#' @param ... Additional arguments forwarded to `fit_fn`.
#'
#' @return An object of class `Convergence` (named list) containing the
#'   detected `k_conv`, the candidate sequence `v`, and the diagnostic
#'   sequences `R_v`, `SE_param_v`, `D_v`, `pass_v`. Metadata is carried
#'   on attributes (`group_var`, `value_var`, `fit_fn_name`).
#'
#' @seealso [find_maturity()], [backtest()], [fit_lr()]
#'
#' @export
find_convergence <- function(triangle,
                              fit_fn        = fit_lr,
                              c             = 0.5,
                              tau           = 0.15,
                              M             = 3L,
                              k_star        = NULL,
                              holdout_max   = NULL,
                              min_n_cohorts = 5L,
                              ...) {

  fit_fn_name <- deparse(substitute(fit_fn))

  # 1) validate inputs -------------------------------------------------
  .assert_class(triangle, "Triangle")

  if (!is.numeric(c)   || length(c)   != 1L || is.na(c)   || c   <= 0)
    stop("`c` must be a single positive numeric value.",   call. = FALSE)
  if (!is.numeric(tau) || length(tau) != 1L || is.na(tau) || tau <= 0)
    stop("`tau` must be a single positive numeric value.", call. = FALSE)
  if (!is.numeric(M)   || length(M)   != 1L || is.na(M)   || M   <  1)
    stop("`M` must be a single integer >= 1.", call. = FALSE)
  M <- as.integer(M)

  grp_var <- attr(triangle, "group_var")
  if (is.null(grp_var)) grp_var <- character(0)
  dev_var <- attr(triangle, "dev_var")

  # 2) resolve k_star --------------------------------------------------
  if (is.null(k_star)) {
    mat     <- find_maturity(triangle, value_var = "clr", weight_var = "crp")
    k_star  <- suppressWarnings(min(mat$ata_from, na.rm = TRUE))
    if (!is.finite(k_star))
      stop("Could not derive `k_star` from `find_maturity()`; ",
           "supply it explicitly.", call. = FALSE)
  }
  k_star <- as.integer(k_star)

  # 3) determine V (max observable dev) and holdout window -------------
  V <- max(triangle$dev, na.rm = TRUE)
  if (is.null(holdout_max)) {
    holdout_max <- max(M, as.integer(floor((V - k_star) / 2)))
  }
  holdout_max <- as.integer(holdout_max)

  # candidate v sequence: [k_star, V - M] so an M-run still fits
  v_seq <- if (V - M >= k_star) seq.int(k_star, V - M) else integer(0)

  # 4) build R_v sequence via repeated backtest ------------------------
  # For each v: bt_prev uses data through v-1 (holdout = V-v+1),
  # bt_curr uses data through v (holdout = V-v). R_v is the change
  # in portfolio-level projected ultimate LR.
  R_v        <- rep(NA_real_, length(v_seq))
  SE_param_v <- rep(NA_real_, length(v_seq))

  # Pre-compute LR/SE at each holdout depth we'll need, so adjacent
  # v's share cached calls (each holdout depth used by two v's at most).
  lr_cache <- numeric(0)
  se_cache <- numeric(0)
  cache_holdout <- integer(0)

  .get_lr_se <- function(h) {
    idx <- match(h, cache_holdout)
    if (!is.na(idx)) {
      return(list(lr = lr_cache[idx], se = se_cache[idx]))
    }
    bt <- tryCatch(
      backtest(triangle, holdout = h, fit_fn = fit_fn, value_var = "clr", ...),
      error = function(e) NULL
    )
    lr <- .extract_portfolio_lr(bt)
    se <- .extract_portfolio_se_param(bt)
    cache_holdout <<- c(cache_holdout, h)
    lr_cache      <<- c(lr_cache,      lr)
    se_cache      <<- c(se_cache,      se)
    list(lr = lr, se = se)
  }

  for (i in seq_along(v_seq)) {
    v <- v_seq[i]
    h_curr <- V - v          # data through v
    h_prev <- V - v + 1L     # data through v-1

    if (h_curr < 1L || h_prev > holdout_max) next

    curr <- .get_lr_se(h_curr)
    prev <- .get_lr_se(h_prev)

    if (is.finite(curr$lr) && is.finite(prev$lr))
      R_v[i] <- abs(curr$lr - prev$lr)
    if (is.finite(curr$se))
      SE_param_v[i] <- curr$se
  }

  # 5) build D_v sequence ----------------------------------------------
  D_v <- rep(NA_real_, length(v_seq))
  if (length(v_seq)) {
    dv_tbl <- .compute_dv(triangle, min_n_cohorts = min_n_cohorts)
    if (length(grp_var)) {
      # collapse across groups: take median D_v across groups at each dev
      dv_tbl <- dv_tbl[, list(D_v = stats::median(D_v, na.rm = TRUE)),
                       by = "dev"]
    }
    D_v <- dv_tbl$D_v[match(v_seq, dv_tbl$dev)]
  }

  # 6) two-clause pass test --------------------------------------------
  pass_v <- is.finite(R_v) & is.finite(SE_param_v) & is.finite(D_v) &
            (R_v < c * SE_param_v) & (D_v < tau)

  # 7) first run of length M -------------------------------------------
  k_conv <- NA_integer_
  if (length(pass_v) >= M) {
    for (i in seq_len(length(pass_v) - M + 1L)) {
      if (all(pass_v[i:(i + M - 1L)])) {
        k_conv <- v_seq[i]
        break
      }
    }
  }

  # 8) assemble return object ------------------------------------------
  out <- list(
    call          = match.call(),
    k_conv      = k_conv,
    k_star        = k_star,
    V             = V,
    v             = v_seq,
    R_v           = R_v,
    SE_param_v    = SE_param_v,
    D_v           = D_v,
    pass_v        = pass_v,
    c             = c,
    tau           = tau,
    M             = M,
    holdout_max   = holdout_max,
    min_n_cohorts = min_n_cohorts
  )

  data.table::setattr(out, "group_var",   grp_var)
  data.table::setattr(out, "value_var",   "clr")
  data.table::setattr(out, "fit_fn_name", fit_fn_name)
  data.table::setattr(out, "dev_var",     dev_var)
  class(out) <- "Convergence"
  out
}


# S3 methods --------------------------------------------------------------

#' @method print Convergence
#' @export
print.Convergence <- function(x, ...) {
  cat("<Convergence>\n")
  cat("k_conv       :", x$k_conv, "\n")
  cat("k_star       :", x$k_star,   "\n")
  cat("V (max dev)  :", x$V,        "\n")
  cat("criterion    : R_v < ", x$c, " * SE_param_v  AND  D_v < ", x$tau,
      "  (run M = ", x$M, ")\n", sep = "")
  cat("fit_fn       :", attr(x, "fit_fn_name"), "\n")
  n_pass <- sum(x$pass_v, na.rm = TRUE)
  cat("v candidates :", length(x$v), " (",
      n_pass, " pass both clauses)\n", sep = "")
  invisible(x)
}

#' @method summary Convergence
#' @export
summary.Convergence <- function(object, ...) {
  data.table::data.table(
    v          = object$v,
    R_v        = object$R_v,
    SE_param_v = object$SE_param_v,
    R_over_SE  = object$R_v / object$SE_param_v,
    D_v        = object$D_v,
    pass       = object$pass_v
  )
}

#' Plot the Convergence diagnostic
#'
#' @description
#' Two-panel diagnostic showing the dual criterion driving \eqn{k^{**}}:
#' \itemize{
#'   \item Top panel: \eqn{R_v / \hat{SE}^{param}_v} (predictive
#'     revision normalised by parameter SE), with horizontal guide at
#'     the threshold `c`.
#'   \item Bottom panel: \eqn{\hat{D}_v} (robust cross-cohort
#'     dispersion of incremental loss ratio), with horizontal guide at
#'     the threshold `tau`.
#' }
#' Vertical guides mark `k_star` (dashed) and `k_conv` (solid). A
#' point falling below both threshold lines passes the joint criterion.
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

  # build long-form data: one row per (v, metric)
  R_over_SE <- x$R_v / x$SE_param_v
  long <- data.table::rbindlist(list(
    data.table::data.table(
      v        = x$v,
      metric   = "R[v] / SE[param]",
      value    = R_over_SE,
      thresh   = x$c
    ),
    data.table::data.table(
      v        = x$v,
      metric   = "D[v]",
      value    = x$D_v,
      thresh   = x$tau
    )
  ))
  long[, metric := factor(metric, levels = c("R[v] / SE[param]", "D[v]"))]

  # threshold table (one row per facet) for geom_hline
  thresh_tbl <- data.table::data.table(
    metric = factor(c("R[v] / SE[param]", "D[v]"),
                    levels = c("R[v] / SE[param]", "D[v]")),
    thresh = c(x$c, x$tau)
  )

  p <- ggplot2::ggplot(
    long,
    ggplot2::aes(x = .data[["v"]], y = .data[["value"]])
  ) +
    ggplot2::geom_hline(
      data = thresh_tbl,
      mapping = ggplot2::aes(yintercept = .data[["thresh"]]),
      linetype = "dashed",
      color = "#d62728"
    ) +
    ggplot2::geom_vline(
      xintercept = x$k_star,
      linetype = "dotted",
      color = "grey40"
    ) +
    ggplot2::geom_line(linewidth = 0.6, color = "#1f77b4") +
    ggplot2::geom_point(size = 1.6, color = "#1f77b4") +
    ggplot2::facet_wrap(
      ggplot2::vars(.data[["metric"]]),
      ncol = 1, scales = "free_y",
      labeller = ggplot2::label_parsed
    ) +
    ggplot2::labs(
      title = "LR stability diagnostic",
      subtitle = sprintf(
        "k_star = %s   k_conv = %s   (c = %s, tau = %s, M = %d)",
        x$k_star,
        ifelse(is.na(x$k_conv), "NA", x$k_conv),
        x$c, x$tau, x$M
      ),
      x = .pretty_var_label(attr(x, "dev_var")),
      y = NULL
    )

  if (!is.na(x$k_conv)) {
    p <- p + ggplot2::geom_vline(
      xintercept = x$k_conv,
      linetype = "solid",
      color = "#2ca02c",
      linewidth = 0.8
    )
  }

  p + .switch_theme(theme = theme, ...)
}

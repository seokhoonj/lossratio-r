# Cohort Regime Detection ---------------------------------------------------

#' Detect structural regime shifts across underwriting cohorts
#'
#' @description
#' Detect structural change points in the sequence of cohort-level
#' development trajectories. Each underwriting cohort (indexed by the
#' `cohort_var` of a `"Triangle"` object) is treated as a feature vector
#' whose entries are the selected `target` metric observed at development
#' periods `1, ..., K`. Cohorts are then ordered by underwriting
#' period and tested for structural shifts in the multivariate
#' sequence.
#'
#' Multi-group `Triangle` inputs are supported: detection runs
#' independently per group, and results are combined into a single
#' `Regime` object whose `$breakpoints`, `$labels`, etc. carry the
#' group column. Single-group input retains the original scalar /
#' Date-vector / matrix layout for backward compatibility.
#'
#' Three detection strategies are supported:
#' \describe{
#'   \item{`"e_divisive"`}{Multivariate non-parametric divisive change-point
#'     detection via [ecp::e.divisive()]. The number of regimes is
#'     determined by the data; only significant breakpoints at
#'     `sig_level` are retained. Preferred when the number of regimes
#'     is not known in advance.}
#'   \item{`"pelt"`}{Univariate mean change-point detection via
#'     [changepoint::cpt.mean()] with the PELT algorithm applied to the
#'     first principal component of the cohort feature matrix. Fast
#'     and may return multiple breakpoints.}
#'   \item{`"hclust"`}{Ward hierarchical clustering on the scaled
#'     cohort feature matrix, cut to `n_regimes` clusters. Ignores
#'     time ordering -- useful as a sanity check since non-adjacent
#'     cohorts may cluster together if the trajectory pattern is not
#'     strictly chronological.}
#' }
#'
#' @param x An object of class `"Triangle"`. May contain one or more
#'   groups (per-group detection runs independently).
#'   Also used by S3 `print()` method on `Regime` objects.
#' @param object An object of class `"Regime"`. Used by the S3
#'   `summary()` method.
#' @param target Column name of the trajectory variable. Default
#'   is `"lr"` (cumulative loss ratio).
#' @param K Integer. Common development-period window used to build the
#'   cohort feature matrix. Cohorts with fewer than `K` observed
#'   periods are dropped. Default is `12`.
#' @param method One of `"e_divisive"`, `"pelt"`, `"hclust"`.
#' @param n_regimes Integer. Number of regimes to force. `NULL` means
#'   auto-detect for `"e_divisive"` and `"pelt"`; ignored (required to equal
#'   the requested value) for `"hclust"`, where the default is `2`.
#' @param sig_level Significance level for `"e_divisive"`. Default `0.05`.
#' @param min_size Minimum segment size for `"e_divisive"`. Default `3`.
#' @param ... Reserved for future use.
#'
#' @return An object of class `"Regime"`. For single-group input:
#'   \describe{
#'     \item{`call`}{Matched call.}
#'     \item{`method`}{Detection method used.}
#'     \item{`target`, `K`}{Trajectory variable and window.}
#'     \item{`cohort_var`}{Period variable from `x`.}
#'     \item{`labels`}{`data.table` with one row per analysed cohort:
#'       period, regime id, regime label.}
#'     \item{`breakpoints`}{`Date` vector of breakpoint dates (each is
#'       the first cohort of a new regime; excludes the initial regime
#'       start).}
#'     \item{`n_regimes`}{Number of regimes detected (scalar integer).}
#'     \item{`trajectory`}{Cohort feature matrix (rows = cohorts,
#'       columns = development periods `1, ..., K`).}
#'     \item{`pca`}{`prcomp` object fitted to the feature matrix.}
#'     \item{`dropped`}{Cohorts excluded due to the `K` window
#'       constraint.}
#'   }
#'   For multi-group input the same fields are returned but with
#'   per-group containers: `$breakpoints` is a `data.table` with columns
#'   `{<group_var>, breakpoint}`; `$labels` gains a `<group_var>` column;
#'   `$n_regimes` is a named integer vector; `$trajectory`, `$pca`, and
#'   `$dropped` are named lists keyed by group value. The `$multi_group`
#'   logical flag distinguishes the two layouts.
#'
#' @seealso [plot.Regime()], [build_triangle()]
#'
#' @examples
#' \dontrun{
#' data(experience)
#' tri_sur <- build_triangle(experience[coverage == "SUR"], groups = coverage)
#'
#' # Hierarchical clustering (no extra package dependency)
#' r <- detect_regime(tri_sur, K = 12, method = "hclust",
#'                           n_regimes = 2L)
#' print(r)
#' summary(r)
#' plot(r)
#'
#' # ecp divisive change-point detection (requires the ecp package)
#' r_ecp <- detect_regime(tri_sur, K = 12, method = "e_divisive")
#'
#' # Multi-group: detection per coverage
#' tri_all <- build_triangle(experience, groups = coverage)
#' r_all <- detect_regime(tri_all, K = 12, method = "e_divisive")
#' print(r_all$breakpoints)
#' }
#'
#' @export
detect_regime <- function(x,
                          target    = "lr",
                          K         = 12L,
                          method    = c("e_divisive", "pelt", "hclust"),
                          n_regimes = NULL,
                          sig_level = 0.05,
                          min_size  = 3L,
                          ...) {

  .assert_triangle_input(x, "detect_regime()")
  method <- match.arg(method)

  coh <- attr(x, "cohort_var")
  dev <- attr(x, "dev_var")
  grp <- attr(x, "group_var")

  if (length(coh) != 1L)
    stop("`x` must have exactly one `cohort_var`.", call. = FALSE)
  if (length(dev) != 1L)
    stop("`x` must have exactly one `dev_var`.", call. = FALSE)

  d <- .ensure_dt(x)

  if (!(target %in% names(d)))
    stop(sprintf("`target` = '%s' not found in `x`.", target),
         call. = FALSE)

  K <- as.integer(K)
  if (is.na(K) || K < 2L)
    stop("`K` must be an integer >= 2.", call. = FALSE)

  call_obj <- match.call()

  multi_group <- length(grp) > 0L && length(unique(d[[grp]])) > 1L

  if (!multi_group) {
    res <- .detect_regime_single(
      d         = d,
      target    = target,
      K         = K,
      method    = method,
      n_regimes = n_regimes,
      sig_level = sig_level,
      min_size  = min_size,
      coh       = coh,
      dev       = dev
    )

    out <- list(
      call        = call_obj,
      method      = method,
      target      = target,
      K           = K,
      cohort_var  = coh,
      dev_var     = dev,
      group_var   = grp,
      multi_group = FALSE,
      labels      = res$labels,
      breakpoints = res$breakpoints,
      n_regimes   = res$n_regimes,
      trajectory  = res$trajectory,
      pca         = res$pca,
      dropped     = res$dropped
    )
    class(out) <- "Regime"
    return(out)
  }

  # Multi-group dispatch ---------------------------------------------------
  grp_vals <- sort(unique(d[[grp]]))

  per_group <- vector("list", length(grp_vals))
  names(per_group) <- as.character(grp_vals)

  for (gv in grp_vals) {
    di <- d[d[[grp]] == gv]
    per_group[[as.character(gv)]] <- tryCatch(
      .detect_regime_single(
        d         = di,
        target    = target,
        K         = K,
        method    = method,
        n_regimes = n_regimes,
        sig_level = sig_level,
        min_size  = min_size,
        coh       = coh,
        dev       = dev
      ),
      error = function(e) {
        warning(sprintf("Group '%s': %s -- skipped.", gv, conditionMessage(e)),
                call. = FALSE)
        NULL
      }
    )
  }

  ok_groups <- !vapply(per_group, is.null, logical(1L))
  if (!any(ok_groups))
    stop("No group produced a usable detection result.", call. = FALSE)

  # Combine breakpoints into a data.table {grp, breakpoint}
  bp_rows <- lapply(names(per_group)[ok_groups], function(nm) {
    bp <- per_group[[nm]]$breakpoints
    if (!length(bp)) return(NULL)
    gval <- grp_vals[match(nm, as.character(grp_vals))]
    data.table::data.table(
      .grp        = gval,
      breakpoint  = bp
    )
  })
  bp_dt <- if (length(bp_rows) && any(!vapply(bp_rows, is.null, logical(1L)))) {
    data.table::rbindlist(bp_rows[!vapply(bp_rows, is.null, logical(1L))])
  } else {
    data.table::data.table(
      .grp       = grp_vals[0],
      breakpoint = as.Date(character(0))
    )
  }
  data.table::setnames(bp_dt, ".grp", grp)

  # Combine labels with group column
  label_rows <- lapply(names(per_group)[ok_groups], function(nm) {
    lab <- data.table::copy(per_group[[nm]]$labels)
    gval <- grp_vals[match(nm, as.character(grp_vals))]
    lab[, .grp := gval]
    data.table::setcolorder(lab, c(".grp", setdiff(names(lab), ".grp")))
    lab
  })
  labels_dt <- data.table::rbindlist(label_rows)
  data.table::setnames(labels_dt, ".grp", grp)

  n_regimes_vec <- vapply(per_group[ok_groups], `[[`, integer(1L), "n_regimes")
  trajectory_lst <- lapply(per_group[ok_groups], `[[`, "trajectory")
  pca_lst        <- lapply(per_group[ok_groups], `[[`, "pca")
  dropped_lst    <- lapply(per_group[ok_groups], `[[`, "dropped")

  out <- list(
    call        = call_obj,
    method      = method,
    target      = target,
    K           = K,
    cohort_var  = coh,
    dev_var     = dev,
    group_var   = grp,
    multi_group = TRUE,
    labels      = labels_dt,
    breakpoints = bp_dt,
    n_regimes   = n_regimes_vec,
    trajectory  = trajectory_lst,
    pca         = pca_lst,
    dropped     = dropped_lst
  )
  class(out) <- "Regime"
  out
}


# Internal helpers --------------------------------------------------------

#' Single-group regime detection
#'
#' Core single-group routine used by [detect_regime()]. Takes a
#' pre-filtered data.table `d` (single group) and returns a list with
#' the per-group Regime fields. Multi-group dispatch lives in
#' [detect_regime()] itself.
#'
#' @keywords internal
.detect_regime_single <- function(d, target, K, method,
                                  n_regimes, sig_level, min_size,
                                  coh, dev) {

  d <- d[d[["dev"]] <= K]
  n_obs <- d[, .(n = .N), by = c("cohort")]
  ok <- n_obs[n >= K][["cohort"]]
  dropped <- setdiff(unique(d[["cohort"]]), ok)

  d <- d[d[["cohort"]] %in% ok]
  if (!nrow(d))
    stop("No cohorts have >= K observed development periods. Reduce `K`.",
         call. = FALSE)

  w <- data.table::dcast(
    d, stats::reformulate("dev", response = "cohort"),
    value.var = target
  )
  data.table::setorderv(w, "cohort")

  mat <- as.matrix(w[, !"cohort", with = FALSE])
  rownames(mat) <- as.character(w[["cohort"]])

  if (anyNA(mat))
    stop("Feature matrix contains NA. Reduce `K` or check input.",
         call. = FALSE)

  n_cohorts <- nrow(mat)
  if (n_cohorts < 2L * max(min_size, 1L))
    stop("Too few cohorts after filtering. Reduce `K` or `min_size`.",
         call. = FALSE)

  pca <- stats::prcomp(mat, scale. = TRUE)

  breakpoints_idx <- .regime_breakpoints(
    mat        = mat,
    pca        = pca,
    method     = method,
    n_regimes  = n_regimes,
    sig_level  = sig_level,
    min_size   = min_size
  )

  regime_id <- .regime_ids_from_breaks(n_cohorts, breakpoints_idx)
  regime_label <- .regime_label_from_range(w[["cohort"]], regime_id)

  labels <- data.table::data.table(
    period    = w[["cohort"]],
    regime    = factor(regime_label, levels = unique(regime_label)),
    regime_id = regime_id
  )
  data.table::setnames(labels, "period", "cohort")

  breakpoints <- if (length(breakpoints_idx)) {
    w[["cohort"]][breakpoints_idx]
  } else {
    w[["cohort"]][0]
  }

  list(
    labels      = labels,
    breakpoints = breakpoints,
    n_regimes   = as.integer(max(regime_id)),
    trajectory  = mat,
    pca         = pca,
    dropped     = dropped
  )
}


#' @keywords internal
.regime_breakpoints <- function(mat, pca, method, n_regimes,
                                sig_level, min_size) {
  n <- nrow(mat)

  if (method == "e_divisive") {
    if (!requireNamespace("ecp", quietly = TRUE))
      stop("Package 'ecp' is required for method = \"ecp\". ",
           "Install with install.packages('ecp').", call. = FALSE)
    k_arg <- if (is.null(n_regimes)) NULL else as.integer(n_regimes - 1L)
    res <- ecp::e.divisive(
      X        = mat,
      k        = k_arg,
      sig.lvl  = sig_level,
      min.size = as.integer(min_size)
    )
    est <- res$estimates
    # ecp returns segment starts incl. 1 and n+1; interior = regime starts
    est[-c(1L, length(est))]

  } else if (method == "pelt") {
    if (!requireNamespace("changepoint", quietly = TRUE))
      stop("Package 'changepoint' is required for method = \"pelt\". ",
           "Install with install.packages('changepoint').", call. = FALSE)
    pc1 <- pca$x[, 1L]
    if (is.null(n_regimes)) {
      cpt <- changepoint::cpt.mean(pc1, method = "PELT",
                                   minseglen = as.integer(min_size))
    } else {
      cpt <- changepoint::cpt.mean(pc1, method = "BinSeg",
                                   Q = as.integer(n_regimes - 1L),
                                   minseglen = as.integer(min_size))
    }
    # changepoint returns last index of each segment; convert to starts
    last_of_seg <- changepoint::cpts(cpt)
    last_of_seg + 1L  # next index = start of new regime

  } else if (method == "hclust") {
    k <- if (is.null(n_regimes)) 2L else as.integer(n_regimes)
    if (k < 2L) stop("`n_regimes` must be >= 2.", call. = FALSE)
    h  <- stats::hclust(stats::dist(scale(mat)), method = "ward.D2")
    cl <- stats::cutree(h, k = k)
    # breakpoints = indices where cluster id changes in sequential order
    which(diff(cl) != 0L) + 1L
  }
}

#' @keywords internal
.regime_ids_from_breaks <- function(n, breaks) {
  ids <- integer(n)
  cur <- 1L
  bk  <- sort(unique(as.integer(breaks)))
  for (i in seq_len(n)) {
    if (length(bk) && i >= bk[1L]) {
      cur <- cur + 1L
      bk  <- bk[-1L]
    }
    ids[i] <- cur
  }
  ids
}

#' @keywords internal
.regime_label_from_range <- function(period, regime_id) {
  s <- vapply(split(period, regime_id), function(p) {
    sprintf("%s-%s", format(min(p), "%y.%m"), format(max(p), "%y.%m"))
  }, character(1L))
  s[as.character(regime_id)]
}


# Print / summary ---------------------------------------------------------

#' @rdname detect_regime
#' @method print Regime
#' @export
print.Regime <- function(x, ...) {
  cat("<Regime>\n")
  cat(sprintf("  method      : %s\n", x$method))
  cat(sprintf("  target      : %s\n", x$target))
  cat(sprintf("  window (K)  : %s 1-%d\n", x$dev_var, x$K))

  if (isTRUE(x$multi_group)) {
    grp <- x$group_var
    grp_vals <- names(x$n_regimes)
    cat(sprintf("  groups      : %d (%s)\n",
                length(grp_vals), grp))
    for (gv in grp_vals) {
      n_coh <- nrow(x$labels[x$labels[[grp]] == .coerce_match(gv, x$labels[[grp]])])
      n_drop <- length(x$dropped[[gv]])
      bp_g <- x$breakpoints[x$breakpoints[[grp]] ==
                              .coerce_match(gv, x$breakpoints[[grp]])][["breakpoint"]]
      cat(sprintf("    [%s] cohorts: %d", gv, n_coh))
      if (n_drop) cat(sprintf(" (%d dropped)", n_drop))
      cat(sprintf(" | regimes: %d", x$n_regimes[[gv]]))
      if (length(bp_g)) {
        cat(sprintf(" | breakpoints: %s",
                    paste(format(bp_g, "%y.%m"), collapse = ", ")))
      } else {
        cat(" | breakpoints: (none)")
      }
      cat("\n")
    }
  } else {
    cat(sprintf("  cohorts     : %d analysed", nrow(x$labels)))
    if (length(x$dropped))
      cat(sprintf(" (%d dropped)", length(x$dropped)))
    cat("\n")
    cat(sprintf("  regimes     : %d\n", x$n_regimes))
    if (length(x$breakpoints)) {
      cat(sprintf("  breakpoints : %s\n",
                  paste(format(x$breakpoints, "%y.%m"), collapse = ", ")))
    } else {
      cat("  breakpoints : (none)\n")
    }
    ve <- (x$pca$sdev ^ 2) / sum(x$pca$sdev ^ 2)
    cat(sprintf("  PC1 / PC2   : %.1f%% / %.1f%%\n",
                ve[1L] * 100, ve[2L] * 100))
  }
  invisible(x)
}


#' Coerce a name token back to the type of a vector for comparison.
#'
#' Used internally by print.Regime / summary.Regime: group values are
#' stored as names (character) on `$n_regimes`, `$trajectory`, etc., but
#' the actual column type in `$labels[[grp]]` / `$breakpoints[[grp]]`
#' may be factor, character, or even Date. This converts the character
#' name back to a scalar of the column's type for `==` filtering.
#'
#' @keywords internal
.coerce_match <- function(name, vec) {
  if (is.factor(vec)) {
    return(factor(name, levels = levels(vec)))
  }
  if (inherits(vec, "Date")) {
    return(as.Date(name))
  }
  if (is.numeric(vec)) {
    return(as.numeric(name))
  }
  if (is.integer(vec)) {
    return(as.integer(name))
  }
  as.character(name)
}


#' @rdname detect_regime
#' @method summary Regime
#' @export
summary.Regime <- function(object, ...) {

  if (isTRUE(object$multi_group)) {
    grp <- object$group_var
    labels <- object$labels

    tbl <- labels[, .(
      n_cohorts = .N,
      start     = min(cohort),
      end       = max(cohort)
    ), by = c(grp, "regime_id", "regime")]
    data.table::setorderv(tbl, c(grp, "regime_id"))

    out <- list(
      method      = object$method,
      target      = object$target,
      dev_var     = object$dev_var,
      K           = object$K,
      group_var   = grp,
      multi_group = TRUE,
      n_cohorts   = nrow(labels),
      n_dropped   = sum(vapply(object$dropped, length, integer(1L))),
      n_regimes   = object$n_regimes,
      breakpoints = object$breakpoints,
      regimes     = tbl
    )
  } else {
    labels <- object$labels

    tbl <- labels[, .(
      n_cohorts = .N,
      start     = min(cohort),
      end       = max(cohort)
    ), by = .(regime_id, regime)]
    data.table::setorder(tbl, regime_id)

    out <- list(
      method      = object$method,
      target      = object$target,
      dev_var     = object$dev_var,
      K           = object$K,
      group_var   = object$group_var,
      multi_group = FALSE,
      n_cohorts   = nrow(labels),
      n_dropped   = length(object$dropped),
      n_regimes   = object$n_regimes,
      breakpoints = object$breakpoints,
      regimes     = tbl
    )
  }
  class(out) <- "summary.Regime"
  out
}


#' @rdname detect_regime
#' @method print summary.Regime
#' @export
print.summary.Regime <- function(x, ...) {
  cat("Cohort regime detection summary\n")
  cat(sprintf("  method    : %s\n", x$method))
  cat(sprintf("  target    : %s\n", x$target))
  cat(sprintf("  window    : %s 1-%d\n", x$dev_var, x$K))

  if (isTRUE(x$multi_group)) {
    grp <- x$group_var
    cat(sprintf("  groups    : %d (%s)\n",
                length(x$n_regimes), grp))
    cat(sprintf("  cohorts   : %d analysed", x$n_cohorts))
    if (x$n_dropped) cat(sprintf(" (%d dropped total)", x$n_dropped))
    cat("\n\n")

    for (gv in names(x$n_regimes)) {
      cat(sprintf("[%s] %d regime(s)\n", gv, x$n_regimes[[gv]]))
      sub <- x$regimes[x$regimes[[grp]] ==
                         .coerce_match(gv, x$regimes[[grp]])]
      for (i in seq_len(nrow(sub))) {
        r <- sub[i]
        cat(sprintf("  %d: %s-%s (%d cohorts)\n",
                    r$regime_id,
                    format(r$start, "%y.%m"),
                    format(r$end,   "%y.%m"),
                    r$n_cohorts))
      }
      bp_g <- x$breakpoints[x$breakpoints[[grp]] ==
                              .coerce_match(gv, x$breakpoints[[grp]])][["breakpoint"]]
      if (length(bp_g)) {
        cat(sprintf("  breakpoints: %s\n",
                    paste(format(bp_g, "%y.%m"), collapse = ", ")))
      }
      cat("\n")
    }
  } else {
    cat(sprintf("  cohorts   : %d analysed", x$n_cohorts))
    if (x$n_dropped) cat(sprintf(" (%d dropped)", x$n_dropped))
    cat("\n\n")

    cat(sprintf("Regimes (%d):\n", x$n_regimes))
    for (i in seq_len(nrow(x$regimes))) {
      r <- x$regimes[i]
      cat(sprintf("  %d: %s-%s (%d cohorts)\n",
                  r$regime_id,
                  format(r$start, "%y.%m"),
                  format(r$end,   "%y.%m"),
                  r$n_cohorts))
    }

    if (length(x$breakpoints)) {
      cat(sprintf("\nBreakpoints: %s\n",
                  paste(format(x$breakpoints, "%y.%m"), collapse = ", ")))
    }
  }
  invisible(x)
}

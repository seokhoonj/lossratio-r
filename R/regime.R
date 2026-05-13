# Cohort Regime Detection ---------------------------------------------------

#' Detect structural regime shifts across underwriting cohorts
#'
#' @description
#' Detect structural change points in the sequence of cohort-level
#' development trajectories. Each underwriting cohort (indexed by the
#' `cohort` of a `"Triangle"` object) is treated as a feature vector
#' whose entries are the selected `target` metric observed at development
#' periods `1, ..., window`. Cohorts are then ordered by underwriting
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
#' @param target Trajectory variable. Default is `"lr"` (cumulative loss
#'   ratio). Accepts any column on the `Triangle` (e.g. `"lr"`,
#'   `"loss"`, `"premium"`, `"loss_incr"`, `"premium_incr"`), plus three
#'   *diagnostic* derived targets computed inline per (group, cohort):
#'   \describe{
#'     \item{`"loss_ata"`}{Loss age-to-age factor
#'       `loss[k+1] / loss[k]` — multiplicative loss development speed
#'       (Mack's $f_k$).}
#'     \item{`"premium_ata"`}{Premium age-to-age factor — same form on
#'       premium.}
#'     \item{`"loss_ed"`}{Loss intensity
#'       `(loss[k] - loss[k-1]) / premium[k-1]` — additive,
#'       exposure-anchored (ED model's $g_k$).}
#'   }
#'   Derived targets drop the first dev row per cohort (no predecessor),
#'   then re-index `dev` so detection sees a contiguous sequence. See the
#'   `vignette("regime")` "Choice of target" section for guidance on
#'   which target matches which suspected event.
#' @param by Grouping column(s) for per-combination detection. `NULL`
#'   (default) reuses the Triangle's `attr(x, "groups")` when non-empty —
#'   so `detect_regime(tri)` dispatches per group automatically — and
#'   otherwise falls back to pooled detection. Pass `by = character(0)`
#'   to force pooled detection on a multi-group Triangle, or a character
#'   vector (subset of `names(x)`) to dispatch on an explicit combo,
#'   e.g. `by = "coverage"` or `by = c("channel", "coverage")`.
#' @param window Trajectory window. Integer (e.g., `12L`) for a fixed window, or
#'   the string `"auto"` (default) — resolves to each group's maturity
#'   via [detect_maturity()], falling back to `6L` when maturity is
#'   unavailable (NA, pooled mode, or `by` mismatching the Triangle's
#'   `attr("groups")`). Cohorts with fewer than the resolved `window`
#'   observed periods are dropped.
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
#'     \item{`target`}{Trajectory variable used for detection.}
#'     \item{`window`}{Trajectory window per combo. Scalar integer when a
#'       single combo was analysed; integer vector (one per surviving
#'       combo, in the order of `$labels` / `$breakpoints` group rows)
#'       otherwise.}
#'     \item{`window_mode`}{Either `"auto"` (resolved per group via
#'       [detect_maturity()]) or `"manual"` (user-supplied integer).}
#'     \item{`cohort`}{Period variable from `x`.}
#'     \item{`labels`}{`data.table` of one row per analysed cohort:
#'       `[by..., cohort, regime, regime_id]`. Group columns are prepended
#'       when `by` resolves to a non-empty vector.}
#'     \item{`breakpoints`}{`data.table` of detected breakpoints with
#'       columns `[by..., breakpoint, regime_id, pre_value, post_value,
#'       magnitude]`. `regime_id` = id of the regime that STARTS at this
#'       break (the pre-break regime is `regime_id - 1`); matches
#'       `$labels$regime_id`. `pre_value` / `post_value` are the mean
#'       `target` over the cohort × dev trajectory windows in the pre- /
#'       post-break regimes; `magnitude = |post_value - pre_value|`.
#'       Empty (zero rows) when no break is detected.}
#'     \item{`n_regimes`}{Number of regimes detected. Scalar integer for
#'       single-combo detection; named integer vector (keyed by combo) for
#'       multi-combo.}
#'     \item{`trajectory`}{Cohort × dev feature matrix used for detection.
#'       Single matrix when single combo; named list of matrices for
#'       multi-combo.}
#'     \item{`pca`}{`prcomp` object (single combo) or named list of
#'       `prcomp` objects (multi-combo).}
#'     \item{`dropped`}{Cohorts excluded due to the `window` window
#'       constraint. Vector (single) / named list (multi).}
#'     \item{`multi_group`}{Logical flag; `TRUE` when detection ran over
#'       multiple group combos.}
#'   }
#'
#' @seealso [plot.Regime()], [build_triangle()]
#'
#' @examples
#' \dontrun{
#' data(experience)
#' tri_sur <- build_triangle(
#'   experience[coverage == "SUR"],
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "loss_incr",
#'   premium  = "premium_incr"
#' )
#'
#' # Hierarchical clustering (no extra package dependency)
#' r <- detect_regime(tri_sur, method = "hclust",
#'                           n_regimes = 2L)
#' print(r)
#' summary(r)
#' plot(r)
#'
#' # ecp divisive change-point detection (requires the ecp package)
#' r_ecp <- detect_regime(tri_sur, method = "e_divisive")
#'
#' # Multi-group: detection per coverage
#' tri_all <- build_triangle(
#'   experience,
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "loss_incr",
#'   premium  = "premium_incr"
#' )
#' r_all <- detect_regime(tri_all, by = "coverage", method = "e_divisive")
#' print(r_all$breakpoints)
#' }
#'
#' @export
detect_regime <- function(x,
                          target    = "lr",
                          by        = NULL,
                          window         = "auto",
                          method    = c("e_divisive", "pelt", "hclust"),
                          n_regimes = NULL,
                          sig_level = 0.05,
                          min_size  = 3L,
                          ...) {

  .assert_triangle_input(x, "detect_regime()")
  method <- match.arg(method)

  coh <- attr(x, "cohort")
  dev <- attr(x, "dev")

  # `window = "auto"` falls back to maturity (`detect_maturity()`). The
  # default fallback when no maturity is detected (or pooled mode) is
  # `WINDOW_AUTO_FALLBACK` — small enough to keep recent cohorts in the
  # window for most coverages.
  WINDOW_AUTO_FALLBACK <- 6L
  window_is_auto <- identical(window, "auto")
  if (!window_is_auto) {
    window <- as.integer(window)
    if (is.na(window) || window < 2L)
      stop("`window` must be an integer >= 2 or the string \"auto\".",
           call. = FALSE)
  }

  # resolve grouping:
  #   by = NULL (default) → use `attr(x, "groups")` if non-empty, else pooled
  #   by = character(0)   → force pooled (single cohort sequence)
  #   by = character(.)   → explicit grouping columns
  grp <- if (is.null(by)) {
    g <- attr(x, "groups")
    if (is.null(g)) character(0) else g
  } else {
    by
  }

  if (length(coh) != 1L)
    stop("`x` must have exactly one `cohort`.", call. = FALSE)
  if (length(dev) != 1L)
    stop("`x` must have exactly one `dev`.", call. = FALSE)

  d <- .ensure_dt(x)

  # Derived targets (not native Triangle columns) — compute inline per
  # (group, cohort) before detection. These are diagnostic/experimental;
  # see `?detect_regime` for the recommended use case of each.
  derived <- c("loss_ata", "premium_ata", "loss_ed")
  if (target %in% derived) {
    grp_for_derive <- attr(x, "groups")
    if (is.null(grp_for_derive)) grp_for_derive <- character(0)
    d <- .derive_regime_target(d, target, grp = grp_for_derive)
  } else if (!(target %in% names(d))) {
    stop(sprintf("`target` = '%s' not found in `x`.", target),
         call. = FALSE)
  }

  missing_grp <- setdiff(grp, names(d))
  if (length(missing_grp))
    stop(sprintf("`by` columns not found in `x`: %s.",
                 paste(sprintf("'%s'", missing_grp), collapse = ", ")),
         call. = FALSE)

  call_obj <- match.call()

  multi_group <- length(grp) > 0L &&
                 nrow(unique(d[, grp, with = FALSE])) > 1L

  # Unified dispatch — single combo when `grp` is empty (pooled detection),
  # otherwise one combo per unique (group cols) row.
  if (length(grp) > 0L) {
    grp_combos <- unique(d[, grp, with = FALSE])
    data.table::setorderv(grp_combos, grp)
  } else {
    grp_combos <- data.table::data.table()
  }
  n_combos <- max(nrow(grp_combos), 1L)

  # `window = "auto"`: resolve per-combo trajectory window via detect_maturity.
  # Falls back to `WINDOW_AUTO_FALLBACK` when maturity is unavailable for that
  # combo (pooled detection, NA maturity, or by-columns mismatching the
  # Triangle's `attr("groups")`).
  window_per_combo <- if (window_is_auto) {
    # detect_maturity supports cumulative targets only — map _incr to its
    # cumulative counterpart, fall back to "lr" otherwise.
    mat_target <- switch(target,
      "lr" = , "loss" = , "premium" = target,
      "lr_incr"      = "lr",
      "loss_incr"    = "loss",
      "premium_incr" = "premium",
      "lr"
    )
    m_dt <- tryCatch(
      detect_maturity(x, target = mat_target),
      error = function(e) NULL
    )
    if (!is.null(m_dt) && length(grp) > 0L &&
        all(grp %in% names(m_dt)) &&
        "ata_to" %in% names(m_dt)) {
      vapply(seq_len(n_combos), function(i) {
        combo_row <- grp_combos[i]
        m <- m_dt[combo_row, on = grp, nomatch = NULL]
        v <- if (nrow(m)) m[["ata_to"]][1L] else NA_integer_
        if (is.na(v)) WINDOW_AUTO_FALLBACK else as.integer(v)
      }, integer(1L))
    } else {
      rep(WINDOW_AUTO_FALLBACK, n_combos)
    }
  } else {
    rep(as.integer(window), n_combos)
  }

  per_group <- vector("list", n_combos)
  combo_keys <- character(n_combos)

  for (i in seq_len(n_combos)) {
    if (nrow(grp_combos) > 0L) {
      combo_row <- grp_combos[i]
      combo_keys[i] <- paste(unlist(combo_row), collapse = " / ")
      di <- d[combo_row, on = grp, nomatch = NULL]
    } else {
      combo_keys[i] <- "<all>"
      di <- d
    }
    res_i <- tryCatch(
      .detect_regime_single(
        d         = di,
        target    = target,
        window         = window_per_combo[i],
        method    = method,
        n_regimes = n_regimes,
        sig_level = sig_level,
        min_size  = min_size,
        coh       = coh,
        dev       = dev
      ),
      error = function(e) {
        warning(sprintf("Group '%s': %s -- skipped.", combo_keys[i],
                        conditionMessage(e)), call. = FALSE)
        NULL
      }
    )
    per_group[i] <- list(res_i)  # preserve NULL slot
  }
  names(per_group) <- combo_keys

  ok <- !vapply(per_group, is.null, logical(1L))
  if (!any(ok))
    stop("No group produced a usable detection result.", call. = FALSE)

  empty_bp <- data.table::data.table(
    breakpoint = as.Date(character(0)),
    regime_id  = integer(0),
    pre_value  = numeric(0),
    post_value = numeric(0),
    magnitude  = numeric(0)
  )

  # Combine breakpoints: prepend group columns when grp is non-empty.
  bp_dt_list <- lapply(which(ok), function(i) {
    bp <- per_group[[i]]$breakpoints
    if (!nrow(bp)) return(NULL)
    if (length(grp) > 0L) {
      combo_rep <- grp_combos[rep(i, nrow(bp))]
      bp <- cbind(combo_rep, bp)
    }
    bp
  })
  bp_dt_list <- bp_dt_list[!vapply(bp_dt_list, is.null, logical(1L))]
  bp_dt <- if (length(bp_dt_list)) {
    data.table::rbindlist(bp_dt_list)
  } else if (length(grp) > 0L) {
    cbind(grp_combos[0L], empty_bp)
  } else {
    empty_bp
  }

  # Combine labels: prepend group columns when grp is non-empty.
  label_rows <- lapply(which(ok), function(i) {
    lab <- data.table::copy(per_group[[i]]$labels)
    if (length(grp) > 0L) {
      combo_rep <- grp_combos[rep(i, nrow(lab))]
      lab <- cbind(combo_rep, lab)
    }
    lab
  })
  labels_dt <- data.table::rbindlist(label_rows)

  n_regimes_vec  <- vapply(per_group[ok], `[[`, integer(1L), "n_regimes")
  trajectory_lst <- lapply(per_group[ok], `[[`, "trajectory")
  pca_lst        <- lapply(per_group[ok], `[[`, "pca")
  dropped_lst    <- lapply(per_group[ok], `[[`, "dropped")

  # Single-combo unwrap — preserves the scalar / matrix / prcomp shapes
  # that downstream code (and existing tests) expect when only one group
  # combo is detected. `$breakpoints` and `$labels` remain data.tables.
  is_single <- sum(ok) == 1L
  window_used <- window_per_combo[ok]
  if (is_single) {
    n_regimes_out  <- n_regimes_vec[[1L]]
    trajectory_out <- trajectory_lst[[1L]]
    pca_out        <- pca_lst[[1L]]
    dropped_out    <- dropped_lst[[1L]]
    window_out          <- window_used[[1L]]
  } else {
    n_regimes_out  <- n_regimes_vec
    trajectory_out <- trajectory_lst
    pca_out        <- pca_lst
    dropped_out    <- dropped_lst
    window_out          <- window_used
  }

  out <- list(
    call        = call_obj,
    method      = method,
    target      = target,
    window           = window_out,
    window_mode      = if (window_is_auto) "auto" else "manual",
    cohort      = coh,
    dev         = dev,
    groups      = grp,
    multi_group = !is_single,
    labels      = labels_dt,
    breakpoints = bp_dt,
    n_regimes   = n_regimes_out,
    trajectory  = trajectory_out,
    pca         = pca_out,
    dropped     = dropped_out
  )
  class(out) <- "Regime"
  out
}


# Internal helpers --------------------------------------------------------

#' Derive a non-native regime detection target
#'
#' @description
#' Computes diagnostic / experimental detection targets that are not stored
#' directly on the Triangle:
#' \describe{
#'   \item{`loss_ata`}{Loss age-to-age factor — `loss[k+1] / loss[k]` per
#'     (group, cohort). Captures *multiplicative* development speed.}
#'   \item{`premium_ata`}{Premium age-to-age factor — same form on premium.
#'     Captures premium *recognition speed*.}
#'   \item{`loss_ed`}{Loss intensity (ED model's $g_k$) —
#'     `(loss[k] - loss[k-1]) / premium[k-1]` per (group, cohort).
#'     *Additive*, exposure-anchored.}
#' }
#'
#' The first dev row per cohort is NA (no predecessor). Downstream
#' `.detect_regime_single` handles NA-tolerant aggregation.
#'
#' @keywords internal
.derive_regime_target <- function(d, target, grp = character(0)) {
  by_cols <- c(grp, "cohort")
  d <- data.table::copy(d)

  if (target == "loss_ata") {
    d[, loss_ata := loss / data.table::shift(loss, 1L, type = "lag"),
      by = by_cols]
  } else if (target == "premium_ata") {
    d[, premium_ata := premium / data.table::shift(premium, 1L, type = "lag"),
      by = by_cols]
  } else if (target == "loss_ed") {
    d[, loss_ed := (loss - data.table::shift(loss, 1L, type = "lag")) /
                   data.table::shift(premium, 1L, type = "lag"),
      by = by_cols]
  } else {
    stop(sprintf("Unknown derived target: '%s'.", target), call. = FALSE)
  }

  # Drop the first dev row per cohort (NA from shift), then re-index dev
  # so the first valid observation becomes dev=1. This lets downstream
  # `.detect_regime_single` apply the same `dev <= window` and
  # `n >= window` filters without manual adjustment for the lost dev=1.
  d <- d[is.finite(d[[target]])]
  d[, dev := dev - 1L]
  d
}


#' Single-group regime detection
#'
#' Core single-group routine used by [detect_regime()]. Takes a
#' pre-filtered data.table `d` (single group) and returns a list with
#' the per-group Regime fields. Multi-group dispatch lives in
#' [detect_regime()] itself.
#'
#' @keywords internal
.detect_regime_single <- function(d, target, window, method,
                                  n_regimes, sig_level, min_size,
                                  coh, dev) {

  d <- d[d[["dev"]] <= window]
  n_obs <- d[, .(n = .N), by = c("cohort")]
  ok <- n_obs[n >= window][["cohort"]]
  dropped <- setdiff(unique(d[["cohort"]]), ok)

  d <- d[d[["cohort"]] %in% ok]
  if (!nrow(d))
    stop("No cohorts have >= window observed development periods. Reduce `window`.",
         call. = FALSE)

  w <- data.table::dcast(
    d, stats::reformulate("dev", response = "cohort"),
    value.var     = target,
    fun.aggregate = function(v) mean(v, na.rm = TRUE)
  )
  data.table::setorderv(w, "cohort")

  mat <- as.matrix(w[, !"cohort", with = FALSE])
  rownames(mat) <- as.character(w[["cohort"]])

  if (anyNA(mat))
    stop("Feature matrix contains NA. Reduce `window` or check input.",
         call. = FALSE)

  n_cohorts <- nrow(mat)
  if (n_cohorts < 2L * max(min_size, 1L))
    stop("Too few cohorts after filtering. Reduce `window` or `min_size`.",
         call. = FALSE)

  pca <- stats::prcomp(mat, scale. = TRUE)

  breakpoints_idx <- .regime_breakpoints(
    mat       = mat,
    pca       = pca,
    method    = method,
    n_regimes = n_regimes,
    sig_level = sig_level,
    min_size  = min_size
  )

  regime_id <- .regime_ids_from_breaks(n_cohorts, breakpoints_idx)
  regime_label <- .regime_label_from_range(w[["cohort"]], regime_id)

  labels <- data.table::data.table(
    period    = w[["cohort"]],
    regime    = factor(regime_label, levels = unique(regime_label)),
    regime_id = regime_id
  )
  data.table::setnames(labels, "period", "cohort")

  breakpoints <- .build_breakpoints_dt(
    cohorts         = w[["cohort"]],
    breakpoints_idx = breakpoints_idx,
    mat             = mat,
    regime_id       = regime_id
  )

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
.build_breakpoints_dt <- function(cohorts, breakpoints_idx, mat, regime_id) {
  empty <- data.table::data.table(
    breakpoint = as.Date(character(0)),
    regime_id  = integer(0),
    pre_value  = numeric(0),
    post_value = numeric(0),
    magnitude  = numeric(0)
  )
  if (!length(breakpoints_idx)) return(empty)

  bp_idx  <- as.integer(sort(unique(breakpoints_idx)))
  bp_date <- cohorts[bp_idx]
  # `regime_id` on a break row = id of the regime that STARTS at this break
  # (i.e. the post-break regime). `regime_id - 1` is the pre-break regime.
  bp_id   <- seq_along(bp_idx) + 1L

  metas <- vapply(seq_along(bp_idx), function(i) {
    pre_rows  <- which(regime_id == bp_id[i] - 1L)
    post_rows <- which(regime_id == bp_id[i])
    pre_val   <- if (length(pre_rows))  mean(mat[pre_rows,  , drop = FALSE], na.rm = TRUE) else NA_real_
    post_val  <- if (length(post_rows)) mean(mat[post_rows, , drop = FALSE], na.rm = TRUE) else NA_real_
    c(pre_val, post_val)
  }, numeric(2L))

  pre_vals  <- metas[1L, ]
  post_vals <- metas[2L, ]

  data.table::data.table(
    breakpoint = bp_date,
    regime_id  = bp_id,
    pre_value  = pre_vals,
    post_value = post_vals,
    magnitude  = abs(post_vals - pre_vals)
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
                                   Q         = as.integer(n_regimes - 1L),
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
  cat(sprintf("  method : %s\n", x$method))
  cat(sprintf("  target : %s\n", x$target))

  if (isTRUE(x$multi_group)) {
    grp      <- x$groups
    grp_vals <- names(x$n_regimes)
    K_vec    <- if (length(x$window) == length(grp_vals)) x$window
                else rep(x$window[[1L]], length(grp_vals))

    cat(sprintf("  groups : %d (%s)\n", length(grp_vals), grp))

    n_coh  <- integer(length(grp_vals))
    n_drop <- integer(length(grp_vals))
    bp_str <- character(length(grp_vals))
    for (i in seq_along(grp_vals)) {
      gv         <- grp_vals[i]
      n_coh[i]   <- nrow(x$labels[x$labels[[grp]] ==
                                    .coerce_match(gv, x$labels[[grp]])])
      n_drop[i]  <- length(x$dropped[[gv]])
      bp_g       <- x$breakpoints[x$breakpoints[[grp]] ==
                                    .coerce_match(gv, x$breakpoints[[grp]])][["breakpoint"]]
      bp_str[i]  <- if (length(bp_g))
                      paste(format(bp_g, "%y.%m"), collapse = ", ")
                    else "(none)"
    }

    # Right-align the dropped-count digit so paren contents line up
    # vertically across groups (e.g., "( 8 dropped)" vs "(11 dropped)").
    drop_w   <- max(nchar(format(n_drop)), 0L)
    drop_str <- ifelse(
      n_drop > 0L,
      sprintf(paste0("(%", drop_w, "d dropped)"), n_drop),
      ""
    )

    cols <- list(
      label    = sprintf("[%s]",          grp_vals),
      window   = sprintf("%s 1-%d",       x$dev, K_vec),
      cohorts  = sprintf("cohorts: %d",   n_coh),
      dropped  = drop_str,
      regimes  = sprintf("regimes: %d",   as.integer(x$n_regimes[grp_vals])),
      brkpts   = sprintf("breakpoints: %s", bp_str)
    )
    rows <- .format_record_table(
      cols,
      justify = c("left", "left", "left", "left", "left", "left")
    )
    for (row in rows) cat("    ", row, "\n", sep = "")
  } else {
    cat(sprintf("  window (window) : %s 1-%d\n", x$dev, x$window))
    cat(sprintf("  cohorts    : %d analysed", nrow(x$labels)))
    if (length(x$dropped))
      cat(sprintf(" (%d dropped)", length(x$dropped)))
    cat("\n")
    cat(sprintf("  regimes    : %d\n", x$n_regimes))
    if (nrow(x$breakpoints)) {
      cat(sprintf("  breakpoints: %s\n",
                  paste(format(x$breakpoints[["breakpoint"]], "%y.%m"),
                        collapse = ", ")))
    } else {
      cat("  breakpoints: (none)\n")
    }
    ve <- (x$pca$sdev ^ 2) / sum(x$pca$sdev ^ 2)
    cat(sprintf("  PC1 / PC2  : %.1f%% / %.1f%%\n",
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
    grp <- object$groups
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
      dev         = object$dev,
      window           = object$window,
      groups      = grp,
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
      dev         = object$dev,
      window           = object$window,
      groups      = object$groups,
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
  cat(sprintf("  window    : %s 1-%d\n", x$dev, x$window))

  if (isTRUE(x$multi_group)) {
    grp <- x$groups
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

    if (nrow(x$breakpoints)) {
      cat(sprintf("\nBreakpoints: %s\n",
                  paste(format(x$breakpoints[["breakpoint"]], "%y.%m"),
                        collapse = ", ")))
    }
  }
  invisible(x)
}

# Age-to-age maturity -----------------------------------------------------

#' Find ata maturity by group
#'
#' @description
#' Identify the first mature age-to-age (ata) link from a `Triangle`.
#' Internally builds a single-variable `Link` table, computes the
#' per-link diagnostic via [summary.Link()] with `model = "ata"`, and
#' then locates the first link whose statistics satisfy all maturity
#' criteria.
#'
#' Maturity is determined using a combination of:
#' \itemize{
#'   \item `cv < max_cv`
#'   \item `rse < max_rse`
#'   \item `valid_ratio >= min_valid_ratio`
#'   \item `n_valid >= min_n_valid`
#'   \item optional consecutive maturity over `min_run` ata links
#' }
#'
#' Both `cv` and `rse` must be satisfied simultaneously. `cv` captures
#' the raw variability of observed ata factors across cohorts, while `rse`
#' reflects the precision of the WLS-estimated factor. Using both criteria
#' together provides a more robust maturity assessment than either alone.
#'
#' Default `target = "loss"` (cumulative loss). Maturity in chain
#' ladder is methodologically a property of *loss* development:
#' the ATA factors of cumulative loss stabilize when chain ladder
#' becomes reliable, which in turn makes downstream LR projection
#' reliable. ATA factors of `lr` itself (a ratio of two cumulative
#' quantities) carry additional noise and tend to give less precise
#' maturity decisions. Override `target` only when you specifically
#' want maturity of premium development or another cumulative metric.
#'
#' @param x A `Triangle` object.
#' @param target Cumulative metric for the link factor. Default
#'   `"loss"` (chain-ladder convention; see Description). Forwarded to
#'   [as_link()].
#' @param groups Optional `character` subset of `attr(x, "groups")`
#'   selecting which columns define the maturity partition. Maturity is
#'   typically a structural property of the development curve driven by
#'   coverage rather than by demographic mix (age, channel, ...), so a
#'   Triangle aggregated by `c("coverage", "age_band", "channel")` may
#'   still want a per-coverage maturity. `NULL` (default) keeps the
#'   current Triangle grouping (fully backward compatible).
#'   `character(0)` pools across all groups and returns a single global
#'   maturity row. Any non-`NULL`, non-empty value must be a subset of
#'   `attr(x, "groups")`; column order is irrelevant. When the requested
#'   `groups` is coarser than the Triangle grouping, the underlying
#'   `loss` / `premium` / `lr` columns are re-aggregated to the coarser
#'   partition before computing ata links.
#' @param weight Optional WLS weight variable. Forwarded to
#'   [as_link()].
#' @param alpha Numeric scalar controlling the variance structure in
#'   the underlying WLS fit. Default `1`. Forwarded to [summary.Link()].
#' @param max_cv Maximum allowed coefficient of variation.
#'   Default is `0.15`.
#' @param max_rse Maximum allowed relative standard error.
#'   Default is `0.05`.
#' @param min_valid_ratio Minimum proportion of finite ata values required.
#'   Default is `0.5`.
#' @param min_n_valid Minimum number of finite ata factors required.
#'   Default is `3L`.
#' @param min_run Minimum number of consecutive ata links satisfying the
#'   maturity criteria. Default is `2L`.
#'
#' @return A `data.table` with class `"Maturity"` containing one row
#'   per group. Columns include `ata_from`, `change` (the maturity
#'   point, i.e. the `to`-index of the first mature ata link),
#'   `ata_link`, and the diagnostic statistics (`mean`, `median`,
#'   `wt`, `cv`, `f`, `f_se`, `rse`, `sigma`, `n_cohorts`, `n_valid`,
#'   `n_inf`, `n_nan`, `valid_ratio`). If no mature link is found,
#'   all values for that group are `NA`.
#'
#' @export
detect_maturity <- function(x,
                            target          = "loss",
                            groups          = NULL,
                            weight          = NULL,
                            alpha           = 1,
                            max_cv          = 0.15,
                            max_rse         = 0.05,
                            min_valid_ratio = 0.5,
                            min_n_valid     = 3L,
                            min_run         = 2L) {

  .assert_triangle_input(x, "detect_maturity()")

  x <- .rebucket_triangle_groups(x, groups)

  link <- as_link(x, target = target, weight = weight)
  ata_summary <- summary(link, model = "ata", alpha = alpha)

  .detect_maturity(
    ata_summary,
    max_cv          = max_cv,
    max_rse         = max_rse,
    min_valid_ratio = min_valid_ratio,
    min_n_valid     = min_n_valid,
    min_run         = min_run
  )
}


#' Internal: locate the first mature ata link from an `ATASummary`
#'
#' @keywords internal
.detect_maturity <- function(x,
                             max_cv          = 0.15,
                             max_rse         = 0.05,
                             min_valid_ratio = 0.5,
                             min_n_valid     = 3L,
                             min_run         = 2L) {

  .assert_class(x, "ATASummary")

  if (!is.numeric(max_cv) || length(max_cv) != 1L ||
      is.na(max_cv))
    stop("`max_cv` must be a single non-missing numeric value.",
         call. = FALSE)

  if (!is.numeric(max_rse) || length(max_rse) != 1L ||
      is.na(max_rse))
    stop("`max_rse` must be a single non-missing numeric value.",
         call. = FALSE)

  if (!is.numeric(min_valid_ratio) || length(min_valid_ratio) != 1L ||
      is.na(min_valid_ratio))
    stop("`min_valid_ratio` must be a single non-missing numeric value.",
         call. = FALSE)

  if (!is.numeric(min_n_valid) || length(min_n_valid) != 1L ||
      is.na(min_n_valid))
    stop("`min_n_valid` must be a single non-missing numeric value.",
         call. = FALSE)

  if (!is.numeric(min_run) || length(min_run) != 1L ||
      is.na(min_run) || min_run < 1)
    stop("`min_run` must be a single integer >= 1.", call. = FALSE)

  min_n_valid <- as.integer(min_n_valid)
  min_run     <- as.integer(min_run)

  smr <- .copy_dt(x)
  grp <- attr(x, "groups")
  if (is.null(grp)) grp <- character(0)

  # internal: find first mature row in a single-group summary table
  .first_mature_row <- function(d,
                                max_cv,
                                max_rse,
                                min_valid_ratio,
                                min_n_valid,
                                min_run) {

    d  <- .copy_dt(d)
    ok <- with(d,
               is.finite(cv)          & cv          <  max_cv    &
                 is.finite(rse)         & rse         <  max_rse   &
                 is.finite(valid_ratio) & valid_ratio >= min_valid_ratio &
                 is.finite(n_valid)     & n_valid     >= min_n_valid
    )

    idx <- NA_integer_

    if (min_run == 1L) {
      idx <- which(ok)[1L]
    } else if (length(ok) >= min_run) {
      for (i in seq_len(length(ok) - min_run + 1L)) {
        if (all(ok[i:(i + min_run - 1L)])) { idx <- i; break }
      }
    }

    if (length(idx) == 0L || is.na(idx)) {
      return(data.table::data.table(
        ata_from    = NA_real_,
        change      = NA_real_,
        ata_link    = NA_character_,
        mean        = NA_real_,
        median      = NA_real_,
        wt          = NA_real_,
        cv          = NA_real_,
        f           = NA_real_,
        f_se        = NA_real_,
        rse         = NA_real_,
        sigma       = NA_real_,
        n_cohorts       = NA_real_,
        n_valid     = NA_real_,
        n_inf       = NA_real_,
        n_nan       = NA_real_,
        valid_ratio = NA_real_
      ))
    }

    # Coerce all numeric outputs to double so the no-match branch
    # (NA_real_) and the match branch share types across groups
    # (data.table grouped-j requires stable column types).
    data.table::data.table(
      ata_from    = as.numeric(d$ata_from[idx]),
      change      = as.numeric(d$ata_to[idx]),
      ata_link    = as.character(d$ata_link[idx]),
      mean        = as.numeric(d$mean[idx]),
      median      = as.numeric(d$median[idx]),
      wt          = as.numeric(d$wt[idx]),
      cv          = as.numeric(d$cv[idx]),
      f           = as.numeric(d$f[idx]),
      f_se        = as.numeric(d$f_se[idx]),
      rse         = as.numeric(d$rse[idx]),
      sigma       = as.numeric(d$sigma[idx]),
      n_cohorts       = as.numeric(d$n_cohorts[idx]),
      n_valid     = as.numeric(d$n_valid[idx]),
      n_inf       = as.numeric(d$n_inf[idx]),
      n_nan       = as.numeric(d$n_nan[idx]),
      valid_ratio = as.numeric(d$valid_ratio[idx])
    )
  }

  if (length(grp)) {
    z <- smr[, .first_mature_row(
      .SD,
      max_cv          = max_cv,
      max_rse         = max_rse,
      min_valid_ratio = min_valid_ratio,
      min_n_valid     = min_n_valid,
      min_run         = min_run
    ), by = grp]
  } else {
    z <- .first_mature_row(
      smr,
      max_cv          = max_cv,
      max_rse         = max_rse,
      min_valid_ratio = min_valid_ratio,
      min_n_valid     = min_n_valid,
      min_run         = min_run
    )
  }

  data.table::setattr(z, "max_cv",    max_cv)
  data.table::setattr(z, "max_rse",   max_rse)
  data.table::setattr(z, "min_valid_ratio", min_valid_ratio)
  data.table::setattr(z, "min_n_valid",     min_n_valid)
  data.table::setattr(z, "min_run",         min_run)
  data.table::setattr(z, "groups",       grp)
  data.table::setattr(z, "target",          attr(x, "target"))
  data.table::setattr(z, "weight",          attr(x, "weight"))

  .prepend_class(z, "Maturity")
}


#' Internal: rebucket a `Triangle` to a coarser `groups` partition
#'
#' Re-aggregates `loss` / `premium` / `loss_incr` / `premium_incr` over
#' the dropped grouping columns and recomputes `lr` / `lr_incr` as
#' ratios of the aggregated totals. Other cell-level columns
#' (`margin`, `profit`, `loss_share`, ...) are not regenerated -- the
#' rebucketed object is intended for `as_link()` consumption only.
#'
#' @param x A `Triangle` object.
#' @param groups `NULL`, `character(0)`, or a `character` subset of
#'   `attr(x, "groups")`. `NULL` returns `x` unchanged.
#'
#' @return A `Triangle` with `attr(., "groups")` set to the requested
#'   value and `loss` / `premium` / `lr` aggregated to the requested
#'   partition.
#'
#' @keywords internal
.rebucket_triangle_groups <- function(x, groups) {

  if (is.null(groups)) return(x)

  if (!is.character(groups))
    stop("`groups` must be `NULL` or a character vector.", call. = FALSE)

  grp_orig <- attr(x, "groups")
  if (is.null(grp_orig)) grp_orig <- character(0)

  if (length(groups)) {
    bad <- setdiff(groups, grp_orig)
    if (length(bad))
      stop(
        sprintf(
          "`groups` must be a subset of `attr(x, \"groups\")`. Unknown column(s): %s.",
          paste(sprintf("`%s`", bad), collapse = ", ")
        ),
        call. = FALSE
      )
  }

  # No-op when requested grouping matches the Triangle's (order-insensitive).
  if (setequal(groups, grp_orig)) {
    z <- .copy_dt(x)
    # Preserve original group column order to keep as_link's setorderv stable.
    data.table::setattr(z, "groups"  , grp_orig)
    data.table::setattr(z, "cohort"  , attr(x, "cohort"))
    data.table::setattr(z, "calendar", attr(x, "calendar"))
    data.table::setattr(z, "grain"   , attr(x, "grain"))
    data.table::setattr(z, "dev"     , attr(x, "dev"))
    data.table::setattr(z, "loss"    , attr(x, "loss"))
    data.table::setattr(z, "premium" , attr(x, "premium"))
    return(.prepend_class(z, "Triangle"))
  }

  dt <- .copy_dt(x)

  # Columns we re-aggregate. Only sum-additive primitives; ratios (lr) are
  # recomputed from the aggregated totals.
  sum_cols <- intersect(
    c("loss", "loss_incr", "premium", "premium_incr", "n_cohorts"),
    names(dt)
  )
  by_cols <- c(groups, "cohort", "dev")

  agg <- dt[, lapply(.SD, sum, na.rm = TRUE),
            by      = by_cols,
            .SDcols = sum_cols]

  if (all(c("loss", "premium") %in% names(agg)))
    agg[, ("lr") := loss / premium]
  if (all(c("loss_incr", "premium_incr") %in% names(agg)))
    agg[, ("lr_incr") := loss_incr / premium_incr]

  data.table::setorderv(agg, by_cols)

  data.table::setattr(agg, "groups"  , groups)
  data.table::setattr(agg, "cohort"  , attr(x, "cohort"))
  data.table::setattr(agg, "calendar", attr(x, "calendar"))
  data.table::setattr(agg, "grain"   , attr(x, "grain"))
  data.table::setattr(agg, "dev"     , attr(x, "dev"))
  data.table::setattr(agg, "loss"    , attr(x, "loss"))
  data.table::setattr(agg, "premium" , attr(x, "premium"))

  .prepend_class(agg, "Triangle")
}


# Manual Maturity construction --------------------------------------------

#' Construct a Maturity object from manually specified maturity points
#'
#' @description
#' User-facing helper for hand-specifying a maturity point (or a set of
#' per-group maturity points) without running [detect_maturity()]. The
#' returned `"Maturity"` object plugs into any function that consumes a
#' Maturity result -- `fit_lr()`, `fit_loss()`, [backtest()], and the
#' maturity input dispatcher -- by carrying the same row schema as
#' [detect_maturity()] output (group columns plus `ata_from`, `change`,
#' `ata_link`).
#'
#' Use this when company-standard or domain-knowledge maturity points
#' are known a priori and you want to override the data-driven
#' detection. Stat columns (`mean`, `cv`, `f`, `rse`, ...) are set to
#' `NA_real_` because manual entry carries no estimates.
#'
#' Argument syntax mirrors `data.frame()` / `data.table()`: named
#' vectors of equal length, one of which **must** be `change` (the
#' maturity point, an integer dev index). Any other named arguments are
#' treated as group columns.
#'
#' @param ... Named vectors of equal length. Must include `change`
#'   (coercible to integer; the maturity point, i.e. the `to`-index of
#'   the first mature ata link). Any other named arguments are
#'   interpreted as group column values (e.g. `coverage`, `channel`).
#'   With no group columns the result is a pooled (single-row)
#'   Maturity.
#'
#' @return A `data.table` with class `"Maturity"` carrying the same
#'   columns as [detect_maturity()] output: group columns (if any),
#'   `ata_from = change - 1L`, `change`, `ata_link = "<from>-<to>"`,
#'   and the diagnostic stat columns (`mean`, `median`, `wt`, `cv`,
#'   `f`, `f_se`, `rse`, `sigma`, `n_cohorts`, `n_valid`, `n_inf`, `n_nan`,
#'   `valid_ratio`) set to `NA_real_`. `attr(., "groups")` holds the
#'   group column names (possibly `character(0)`).
#'
#' @seealso [detect_maturity()], [regime_at()]
#'
#' @examples
#' \dontrun{
#' # Single-group manual override
#' maturity_at(coverage = "SUR", change = 4)
#'
#' # Multi-group manual override (e.g. company-standard k*)
#' maturity_at(coverage = c("CAN", "CI", "HOS", "SUR"),
#'             change   = c(   9,   10,     7,     4))
#'
#' # Pooled (no group columns)
#' maturity_at(change = 5)
#' }
#'
#' @export
maturity_at <- function(...) {
  args <- list(...)
  nms  <- names(args)

  if (is.null(nms) || any(!nzchar(nms)))
    stop("All arguments to `maturity_at()` must be named.", call. = FALSE)
  if (!"change" %in% nms)
    stop("`maturity_at()` requires a `change` argument.", call. = FALSE)

  lens <- vapply(args, length, integer(1L))
  if (length(unique(lens)) != 1L)
    stop(sprintf(
      "All arguments must have equal length; got lengths: %s.",
      paste(sprintf("%s=%d", nms, lens), collapse = ", ")
    ), call. = FALSE)
  if (lens[[1L]] == 0L)
    stop("`maturity_at()` arguments must have length >= 1.", call. = FALSE)

  change_raw <- args[["change"]]
  change <- tryCatch(as.integer(change_raw),
                     error = function(e)
                       stop(sprintf("Failed to coerce `change` to integer: %s",
                                    conditionMessage(e)), call. = FALSE))
  if (any(is.na(change)))
    stop("`change` contains NA after coercion to integer.", call. = FALSE)

  grp <- setdiff(nms, "change")
  grp_cols <- args[grp]

  ata_from <- change - 1L
  ata_link <- sprintf("%s-%s", ata_from, change)
  n        <- length(change)

  stat_cols <- data.table::data.table(
    ata_from    = as.numeric(ata_from),
    change      = as.numeric(change),
    ata_link    = ata_link,
    mean        = rep(NA_real_, n),
    median      = rep(NA_real_, n),
    wt          = rep(NA_real_, n),
    cv          = rep(NA_real_, n),
    f           = rep(NA_real_, n),
    f_se        = rep(NA_real_, n),
    rse         = rep(NA_real_, n),
    sigma       = rep(NA_real_, n),
    n_cohorts       = rep(NA_real_, n),
    n_valid     = rep(NA_real_, n),
    n_inf       = rep(NA_real_, n),
    n_nan       = rep(NA_real_, n),
    valid_ratio = rep(NA_real_, n)
  )

  out <- if (length(grp)) {
    data.table::data.table(
      do.call(data.table::data.table, grp_cols),
      stat_cols
    )
  } else {
    stat_cols
  }

  data.table::setattr(out, "groups", grp)
  data.table::setattr(out, "target", NA_character_)
  data.table::setattr(out, "weight", NA_character_)

  class(out) <- c("Maturity", "data.table", "data.frame")
  out
}


# Lazy maturity detection spec --------------------------------------------

#' Build a lazy maturity detection spec
#'
#' @description
#' Captures [detect_maturity()] arguments without running detection.
#' Returns a closure that the consumer (fit_* or [backtest()]) invokes
#' on its own *internal* triangle. The point is **conditional /
#' deferred** detection -- the value of $k^*$ depends on which cells the
#' caller decides to expose:
#'
#' * In `fit_lr()` / `fit_loss()`, the spec is invoked on the *full*
#'   triangle the user passed in.
#'
#' * In [backtest()], **the spec is invoked on the masked triangle of
#'   each holdout fold**, *never* on the full triangle. Held-out
#'   diagonals are removed before [detect_maturity()] sees the data, so
#'   the detected $k^*$ depends only on cells the masked fit can also
#'   see. This is the leakage-safe contract of `maturity_spec()`.
#'
#' Contrast with [maturity_at()], which produces an eager `"Maturity"`
#' object whose value is fixed at construction time (independent of the
#' fold's masked data).
#'
#' Use `maturity_spec()` when you want $k^*$ to be **re-detected per
#' fold** so backtest honestly answers "given the data available at this
#' fold, what would I have picked?" Use `maturity_at()` when you want a
#' fixed value tested across folds.
#'
#' @param ... kwargs passed verbatim to [detect_maturity()] when the
#'   spec is invoked (e.g. `target`, `groups`, `min_run`, `max_cv`,
#'   `max_rse`, `min_valid_ratio`, `min_n_valid`).
#'
#' @return A function of one argument (a `"Triangle"`) returning a
#'   `"Maturity"` object. The caller decides which triangle to pass
#'   (full vs. masked); inside [backtest()] this is always the masked
#'   training triangle.
#'
#' @seealso [detect_maturity()], [maturity_at()], [backtest()]
#'
#' @examples
#' \dontrun{
#' # Capture detection arguments, defer execution until fit time.
#' spec <- maturity_spec(min_run = 2, max_cv = 0.04)
#'
#' # In fit_lr(): closure is invoked on the user's `tri`.
#' fit <- fit_lr(tri, maturity = maturity_spec(min_run = 2))
#'
#' # In backtest(): closure is invoked on the *masked* triangle of
#' # each holdout fold, so detected k* never peeks at held-out cells.
#' bt <- backtest(tri, holdout = 6L,
#'                maturity = maturity_spec(min_run = 2, max_cv = 0.04))
#' }
#'
#' @export
maturity_spec <- function(...) {
  args <- list(...)
  function(tri) do.call(detect_maturity, c(list(x = tri), args))
}

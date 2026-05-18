#' Bornhuetter-Ferguson projection
#'
#' @description
#' Fit a Bornhuetter-Ferguson (1972) projection from a `"Triangle"`
#' object. The BF estimator blends the *observed* cumulative loss for
#' each cohort with an *a priori* expected loss ratio (ELR) applied to
#' the cohort's ultimate exposure, weighted by the expected unemerged
#' fraction \eqn{1 - q_i}:
#'
#' \deqn{\hat L_{ult, i}^{BF} = L_{obs, i} +
#'   (1 - q_i) \cdot \mathrm{ELR}_i \cdot E_i^{ult}}
#'
#' where
#' \itemize{
#'   \item \eqn{L_{obs, i}}: cohort \eqn{i}'s observed cumulative loss
#'     at its latest observed development period.
#'   \item \eqn{q_i = L_{obs, i} / \hat L_{ult, i}^{CL}}: the *expected
#'     emerged fraction*, equivalent to the inverse of the cumulative
#'     loss development factor (LDF) for cohort \eqn{i}.
#'   \item \eqn{\mathrm{ELR}_i}: the user-supplied a priori expected loss
#'     ratio for cohort \eqn{i} (`prior` argument).
#'   \item \eqn{E_i^{ult}}: cohort \eqn{i}'s ultimate exposure, projected
#'     via chain ladder on the `exposure` column.
#' }
#'
#' This is a *standalone* worker -- it does not currently integrate with
#' [fit_loss()] / [fit_ratio()]. Point projection only; analytical MSEP
#' (Mack 2008) is not yet computed.
#'
#' @param x A `Triangle` object.
#' @param loss A single cumulative loss variable to project. Default
#'   `"loss"`.
#' @param exposure A single cumulative exposure variable used as the
#'   denominator of the prior ELR. Default `"exposure"`.
#' @param prior The a priori expected loss ratio. Accepts:
#'   \describe{
#'     \item{single numeric}{Applied uniformly to every cohort.}
#'     \item{`data.frame` with columns `cohort` and `elr`}{Per-cohort
#'       ELR. Must cover every cohort present in `x` (extras are
#'       silently dropped, missing cohorts raise an error).}
#'   }
#' @param ... Reserved for future extension (currently unused).
#'
#' @return An object of class `"BFFit"` containing:
#'   \describe{
#'     \item{`call`}{The matched call.}
#'     \item{`data`}{The input `Triangle`.}
#'     \item{`method`}{`"bf"`.}
#'     \item{`groups`}{Grouping variable names.}
#'     \item{`cohort`}{Raw cohort variable name.}
#'     \item{`dev`}{Raw development variable name.}
#'     \item{`loss`, `exposure`}{Loss / exposure variable names.}
#'     \item{`full`}{`data.table` `[group, cohort, dev, loss_obs,
#'       loss_proj, exposure_obs, exposure_proj, is_observed,
#'       incr_loss_proj, exposure_incr_proj]`.}
#'     \item{`proj`}{Same shape as `full`, with observed-cell projection
#'       columns NA'd out.}
#'     \item{`summary`}{Cohort-level reserve summary: `[group, cohort,
#'       latest, loss_ult, reserve, elr, q]`.}
#'     \item{`prior`}{Resolved `data.table(group..., cohort, elr)`.}
#'     \item{`q`}{`data.table(group..., cohort, q)` of expected
#'       emerged fractions.}
#'     \item{`cl_fit`}{The inner `CLFit` used to derive \eqn{q_i}.}
#'     \item{`exposure_fit`}{The inner `ExposureFit` used to derive
#'       \eqn{E_i^{ult}}.}
#'   }
#'
#' @references
#' Bornhuetter, R. L. and Ferguson, R. E. (1972). The actuary and IBNR.
#' *Proceedings of the Casualty Actuarial Society*, 59, 181-195.
#'
#' Mack, T. (2008). The prediction error of Bornhuetter/Ferguson.
#' *ASTIN Bulletin*, 38(1), 87-103. (MSEP -- not yet implemented.)
#'
#' @seealso [fit_capecod()] (pooled ELR variant), [fit_cl()],
#'   [fit_exposure()]
#'
#' @examples
#' \dontrun{
#' data(experience)
#' tri <- as_triangle(
#'   experience[coverage == "surgery"],
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "incr_loss",
#'   exposure = "incr_exposure"
#' )
#'
#' # Scalar prior: 0.7 ELR for every cohort
#' bf1 <- fit_bf(tri, prior = 0.7)
#' summary(bf1)
#'
#' # Per-cohort prior table
#' prior_tbl <- data.frame(
#'   cohort = unique(tri$cohort),
#'   elr    = c(0.6, 0.65, 0.7, 0.72, 0.75)
#' )
#' bf2 <- fit_bf(tri, prior = prior_tbl)
#' }
#'
#' @export
fit_bf <- function(x,
                   loss     = "loss",
                   exposure = "exposure",
                   prior,
                   ...) {

  # data.table NSE bindings
  cohort <- elr <- loss_obs <- loss_proj <- exposure_proj <- NULL
  is_observed <- q <- NULL

  .assert_triangle_input(x, "fit_bf()")
  if (missing(prior))
    stop("`prior` is required: pass a scalar numeric or a ",
         "`data.frame(cohort, elr)`.", call. = FALSE)

  grp <- attr(x, "groups")
  if (is.null(grp)) grp <- character(0)

  # 1) CL on loss for q_i -------------------------------------------------
  cl_fit <- fit_cl(x, loss = loss)

  # 2) CL on exposure for ultimate exposure -------------------------------
  exposure_fit <- fit_exposure(x, method = "cl", bootstrap = FALSE)

  # 3) per-cohort q_i + ultimate exposure ---------------------------------
  by_cols <- c(grp, "cohort")

  loss_grid <- cl_fit$full
  exp_grid  <- exposure_fit$full

  # latest observed cum loss + projected ultimate (last dev per cohort)
  loss_latest <- loss_grid[is_observed == TRUE,
                           .SD[.N, .(loss_latest = loss_obs)],
                           by = by_cols]
  loss_ult <- loss_grid[, .SD[.N, .(loss_ult_cl = loss_proj)],
                        by = by_cols]
  q_dt <- loss_latest[loss_ult, on = by_cols]
  q_dt[, q := data.table::fifelse(
    is.finite(loss_ult_cl) & loss_ult_cl > 0,
    loss_latest / loss_ult_cl,
    NA_real_
  )]

  exp_ult <- exp_grid[, .SD[.N, .(exposure_ult = exposure_proj)],
                      by = by_cols]
  q_dt <- exp_ult[q_dt, on = by_cols]

  # 4) resolve prior to a per-cohort table --------------------------------
  prior_dt <- .resolve_bf_prior(prior, q_dt, by_cols)

  # 5) BF formula ---------------------------------------------------------
  agg <- prior_dt[q_dt, on = by_cols]
  agg[, loss_ult_bf := loss_latest +
        (1 - q) * elr * exposure_ult]
  agg[, reserve := loss_ult_bf - loss_latest]

  # 6) cell-level full grid (project BF ultimate proportionally to CL
  #    pattern between current dev and J). Base = CL$full + exposure
  #    columns from ExposureFit$full so the BFFit cell layout carries
  #    both loss and exposure projections.
  full <- .copy_dt(loss_grid)
  exp_cols <- intersect(
    c("exposure_obs", "exposure_proj", "incr_exposure_proj"),
    names(exp_grid)
  )
  full <- exp_grid[, c(by_cols, "dev", exp_cols), with = FALSE
                   ][full, on = c(by_cols, "dev")]

  full <- agg[, c(by_cols, "loss_ult_bf", "q", "elr",
                  "exposure_ult", "loss_latest"),
              with = FALSE][full, on = by_cols]

  # BF cell-level pattern: at the latest observed dev, loss = loss_obs.
  # For unobserved cells, distribute (loss_ult_bf - loss_latest) along
  # the CL emergence pattern, i.e., scale CL's projected unemerged
  # increments by the BF/CL reserve ratio. When CL projects zero
  # remainder, BF cell = latest (no incremental movement).
  full[, ("loss_proj_bf") := {
    cl_remainder <- loss_proj - loss_latest
    bf_remainder <- loss_ult_bf - loss_latest
    scale <- data.table::fifelse(
      is.finite(cl_remainder) & abs(cl_remainder) > .Machine$double.eps,
      bf_remainder / cl_remainder, 0
    )
    data.table::fifelse(
      is_observed == TRUE,
      loss_obs,
      loss_latest + cl_remainder * scale
    )
  }, by = by_cols]

  data.table::setnames(full, "loss_proj",    "loss_proj_cl")
  data.table::setnames(full, "loss_proj_bf", "loss_proj")

  full[, ("incr_loss_proj") := loss_proj -
         data.table::shift(loss_proj, 1L, fill = 0),
       by = by_cols]
  full[, ("exposure_incr_proj") := exposure_proj -
         data.table::shift(exposure_proj, 1L, fill = 0),
       by = by_cols]

  # drop intermediate workspace columns
  full[, c("loss_ult_bf", "q", "elr", "exposure_ult",
           "loss_latest", "loss_proj_cl") := NULL]

  # 7) proj: NA out observed cells ----------------------------------------
  proj <- data.table::copy(full)
  proj_cols <- c("loss_proj", "incr_loss_proj",
                 "exposure_proj", "exposure_incr_proj")
  proj_cols <- intersect(proj_cols, names(proj))
  proj[is_observed == TRUE, (proj_cols) := NA_real_]

  # 8) cohort-level summary -----------------------------------------------
  summary_dt <- agg[, c(by_cols, "loss_latest", "loss_ult_bf",
                         "reserve", "elr", "q"),
                    with = FALSE]
  data.table::setnames(summary_dt,
                       c("loss_latest", "loss_ult_bf"),
                       c("latest",      "loss_ult"))

  # 9) assemble output ----------------------------------------------------
  out <- list(
    call         = match.call(),
    data         = x,
    method       = "bf",
    groups       = grp,
    cohort       = attr(x, "cohort"),
    dev          = attr(x, "dev"),
    loss         = loss,
    exposure     = exposure,
    full         = full,
    proj         = proj,
    summary      = summary_dt,
    prior        = prior_dt,
    q            = q_dt[, c(by_cols, "q"), with = FALSE],
    cl_fit       = cl_fit,
    exposure_fit = exposure_fit
  )
  class(out) <- "BFFit"
  out
}


#' Resolve `prior` input for `fit_bf()`
#'
#' @description
#' Coerce a `prior` argument (scalar numeric or `data.frame(cohort,
#' elr)`) into a per-cohort `data.table`. Validates ELR coverage of
#' every cohort present in the input triangle.
#'
#' @param prior The user-supplied prior. See [fit_bf()].
#' @param q_dt The per-cohort `data.table` (carrying `cohort` etc.).
#' @param by_cols Character vector of join columns (`c(grp, "cohort")`).
#'
#' @return A `data.table` with columns `by_cols + "elr"`.
#'
#' @keywords internal
.resolve_bf_prior <- function(prior, q_dt, by_cols) {

  cohorts <- unique(q_dt[, .SD, .SDcols = by_cols])

  if (is.numeric(prior) && length(prior) == 1L) {
    if (!is.finite(prior) || prior <= 0)
      stop("`prior` (scalar) must be a positive finite numeric.",
           call. = FALSE)
    out <- data.table::copy(cohorts)
    out[, ("elr") := prior]
    return(out)
  }

  if (is.data.frame(prior)) {
    p <- data.table::as.data.table(prior)
    needed <- c("cohort", "elr")
    if (!all(needed %in% names(p)))
      stop("`prior` data.frame must have columns `cohort` and `elr`.",
           call. = FALSE)
    join_cols <- intersect(by_cols, names(p))
    if (!("cohort" %in% join_cols))
      stop("`prior` must contain a `cohort` column matching the triangle.",
           call. = FALSE)
    out <- p[cohorts, on = join_cols, nomatch = NA]
    if (any(!is.finite(out$elr)))
      stop("`prior` is missing ELR for one or more cohorts in `x`.",
           call. = FALSE)
    return(out[, c(by_cols, "elr"), with = FALSE])
  }

  stop("`prior` must be a scalar numeric or a `data.frame(cohort, elr)`.",
       call. = FALSE)
}


#' Print method for `BFFit`
#'
#' @param x An object of class `"BFFit"`.
#' @param ... Unused.
#'
#' @method print BFFit
#' @export
print.BFFit <- function(x, ...) {

  cat("<BFFit>\n")
  cat("method        :", x$method,            "\n")
  cat("loss          :", x$loss,              "\n")
  cat("exposure      :", x$exposure,          "\n")
  cat("groups        :",
      if (length(x$groups) == 0L) "(none)"
      else paste(x$groups, collapse = ", "),  "\n")
  cat("cohorts (n)   :", nrow(x$summary),     "\n")
  prior_summary <- if (length(unique(x$prior$elr)) == 1L)
    sprintf("scalar elr = %g", x$prior$elr[1L])
  else
    sprintf("per-cohort (range %g .. %g)",
            min(x$prior$elr, na.rm = TRUE),
            max(x$prior$elr, na.rm = TRUE))
  cat("prior         :", prior_summary,       "\n")
  invisible(x)
}


#' Summary method for `BFFit`
#'
#' @description
#' Returns the cohort-level reserve summary `[group..., cohort, latest,
#' loss_ult, reserve, elr, q]`. Mirrors `summary.CLFit()` for slot
#' symmetry; the `prior`/`q` columns are BF-specific.
#'
#' @param object A `BFFit` object.
#' @param ... Unused.
#'
#' @method summary BFFit
#' @export
summary.BFFit <- function(object, ...) {
  object$summary
}

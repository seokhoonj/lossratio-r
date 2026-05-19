#' Cape Cod projection (Stanard 1985)
#'
#' @description
#' Fit a Cape Cod projection from a `"Triangle"` object. Cape Cod is
#' the *prior-free* Bornhuetter-Ferguson variant introduced by Stanard
#' (1985): the a priori expected loss ratio is *estimated from the
#' data itself* as a portfolio-pooled quantity, then plugged into the
#' BF formula.
#'
#' \deqn{\widehat{\mathrm{ELR}}^{CC} =
#'   \frac{\sum_i L_{obs, i}}{\sum_i E_i^{ult} \cdot q_i}}
#'
#' where
#' \itemize{
#'   \item \eqn{L_{obs, i}}: cohort \eqn{i}'s observed cumulative loss
#'     at its latest observed development period.
#'   \item \eqn{q_i = L_{obs, i} / \hat L_{ult, i}^{CL}}: the expected
#'     emerged fraction (inverse of cumulative LDF).
#'   \item \eqn{E_i^{ult}}: cohort \eqn{i}'s ultimate exposure
#'     (projected via chain ladder on exposure).
#' }
#'
#' Given \eqn{\widehat{\mathrm{ELR}}^{CC}}, the per-cohort ultimate is
#' obtained from the BF formula with this single pooled ELR:
#'
#' \deqn{\hat L_{ult, i}^{CC} = L_{obs, i} +
#'   (1 - q_i) \cdot \widehat{\mathrm{ELR}}^{CC} \cdot E_i^{ult}}
#'
#' When multiple groups are present, \eqn{\widehat{\mathrm{ELR}}^{CC}}
#' is computed *within group* (not pooled across groups) so each
#' group retains its own portfolio-level ELR estimate.
#'
#' This is a peer worker alongside [fit_bf()] / [fit_cl()] / [fit_ed()].
#' Standalone for the Cape Cod recipe -- composition with [fit_ratio()]
#' is not part of this worker. Point projection is always computed;
#' bootstrap SE / CI is opt-in via `bootstrap = TRUE` (Phase 3b). The
#' bootstrap path also produces per-replicate pooled ELR draws
#' (`elr_cc_se`, `elr_cc_cv`, `elr_cc_ci_lo`, `elr_cc_ci_hi`) since the
#' Cape Cod ELR itself is data-driven and thus uncertain.
#'
#' @param x A `Triangle` object.
#' @param loss A single cumulative loss variable. Default `"loss"`.
#' @param exposure A single cumulative exposure variable. Default
#'   `"exposure"`.
#' @param bootstrap Bootstrap configuration. Same forms as
#'   [fit_bf()]'s `bootstrap` arg -- see there for the full description.
#' @param B Integer number of bootstrap replicates. Used only when
#'   `bootstrap` resolves to `"auto"`. Default `999`.
#' @param seed Optional integer seed for reproducible bootstrap. Default
#'   `NULL`.
#' @param type One of `"parametric"` (default), `"nonparametric"`, or
#'   `"analytical"`. The latter is reserved for Phase 3c.
#' @param residual Residual scope for `type = "nonparametric"`. One of
#'   `"cell"` (default) or `"link"`.
#' @param process One of `"gamma"` (default), `"od_pois"`, `"normal"`.
#' @param alpha Numeric scalar passed through to the inner [fit_cl()] /
#'   [fit_exposure()] calls. Default `1`.
#' @param sigma_method Sigma extrapolation method forwarded to
#'   [fit_cl()] / [fit_exposure()]. Default `"locf"`.
#' @param recent Optional positive integer; calendar-diagonal filter
#'   forwarded to the inner fits. Default `NULL`.
#' @param regime Optional regime specification forwarded to the inner
#'   loss and exposure fits. See [fit_cl()] for the four-type dispatch.
#' @param conf_level Confidence level for bootstrap quantile CI. Default
#'   `0.95`.
#' @param ... Reserved for future extension (currently unused).
#'
#' @return An object of class `"CCFit"` containing:
#'   \describe{
#'     \item{`call`}{The matched call.}
#'     \item{`data`}{The input `Triangle`.}
#'     \item{`method`}{`"cc"`.}
#'     \item{`groups`, `cohort`, `dev`, `loss`, `exposure`}{Metadata.}
#'     \item{`full`, `proj`, `summary`}{Same shape as `BFFit`. With
#'       bootstrap enabled, `$full` carries
#'       `loss_total_se`/`loss_total_cv`/`loss_ci_lo`/`loss_ci_hi` on
#'       projected cells, and `$summary` carries the same plus
#'       `elr_cc_se`/`elr_cc_cv`/`elr_cc_ci_lo`/`elr_cc_ci_hi`
#'       (uncertainty on the pooled ELR itself).}
#'     \item{`elr_cc`}{`data.table(group..., elr_cc)` -- the pooled ELR
#'       per group (or scalar if no group).}
#'     \item{`q`}{Per-cohort emerged fraction.}
#'     \item{`cl_fit`, `exposure_fit`}{Inner CL / Exposure fits.}
#'     \item{`bootstrap`}{When `bootstrap` is enabled, a
#'       `CCBootstrap` helper holding both Triangle-level
#'       `BootstrapTriangle` objects, the per-replicate ultimate
#'       replicates, and the per-replicate pooled ELR draws; `NULL`
#'       otherwise.}
#'     \item{`ci_type`}{`"bootstrap"` when `bootstrap` is enabled,
#'       `"analytical"` (placeholder) otherwise.}
#'     \item{`alpha`, `sigma_method`, `recent`, `regime`}{Inputs
#'       forwarded to the inner [fit_cl()] / [fit_exposure()] calls.}
#'   }
#'
#' @references
#' Stanard, J. N. (1985). A simulation test of prediction errors of
#' loss reserve estimation techniques. *Proceedings of the Casualty
#' Actuarial Society*, 72, 124-148.
#'
#' Bornhuetter, R. L. and Ferguson, R. E. (1972). The actuary and IBNR.
#' *Proceedings of the Casualty Actuarial Society*, 59, 181-195.
#'
#' @seealso [fit_bf()] (Bornhuetter-Ferguson with user-supplied prior),
#'   [fit_cl()], [fit_exposure()]
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
#' cc <- fit_cc(tri)
#' summary(cc)
#' cc$elr_cc   # pooled ELR per group
#' }
#'
#' @export
fit_cc <- function(x,
                        loss         = "loss",
                        exposure     = "exposure",
                        bootstrap    = NULL,
                        B            = 999L,
                        seed         = NULL,
                        type         = c("parametric", "nonparametric",
                                         "analytical"),
                        residual     = c("cell", "link"),
                        process      = c("gamma", "od_pois", "normal"),
                        alpha        = 1,
                        sigma_method = c("locf", "min_last2", "loglinear",
                                         "mack", "none"),
                        recent       = NULL,
                        regime       = NULL,
                        conf_level   = 0.95,
                        ...) {

  # data.table NSE bindings
  cohort <- elr <- elr_cc <- loss_obs <- loss_proj <- exposure_proj <- NULL
  is_observed <- q <- loss_latest <- exposure_ult <- NULL

  .assert_triangle_input(x, "fit_cc()")

  type         <- match.arg(type)
  residual     <- match.arg(residual)
  process      <- match.arg(process)
  sigma_method <- match.arg(sigma_method)

  if (identical(type, "analytical"))
    stop("type = 'analytical' (closed-form Cape Cod MSEP) is not yet ",
         "implemented (Phase 3c). Use type = 'parametric' or ",
         "type = 'nonparametric'.", call. = FALSE)

  if (!is.numeric(alpha) || length(alpha) != 1L ||
      is.na(alpha) || !is.finite(alpha))
    stop("`alpha` must be a single finite numeric value.", call. = FALSE)
  if (!is.numeric(conf_level) || length(conf_level) != 1L ||
      is.na(conf_level) || conf_level <= 0 || conf_level >= 1)
    stop("`conf_level` must be a single numeric value in (0, 1).",
         call. = FALSE)
  if (!is.numeric(B) || length(B) != 1L || is.na(B) || B < 1L)
    stop("`B` must be a single positive integer.", call. = FALSE)
  B <- as.integer(B)

  grp <- attr(x, "groups")
  if (is.null(grp)) grp <- character(0)
  by_cols <- c(grp, "cohort")

  # 1) CL on loss for q_i + ultimate exposure -----------------------------
  cl_fit <- fit_cl(x, loss = loss,
                   alpha        = alpha,
                   sigma_method = sigma_method,
                   recent       = recent,
                   regime       = regime)
  exposure_fit <- fit_exposure(x, method = "cl", bootstrap = FALSE,
                               alpha        = alpha,
                               sigma_method = sigma_method,
                               recent       = recent,
                               regime       = regime)

  # 2) per-cohort q_i + ultimate exposure ---------------------------------
  loss_latest <- cl_fit$full[is_observed == TRUE,
                              .SD[.N, .(loss_latest = loss_obs)],
                              by = by_cols]
  loss_ult <- cl_fit$full[, .SD[.N, .(loss_ult_cl = loss_proj)],
                          by = by_cols]
  q_dt <- loss_latest[loss_ult, on = by_cols]
  q_dt[, q := data.table::fifelse(
    is.finite(loss_ult_cl) & loss_ult_cl > 0,
    loss_latest / loss_ult_cl,
    NA_real_
  )]

  exp_ult <- exposure_fit$full[, .SD[.N, .(exposure_ult = exposure_proj)],
                                by = by_cols]
  q_dt <- exp_ult[q_dt, on = by_cols]

  # 3) Cape Cod pooled ELR within group -----------------------------------
  by_grp <- if (length(grp) == 0L) NULL else grp
  elr_cc_dt <- q_dt[, .(elr_cc = sum(loss_latest, na.rm = TRUE) /
                          sum(exposure_ult * q, na.rm = TRUE)),
                    by = by_grp]
  if (length(grp) == 0L) {
    # avoid empty-key join failure: append elr_cc column directly
    q_dt[, elr_cc := elr_cc_dt$elr_cc[1L]]
  } else {
    q_dt <- elr_cc_dt[q_dt, on = grp]
  }

  # 4) BF formula with pooled ELR -----------------------------------------
  q_dt[, elr := elr_cc]
  q_dt[, loss_ult_cc := loss_latest +
         (1 - q) * elr_cc * exposure_ult]
  q_dt[, reserve := loss_ult_cc - loss_latest]

  # 5) cell-level full grid (BF cell pattern, see fit_bf). Base = CL$full
  #    plus exposure columns merged from ExposureFit$full.
  full <- .copy_dt(cl_fit$full)
  exp_cols <- intersect(
    c("exposure_obs", "exposure_proj", "incr_exposure_proj"),
    names(exposure_fit$full)
  )
  full <- exposure_fit$full[, c(by_cols, "dev", exp_cols), with = FALSE
                            ][full, on = c(by_cols, "dev")]

  full <- q_dt[, c(by_cols, "loss_ult_cc", "q", "elr_cc",
                   "exposure_ult", "loss_latest"),
               with = FALSE][full, on = by_cols]

  full[, ("loss_proj_cc") := {
    cl_remainder <- loss_proj - loss_latest
    cc_remainder <- loss_ult_cc - loss_latest
    scale <- data.table::fifelse(
      is.finite(cl_remainder) & abs(cl_remainder) > .Machine$double.eps,
      cc_remainder / cl_remainder, 0
    )
    data.table::fifelse(
      is_observed == TRUE,
      loss_obs,
      loss_latest + cl_remainder * scale
    )
  }, by = by_cols]

  data.table::setnames(full, "loss_proj",    "loss_proj_cl")
  data.table::setnames(full, "loss_proj_cc", "loss_proj")

  full[, ("incr_loss_proj") := loss_proj -
         data.table::shift(loss_proj, 1L, fill = 0),
       by = by_cols]
  full[, ("exposure_incr_proj") := exposure_proj -
         data.table::shift(exposure_proj, 1L, fill = 0),
       by = by_cols]

  full[, c("loss_ult_cc", "q", "elr_cc", "exposure_ult",
           "loss_latest", "loss_proj_cl") := NULL]

  # 6) proj: NA out observed cells ----------------------------------------
  proj <- data.table::copy(full)
  proj_cols <- c("loss_proj", "incr_loss_proj",
                 "exposure_proj", "exposure_incr_proj")
  proj_cols <- intersect(proj_cols, names(proj))
  proj[is_observed == TRUE, (proj_cols) := NA_real_]

  # 7) cohort-level summary -----------------------------------------------
  summary_dt <- q_dt[, c(by_cols, "loss_latest", "loss_ult_cc",
                          "reserve", "elr_cc", "q"),
                     with = FALSE]
  data.table::setnames(summary_dt,
                       c("loss_latest", "loss_ult_cc", "elr_cc"),
                       c("latest",      "loss_ult",    "elr"))

  # 8) bootstrap composition (optional) -----------------------------------
  boots <- .resolve_bootstrap_bf(
    bootstrap, x,
    B        = B,
    seed     = seed,
    type     = type,
    residual = residual,
    process  = process
  )

  if (!is.null(boots)) {
    cc_boot <- .bf_compose_bootstrap(
      boots         = boots,
      prior_dt      = NULL,
      grp           = grp,
      by_cols       = by_cols,
      full          = full,
      summary_dt    = summary_dt,
      conf_level    = conf_level,
      cohorts_present = unique(q_dt[, .SD, .SDcols = by_cols]),
      cape_cod      = TRUE
    )
    full       <- cc_boot$full
    summary_dt <- cc_boot$summary
    proj       <- data.table::copy(full)
    proj_cols  <- intersect(
      c("loss_proj", "incr_loss_proj", "exposure_proj",
        "exposure_incr_proj", "loss_total_se", "loss_total_cv",
        "loss_ci_lo", "loss_ci_hi"),
      names(proj))
    proj[is_observed == TRUE, (proj_cols) := NA_real_]
    bootstrap_obj <- cc_boot$bootstrap

    # Cape Cod also produces uncertainty on the pooled ELR itself.
    elr_b <- bootstrap_obj$elr_cc_replicates
    alpha2 <- (1 - conf_level) / 2
    by_grp <- if (length(grp) == 0L) NULL else grp
    elr_summary <- elr_b[, .(
      elr_cc_se     = stats::sd(elr_cc_b, na.rm = TRUE),
      elr_cc_ci_lo  = stats::quantile(elr_cc_b, alpha2,     type = 1L,
                                      na.rm = TRUE, names = FALSE),
      elr_cc_ci_hi  = stats::quantile(elr_cc_b, 1 - alpha2, type = 1L,
                                      na.rm = TRUE, names = FALSE)
    ), by = by_grp]

    if (length(grp) == 0L) {
      elr_cc_point <- elr_cc_dt$elr_cc[1L]
      summary_dt[, ("elr_cc_se")    := elr_summary$elr_cc_se]
      summary_dt[, ("elr_cc_cv")    := data.table::fifelse(
        is.finite(elr_cc_point) & elr_cc_point > 0,
        elr_summary$elr_cc_se / elr_cc_point, NA_real_)]
      summary_dt[, ("elr_cc_ci_lo") := elr_summary$elr_cc_ci_lo]
      summary_dt[, ("elr_cc_ci_hi") := elr_summary$elr_cc_ci_hi]
    } else {
      elr_join <- merge(elr_summary, elr_cc_dt,
                        by = grp, sort = FALSE)
      elr_join[, ("elr_cc_cv") := data.table::fifelse(
        is.finite(elr_cc) & elr_cc > 0,
        elr_cc_se / elr_cc, NA_real_)]
      summary_dt <- merge(summary_dt,
                          elr_join[, c(grp, "elr_cc_se", "elr_cc_cv",
                                       "elr_cc_ci_lo", "elr_cc_ci_hi"),
                                    with = FALSE],
                          by = grp, sort = FALSE)
    }
    ci_type       <- "bootstrap"
  } else {
    bootstrap_obj <- NULL
    ci_type       <- "analytical"
  }

  # 9) assemble output ----------------------------------------------------
  out <- list(
    call         = match.call(),
    data         = x,
    method       = "cc",
    groups       = grp,
    cohort       = attr(x, "cohort"),
    dev          = attr(x, "dev"),
    loss         = loss,
    exposure     = exposure,
    full         = full,
    proj         = proj,
    summary      = summary_dt,
    elr_cc       = elr_cc_dt,
    q            = q_dt[, c(by_cols, "q"), with = FALSE],
    cl_fit       = cl_fit,
    exposure_fit = exposure_fit,
    bootstrap    = bootstrap_obj,
    ci_type      = ci_type,
    alpha        = alpha,
    sigma_method = sigma_method,
    recent       = recent,
    regime       = cl_fit$regime
  )
  class(out) <- "CCFit"
  out
}


#' Print method for `CCFit`
#'
#' @param x A `CCFit` object.
#' @param ... Unused.
#'
#' @method print CCFit
#' @export
print.CCFit <- function(x, ...) {

  cat("<CCFit>\n")
  cat("method        :", x$method,        "\n")
  cat("loss          :", x$loss,          "\n")
  cat("exposure      :", x$exposure,      "\n")
  cat("alpha         :", x$alpha,         "\n")
  cat("sigma_method  :", x$sigma_method,  "\n")
  cat("recent        :",
      if (!is.null(x$recent)) x$recent else "all", "\n")
  cat("regime        :")
  if (is.null(x$regime)) {
    cat(" none\n")
  } else if (inherits(x$regime, "Regime")) {
    cat("\n"); print(x$regime)
  } else {
    cat(" ", format(x$regime), "\n", sep = "")
  }
  cat("groups        :",
      if (length(x$groups) == 0L) "(none)"
      else paste(x$groups, collapse = ", "), "\n")
  cat("cohorts (n)   :", nrow(x$summary), "\n")
  cat("pooled ELR    :")
  if (length(x$groups) == 0L)
    cat(" ", sprintf("%.4f", x$elr_cc$elr_cc[1L]), "\n", sep = "")
  else {
    cat("\n")
    for (i in seq_len(nrow(x$elr_cc))) {
      grp_label <- paste(
        vapply(x$groups, function(g) as.character(x$elr_cc[[g]][i]),
               character(1L)),
        collapse = " / "
      )
      cat("  ", grp_label, " : ",
          sprintf("%.4f", x$elr_cc$elr_cc[i]), "\n", sep = "")
    }
  }
  if (!is.null(x$ci_type)) {
    cat("ci_type       :", x$ci_type,
        if (!is.null(x$bootstrap))
          sprintf(" (B = %d, seed = %s)", x$bootstrap$B,
                  if (is.null(x$bootstrap$seed)) "NULL"
                  else as.character(x$bootstrap$seed))
        else "",
        "\n")
  }
  invisible(x)
}


#' Summary method for `CCFit`
#'
#' @param object A `CCFit` object.
#' @param ... Unused.
#'
#' @method summary CCFit
#' @export
summary.CCFit <- function(object, ...) {
  object$summary
}

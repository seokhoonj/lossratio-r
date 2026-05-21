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
#'   \item \eqn{E_i^{ult}}: cohort \eqn{i}'s ultimate premium
#'     (projected via chain ladder on premium).
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
#' @param exposure A single cumulative premium variable. Default
#'   `"premium"`.
#' @param bootstrap Bootstrap configuration. Same forms as
#'   [fit_bf()]'s `bootstrap` arg -- see there for the full description.
#' @param B Integer number of bootstrap replicates. Used only when
#'   `bootstrap` resolves to `"auto"`. Default `999`.
#' @param seed Optional integer seed for reproducible bootstrap. Default
#'   `NULL`.
#' @param type One of `"parametric"` (default), `"nonparametric"`, or
#'   `"analytical"`. `"parametric"` / `"nonparametric"` select the
#'   bootstrap residual paradigm; `"analytical"` skips simulation and
#'   uses the closed-form Mack (2008) MSEP decomposition (with
#'   `Var(ELR_cc)` from the delta method on the pooled ELR). When no
#'   bootstrap is requested the analytical path is used regardless of
#'   `type`.
#' @param residual Residual scope for `type = "nonparametric"`. One of
#'   `"cell"` (default) or `"link"`.
#' @param process One of `"gamma"` (default), `"od_pois"`, `"normal"`.
#' @param alpha Numeric scalar passed through to the inner [fit_cl()] /
#'   [fit_premium()] calls. Default `1`.
#' @param sigma_method Sigma extrapolation method forwarded to
#'   [fit_cl()] / [fit_premium()]. Default `"locf"`.
#' @param recent Optional positive integer; calendar-diagonal filter
#'   forwarded to the inner fits. Default `NULL`.
#' @param regime Optional regime specification forwarded to the inner
#'   loss and premium fits. See [fit_cl()] for the four-type dispatch.
#' @param credibility Optional credibility specification. `NULL`
#'   (default) gives the classical CC blend weighted by the emergence
#'   fraction `q`. A list `list(method = "bs", K = NULL)` switches to a
#'   Buehlmann-Straub credibility blend `ult = Z * CL + (1 - Z) * prior`
#'   with the pooled ELR as the prior; `Z = K / (K + s^2)` shrinks a
#'   green / rare-event cohort toward the pooled ELR. See [fit_bf()] for
#'   the full description. A credibility blend uses the analytical SE
#'   path.
#' @param conf_level Confidence level for the SE-based CI (bootstrap
#'   quantile or analytical normal). Default `0.95`.
#' @param ... Reserved for future extension (currently unused).
#'
#' @return An object of class `"CCFit"` containing:
#'   \describe{
#'     \item{`call`}{The matched call.}
#'     \item{`data`}{The input `Triangle`.}
#'     \item{`method`}{`"cc"`.}
#'     \item{`groups`, `cohort`, `dev`, `loss`, `premium`}{Metadata.}
#'     \item{`full`, `proj`, `summary`}{Same shape as `BFFit`. With
#'       bootstrap enabled, `$full` carries
#'       `loss_total_se`/`loss_total_cv`/`loss_ci_lo`/`loss_ci_hi` on
#'       projected cells, and `$summary` carries the same plus
#'       `elr_cc_se`/`elr_cc_cv`/`elr_cc_ci_lo`/`elr_cc_ci_hi`
#'       (uncertainty on the pooled ELR itself).}
#'     \item{`elr_cc`}{`data.table(group..., elr_cc)` -- the pooled ELR
#'       per group (or scalar if no group).}
#'     \item{`q`}{Per-cohort emerged fraction.}
#'     \item{`credibility`}{`NULL` for the classical blend, or a list
#'       `list(method, weights)` with the Buehlmann-Straub `Z` / `K`
#'       per cohort.}
#'     \item{`cl_fit`, `premium_fit`}{Inner CL / Premium fits.}
#'     \item{`bootstrap`}{When `bootstrap` is enabled, a
#'       `CCBootstrap` helper holding both Triangle-level
#'       `BootstrapTriangle` objects, the per-replicate ultimate
#'       replicates, and the per-replicate pooled ELR draws; `NULL`
#'       otherwise.}
#'     \item{`ci_type`}{`"bootstrap"` when a bootstrap was run,
#'       `"analytical"` when the closed-form Mack (2008) MSEP was used.
#'       In the analytical case `$summary` carries `loss_total_se` /
#'       `loss_total_cv` / `loss_ci_lo` / `loss_ci_hi` plus the pooled-ELR
#'       columns `elr_cc_se` / `elr_cc_cv` / `elr_cc_ci_lo` /
#'       `elr_cc_ci_hi`.}
#'     \item{`alpha`, `sigma_method`, `recent`, `regime`}{Inputs
#'       forwarded to the inner [fit_cl()] / [fit_premium()] calls.}
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
#'   [fit_cl()], [fit_premium()]
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
#'   premium = "incr_premium"
#' )
#' cc <- fit_cc(tri)
#' summary(cc)
#' cc$elr_cc   # pooled ELR per group
#' }
#'
#' @export
fit_cc <- function(x,
                   loss         = "loss",
                   exposure     = "premium",
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
                   credibility  = NULL,
                   conf_level   = 0.95,
                   ...) {

  # data.table NSE bindings
  cohort <- elr <- elr_cc <- loss_obs <- loss_proj <- premium_proj <- NULL
  is_observed <- q <- loss_latest <- premium_ult <- NULL
  elr_cc_b <- elr_cc_se <- NULL
  loss_proc_se <- loss_param_se <- loss_total_se <- premium_total_se <- NULL
  loss_ult_cl <- var_q <- var_eult <- var_elr <- elr_cc_var <- NULL
  lr <- s2 <- Z <- loss_ult_cc <- NULL

  .assert_triangle_input(x, "fit_cc()")

  type         <- match.arg(type)
  residual     <- match.arg(residual)
  process      <- match.arg(process)
  sigma_method <- match.arg(sigma_method)
  credibility  <- .resolve_credibility(credibility)

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

  grp <- .resolve_groups(x)
  by_cols <- c(grp, "cohort")

  # 1) CL on loss for q_i + ultimate premium -----------------------------
  cl_fit <- fit_cl(x, loss = loss,
                   alpha        = alpha,
                   sigma_method = sigma_method,
                   recent       = recent,
                   regime       = regime)
  # CL on premium for ultimate premium
  premium_fit <- .build_internal_premium_fit(
    x, alpha = alpha, sigma_method = sigma_method,
    recent = recent, regime = regime, groups = grp)

  # 2) per-cohort q_i + ultimate premium ---------------------------------
  dt <- .compute_q_table(cl_fit$full, premium_fit$full, by_cols)

  # 3) Cape Cod pooled ELR within group -----------------------------------
  by_grp <- .by_grp(grp)
  elr_pool <- dt[, .(elr_cc = sum(loss_latest, na.rm = TRUE) /
                          sum(premium_ult * q, na.rm = TRUE)),
                    by = by_grp]
  if (length(grp) == 0L) {
    # avoid empty-key join failure: append elr_cc column directly
    dt[, elr_cc := elr_pool$elr_cc[1L]]
  } else {
    dt <- elr_pool[dt, on = grp]
  }

  # per-cohort ultimate-cell SEs (analytical MSEP + credibility weight)
  loss_se <- cl_fit$full[, .SD[.N, .(loss_proc_se  = loss_proc_se,
                                     loss_param_se = loss_param_se,
                                     loss_total_se = loss_total_se)],
                         by = by_cols]
  exp_se  <- premium_fit$full[, .SD[.N,
                .(premium_total_se = premium_total_se)],
                by = by_cols]

  # 4) BF formula with pooled ELR -----------------------------------------
  # Classical CC blends with the emergence fraction q; a credibility
  # spec replaces it with the Buehlmann-Straub factor Z (see
  # `.credibility_bs()`).
  dt[, elr := elr_cc]
  if (is.null(credibility)) {
    cred_tbl <- NULL
    dt[, loss_ult_cc := loss_latest + (1 - q) * elr_cc * premium_ult]
  } else {
    cred_in <- merge(dt, loss_se, by = by_cols, sort = FALSE)
    cred_in[, ("lr") := data.table::fifelse(
        is.finite(premium_ult) & premium_ult > 0,
        loss_ult_cl / premium_ult, NA_real_)]
    cred_in[, ("s2") := data.table::fifelse(
        is.finite(premium_ult) & premium_ult > 0,
        loss_total_se^2 / premium_ult^2, NA_real_)]
    cred_tbl <- .credibility_bs(cred_in, groups = grp, K = credibility$K)
    dt <- merge(dt, cred_tbl[, c(by_cols, "Z", "K"), with = FALSE],
                by = by_cols, sort = FALSE)
    dt[, loss_ult_cc := Z * loss_ult_cl +
          (1 - Z) * elr_cc * premium_ult]
  }
  dt[, reserve := loss_ult_cc - loss_latest]

  # 5) cell-level full grid (BF cell pattern, see fit_bf). Base = CL$full
  #    plus premium columns merged from PremiumFit$full.
  full <- .copy_dt(cl_fit$full)
  exp_cols <- intersect(
    c("premium_obs", "premium_proj", "incr_premium_proj"),
    names(premium_fit$full)
  )
  full <- premium_fit$full[, c(by_cols, "dev", exp_cols), with = FALSE
                            ][full, on = c(by_cols, "dev")]

  full <- dt[, c(by_cols, "loss_ult_cc", "q", "elr_cc",
                   "premium_ult", "loss_latest"),
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
  full[, ("incr_premium_proj") := premium_proj -
         data.table::shift(premium_proj, 1L, fill = 0),
       by = by_cols]

  full[, c("loss_ult_cc", "q", "elr_cc", "premium_ult",
           "loss_latest", "loss_proj_cl") := NULL]

  # 6) proj: NA out observed cells ----------------------------------------
  proj <- data.table::copy(full)
  proj_cols <- c("loss_proj", "incr_loss_proj",
                 "premium_proj", "incr_premium_proj")
  proj_cols <- intersect(proj_cols, names(proj))
  proj[is_observed == TRUE, (proj_cols) := NA_real_]

  # 7) cohort-level summary -----------------------------------------------
  summ <- dt[, c(by_cols, "loss_latest", "loss_ult_cc",
                          "reserve", "elr_cc", "q"),
                     with = FALSE]
  data.table::setnames(summ,
                       c("loss_latest", "loss_ult_cc", "elr_cc"),
                       c("latest",      "loss_ult",    "elr"))

  # 8) prediction error: bootstrap composition or analytical MSEP --------
  # `type = "analytical"` forces the closed-form Mack (2008) path; a
  # credibility blend also routes through the analytical path.
  boots <- if (identical(type, "analytical") || !is.null(credibility))
    NULL
  else
    .resolve_bootstrap_bf(
      bootstrap, x,
      B        = B,
      seed     = seed,
      type     = type,
      residual = residual,
      process  = process
    )

  if (!is.null(boots)) {
    cc_boot <- .bf_compose_bootstrap(
      boots           = boots,
      priors          = NULL,
      groups          = grp,
      by_cols         = by_cols,
      full            = full,
      summ            = summ,
      conf_level      = conf_level,
      cohorts_present = unique(dt[, .SD, .SDcols = by_cols]),
      cape_cod        = TRUE
    )
    full       <- cc_boot$full
    summ <- cc_boot$summary
    proj       <- data.table::copy(full)
    proj_cols  <- intersect(
      c("loss_proj", "incr_loss_proj", "premium_proj",
        "incr_premium_proj", "loss_total_se", "loss_total_cv",
        "loss_ci_lo", "loss_ci_hi"),
      names(proj))
    proj[is_observed == TRUE, (proj_cols) := NA_real_]
    bootstrap_obj <- cc_boot$bootstrap

    # Cape Cod also produces uncertainty on the pooled ELR itself.
    elr_b <- bootstrap_obj$elr_cc_replicates
    alpha2 <- (1 - conf_level) / 2
    by_grp <- .by_grp(grp)
    elr_summary <- elr_b[, .(
      elr_cc_se     = stats::sd(elr_cc_b, na.rm = TRUE),
      elr_cc_ci_lo  = stats::quantile(elr_cc_b, alpha2,     type = 1L,
                                      na.rm = TRUE, names = FALSE),
      elr_cc_ci_hi  = stats::quantile(elr_cc_b, 1 - alpha2, type = 1L,
                                      na.rm = TRUE, names = FALSE)
    ), by = by_grp]

    if (length(grp) == 0L) {
      elr_cc_point <- elr_pool$elr_cc[1L]
      summ[, ("elr_cc_se")    := elr_summary$elr_cc_se]
      summ[, ("elr_cc_cv")    := data.table::fifelse(
        is.finite(elr_cc_point) & elr_cc_point > 0,
        elr_summary$elr_cc_se / elr_cc_point, NA_real_)]
      summ[, ("elr_cc_ci_lo") := elr_summary$elr_cc_ci_lo]
      summ[, ("elr_cc_ci_hi") := elr_summary$elr_cc_ci_hi]
    } else {
      elr_join <- merge(elr_summary, elr_pool,
                        by = grp, sort = FALSE)
      elr_join[, ("elr_cc_cv") := data.table::fifelse(
        is.finite(elr_cc) & elr_cc > 0,
        elr_cc_se / elr_cc, NA_real_)]
      summ <- merge(summ,
                          elr_join[, c(grp, "elr_cc_se", "elr_cc_cv",
                                       "elr_cc_ci_lo", "elr_cc_ci_hi"),
                                    with = FALSE],
                          by = grp, sort = FALSE)
    }
    ci_type       <- "bootstrap"
  } else {
    # analytical MSEP (Mack 2008 decomposition) -- Cape Cod variant.
    # The pooled ELR is data-estimated, so Var(ELR_cc) is derived by
    # the delta method on elr_cc = sum(loss_latest) / sum(E_ult * q).
    ana <- merge(dt, loss_se, by = by_cols, sort = FALSE)
    ana <- merge(ana, exp_se, by = by_cols, sort = FALSE)
    ana[, var_eult := data.table::fifelse(is.finite(premium_total_se),
                                          premium_total_se^2, 0)]
    ana[, var_q := data.table::fifelse(
          is.finite(loss_ult_cl) & loss_ult_cl > 0,
          (q^2 / loss_ult_cl^2) * loss_param_se^2, 0)]

    # Var(elr_cc) per group: elr_cc = N / D with N = sum(loss_latest)
    # (observed, fixed) and D = sum(E_ult * q); delta method on 1 / D.
    elr_var <- ana[, {
        N  <- sum(loss_latest,      na.rm = TRUE)
        D  <- sum(premium_ult * q, na.rm = TRUE)
        vD <- sum(q^2 * var_eult + premium_ult^2 * var_q +
                  var_eult * var_q, na.rm = TRUE)
        .(elr_cc_var = if (is.finite(D) && D > 0)
                         N^2 / D^4 * vD else 0)
      }, by = by_grp]

    if (length(grp) == 0L) {
      ana[, var_elr := elr_var$elr_cc_var[1L]]
    } else {
      ana <- elr_var[ana, on = grp]
      data.table::setnames(ana, "elr_cc_var", "var_elr")
    }
    # under a credibility blend the effective weight is Z, not q.
    if (!is.null(credibility)) ana[, ("q") := Z]
    data.table::setnames(ana, "loss_ult_cc", "loss_ult")
    se_tbl <- .bf_analytical_se(ana, by_cols, conf_level)
    summ   <- merge(summ, se_tbl, by = by_cols, sort = FALSE)

    # ELR uncertainty columns (mirror the bootstrap path).
    z <- stats::qnorm(1 - (1 - conf_level) / 2)
    if (length(grp) == 0L) {
      elr_cc_pt <- elr_pool$elr_cc[1L]
      elr_cc_sd <- sqrt(max(elr_var$elr_cc_var[1L], 0))
      summ[, c("elr_cc_se", "elr_cc_cv",
               "elr_cc_ci_lo", "elr_cc_ci_hi") := list(
        elr_cc_sd,
        if (is.finite(elr_cc_pt) && elr_cc_pt > 0)
          elr_cc_sd / elr_cc_pt else NA_real_,
        elr_cc_pt - z * elr_cc_sd,
        elr_cc_pt + z * elr_cc_sd)]
    } else {
      elr_se_tbl <- merge(elr_pool, elr_var, by = grp, sort = FALSE)
      elr_se_tbl[, ("elr_cc_se") := sqrt(pmax(elr_cc_var, 0))]
      elr_se_tbl[, ("elr_cc_cv") := data.table::fifelse(
          is.finite(elr_cc) & elr_cc > 0, elr_cc_se / elr_cc, NA_real_)]
      elr_se_tbl[, ("elr_cc_ci_lo") := elr_cc - z * elr_cc_se]
      elr_se_tbl[, ("elr_cc_ci_hi") := elr_cc + z * elr_cc_se]
      summ <- merge(summ,
                    elr_se_tbl[, c(grp, "elr_cc_se", "elr_cc_cv",
                                   "elr_cc_ci_lo", "elr_cc_ci_hi"),
                               with = FALSE],
                    by = grp, sort = FALSE)
    }
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
    premium      = exposure,
    full         = full,
    proj         = proj,
    summary      = summ,
    elr_cc       = elr_pool,
    q            = dt[, c(by_cols, "q"), with = FALSE],
    credibility  = if (is.null(credibility)) NULL else
      list(method = "bs",
           weights = cred_tbl[, c(by_cols, "Z", "K"), with = FALSE]),
    cl_fit       = cl_fit,
    premium_fit  = premium_fit,
    bootstrap    = bootstrap_obj,
    ci_type      = ci_type,
    alpha        = alpha,
    sigma_method = sigma_method,
    recent       = recent,
    regime       = cl_fit$regime
  )
  class(out) <- c("CCFit", "list")
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
  cat("premium       :", x$premium,      "\n")
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

#' Bornhuetter-Ferguson projection
#'
#' @description
#' Fit a Bornhuetter-Ferguson (1972) projection from a `"Triangle"`
#' object. The BF estimator blends the *observed* cumulative loss for
#' each cohort with an *a priori* expected loss ratio (ELR) applied to
#' the cohort's ultimate premium, weighted by the expected unemerged
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
#'   \item \eqn{E_i^{ult}}: cohort \eqn{i}'s ultimate premium, projected
#'     via chain ladder on the `premium` column.
#' }
#'
#' This is a peer worker alongside [fit_cl()] / [fit_ed()] / [fit_loss()].
#' Standalone for the BF recipe -- composition with [fit_ratio()] is not
#' part of this worker. Point projection is always computed; bootstrap
#' SE / CI is opt-in via `bootstrap = TRUE` (Phase 3b). Closed-form
#' Mack (2008) MSEP is not yet implemented.
#'
#' @param x A `Triangle` object.
#' @param loss A single cumulative loss variable to project. Default
#'   `"loss"`.
#' @param premium A single cumulative premium variable used as the
#'   denominator of the prior ELR. Default `"premium"`.
#' @param prior The a priori expected loss ratio. Accepts:
#'   \describe{
#'     \item{single numeric}{Applied uniformly to every cohort.}
#'     \item{per-cohort `data.frame` (`cohort` + `elr`)}{Per-cohort
#'       ELR. Must cover every cohort present in `x` (extras are
#'       silently dropped, missing cohorts raise an error).}
#'     \item{per-group `data.frame` (grouping columns + `elr`)}{One ELR
#'       per group, broadcast to every cohort in that group. Useful when
#'       a single a priori ELR is set per line of business. Must cover
#'       every group present in `x`.}
#'   }
#'   A `data.frame` prior may also carry an optional `elr_se` column --
#'   the standard error of the a priori ELR (a *distribution prior*).
#'   When supplied, the bootstrap path draws a per-replicate ELR from
#'   `Normal(elr, elr_se)` instead of treating the prior as a fixed
#'   point. Omit it (or leave `NA`) for a deterministic prior.
#' @param bootstrap Bootstrap configuration. Five forms accepted:
#'   \describe{
#'     \item{`NULL` / `FALSE` (default)}{Point estimate only -- no
#'       bootstrap SE/CI.}
#'     \item{`TRUE` / `"auto"`}{Internal `bootstrap()` calls (one for
#'       loss, one for premium) sharing `seed` so replicate indices
#'       align across the two simulations.}
#'     \item{Named list `list(loss = BootstrapTriangle, premium =
#'       BootstrapTriangle)`}{Pre-built objects from `bootstrap()`. Must
#'       have matching `meta$B` / `meta$seed` so per-replicate
#'       composition is well-defined; `meta$target` must be `"loss"`
#'       and `"premium"` respectively.}
#'     \item{Function `function(tri) -> list(loss = ..., premium =
#'       ...)`}{Lazy spec invoked on the input Triangle (leakage-safe
#'       for `backtest()`).}
#'   }
#'   Latest observed cumulative loss is *not* perturbed in the BF
#'   recipe -- it is treated as the cohort anchor, mirroring the
#'   point-estimate formula.
#' @param B Integer number of bootstrap replicates. Used only when
#'   `bootstrap` resolves to `"auto"`. Default `999`.
#' @param seed Optional integer seed for reproducible bootstrap. Default
#'   `NULL`.
#' @param type One of `"parametric"` (default), `"nonparametric"`, or
#'   `"analytical"`. `"parametric"` / `"nonparametric"` select the
#'   bootstrap residual paradigm; `"analytical"` skips simulation and
#'   uses the closed-form Mack (2008) BF MSEP decomposition for the
#'   cohort-level SE / CI. When no bootstrap is requested the analytical
#'   path is used regardless of `type`.
#' @param residual Residual scope for `type = "nonparametric"`. One of
#'   `"cell"` (default) or `"link"`. See [bootstrap()].
#' @param process One of `"gamma"` (default), `"od_pois"`, or `"normal"`.
#'   See [bootstrap()].
#' @param alpha Numeric scalar passed through to the inner [fit_cl()] and
#'   [fit_premium()] calls. Default `1`.
#' @param sigma_method Sigma extrapolation method forwarded to
#'   [fit_cl()] / [fit_premium()]. Default `"locf"`.
#' @param recent Optional positive integer; calendar-diagonal filter
#'   forwarded to the inner fits. Default `NULL`.
#' @param regime Optional regime specification forwarded to the inner
#'   loss and premium fits. See [fit_cl()] for the four-type dispatch.
#' @param maturity Optional maturity specification forwarded to the inner
#'   loss fit. See [fit_cl()] for the four-type dispatch.
#' @param credibility Optional credibility specification. `NULL`
#'   (default) gives the classical BF blend with weight equal to the
#'   emergence fraction `q`. A list `list(method = "bs", K = NULL)`
#'   switches to a Buehlmann-Straub credibility blend
#'   `ult = Z * CL + (1 - Z) * prior`, where `Z = K / (K + s^2)`,
#'   `s^2` is the variance of the cohort's own CL loss-ratio estimate,
#'   and `K` is the variance of the hypothetical means (the genuine
#'   between-cohort spread). `K` is estimated per group when `NULL`, or
#'   supplied as a non-negative numeric scalar. The credibility weight
#'   protects rare-event cohorts: a green cohort with a CL estimate
#'   built on almost no data has a large `s^2`, so `Z` shrinks toward 0
#'   and the cohort is pulled to the prior even when its `q` is high.
#'   A credibility blend always uses the analytical SE path (the SE is
#'   approximate -- the credibility factor is treated as a fixed
#'   plug-in).
#' @param conf_level Confidence level for the bootstrap quantile CI on
#'   `loss_ult`. Default `0.95`.
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
#'     \item{`loss`, `premium`}{Loss / premium variable names.}
#'     \item{`full`}{`data.table` `[group, cohort, dev, loss_obs,
#'       loss_proj, premium_obs, premium_proj, is_observed,
#'       incr_loss_proj, incr_premium_proj]`. When `bootstrap` is
#'       enabled, additional columns `loss_total_se`, `loss_total_cv`,
#'       `loss_ci_lo`, `loss_ci_hi` carry per-cell bootstrap SE / CI on
#'       projected cells (observed cells stay `NA`).}
#'     \item{`proj`}{Same shape as `full`, with observed-cell projection
#'       columns NA'd out.}
#'     \item{`summary`}{Cohort-level reserve summary: `[group, cohort,
#'       latest, loss_ult, reserve, elr, q]`. When `bootstrap` is
#'       enabled, additional columns `loss_total_se`, `loss_total_cv`,
#'       `loss_ci_lo`, `loss_ci_hi` carry bootstrap SE / CI on
#'       `loss_ult`.}
#'     \item{`prior`}{Resolved `data.table(group..., cohort, elr)`.}
#'     \item{`q`}{`data.table(group..., cohort, q)` of expected
#'       emerged fractions.}
#'     \item{`credibility`}{`NULL` for the classical blend, or a list
#'       `list(method, weights)` where `weights` is a `data.table`
#'       `[group..., cohort, Z, K]` of the Buehlmann-Straub credibility
#'       factors used in place of `q`.}
#'     \item{`cl_fit`}{The inner `CLFit` used to derive \eqn{q_i}.}
#'     \item{`premium_fit`}{The inner `PremiumFit` used to derive
#'       \eqn{E_i^{ult}}.}
#'     \item{`bootstrap`}{When `bootstrap` is enabled, a
#'       `BFBootstrap` helper holding both Triangle-level
#'       `BootstrapTriangle` objects and the per-replicate ultimate
#'       replicates; `NULL` otherwise.}
#'     \item{`ci_type`}{`"bootstrap"` when a bootstrap was run,
#'       `"analytical"` when the closed-form Mack (2008) MSEP was used.
#'       In the analytical case `$summary` carries `loss_total_se`,
#'       `loss_total_cv`, `loss_ci_lo`, and `loss_ci_hi`.}
#'     \item{`alpha`, `sigma_method`, `recent`, `regime`, `maturity`}{
#'       Inputs forwarded to the inner [fit_cl()] / [fit_premium()]
#'       calls.}
#'   }
#'
#' @references
#' Bornhuetter, R. L. and Ferguson, R. E. (1972). The actuary and IBNR.
#' *Proceedings of the Casualty Actuarial Society*, 59, 181-195.
#'
#' Mack, T. (2008). The prediction error of Bornhuetter/Ferguson.
#' *ASTIN Bulletin*, 38(1), 87-103. (MSEP -- not yet implemented.)
#'
#' @seealso [fit_cc()] (pooled ELR variant), [fit_cl()],
#'   [fit_premium()]
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
                   loss         = "loss",
                   premium      = "premium",
                   prior,
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
                   maturity     = NULL,
                   credibility  = NULL,
                   conf_level   = 0.95,
                   ...) {

  # data.table NSE bindings
  cohort <- elr <- loss_obs <- loss_proj <- premium_proj <- NULL
  is_observed <- q <- NULL
  loss_proc_se <- loss_param_se <- loss_total_se <- NULL
  premium_total_se <- elr_se <- var_elr <- var_eult <- NULL
  loss_ult_cl <- premium_ult <- lr <- s2 <- NULL
  Z <- loss_ult_bf <- NULL

  .assert_triangle_input(x, "fit_bf()")
  if (missing(prior))
    stop("`prior` is required: pass a scalar numeric or a ",
         "`data.frame(cohort, elr)`.", call. = FALSE)

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

  # 1) CL on loss for q_i -------------------------------------------------
  cl_fit <- fit_cl(x, loss = loss,
                   alpha        = alpha,
                   sigma_method = sigma_method,
                   recent       = recent,
                   regime       = regime,
                   maturity     = maturity)

  # 2) CL on premium for ultimate premium -------------------------------
  premium_fit <- .build_internal_premium_fit(
    x, alpha = alpha, sigma_method = sigma_method,
    recent = recent, regime = regime, groups = grp)

  # 3) per-cohort q_i + ultimate premium ---------------------------------
  by_cols <- c(grp, "cohort")

  loss_grid <- cl_fit$full
  exp_grid  <- premium_fit$full

  # latest observed cum loss, CL ultimate, q_i, and ultimate premium
  dt <- .compute_q_table(loss_grid, exp_grid, by_cols)

  # per-cohort ultimate-cell SEs for the analytical MSEP path:
  # CL process / parameter / total SE on loss, total SE on premium.
  loss_se <- loss_grid[, .SD[.N, .(loss_proc_se  = loss_proc_se,
                                   loss_param_se = loss_param_se,
                                   loss_total_se = loss_total_se)],
                       by = by_cols]
  exp_se  <- exp_grid[, .SD[.N, .(premium_total_se = premium_total_se)],
                      by = by_cols]

  # 4) resolve prior to a per-cohort table --------------------------------
  priors <- .resolve_bf_prior(prior, dt, by_cols)

  # 5) BF formula ---------------------------------------------------------
  # Classical BF blends with the emergence fraction q:
  #   ult = q * CL + (1 - q) * prior  =  L_obs + (1 - q) * ELR * E_ult.
  # With a credibility spec the blend weight q is replaced by the
  # Buehlmann-Straub credibility factor Z (see `.credibility_bs()`).
  agg <- priors[dt, on = by_cols]

  if (is.null(credibility)) {
    cred_tbl <- NULL
    agg[, loss_ult_bf := loss_latest + (1 - q) * elr * premium_ult]
  } else {
    # per-cohort credibility weight Z: s2 = Var(CL loss ratio), large
    # for green / rare-event cohorts -> Z -> 0 -> pulled to the prior.
    cred_in <- merge(agg, loss_se, by = by_cols, sort = FALSE)
    cred_in[, ("lr") := data.table::fifelse(
        is.finite(premium_ult) & premium_ult > 0,
        loss_ult_cl / premium_ult, NA_real_)]
    cred_in[, ("s2") := data.table::fifelse(
        is.finite(premium_ult) & premium_ult > 0,
        loss_total_se^2 / premium_ult^2, NA_real_)]
    cred_tbl <- .credibility_bs(cred_in, groups = grp, K = credibility$K)
    agg <- merge(agg, cred_tbl[, c(by_cols, "Z", "K"), with = FALSE],
                 by = by_cols, sort = FALSE)
    # credibility blend: ult = Z * CL + (1 - Z) * prior.
    agg[, loss_ult_bf := Z * loss_ult_cl +
          (1 - Z) * elr * premium_ult]
  }
  agg[, reserve := loss_ult_bf - loss_latest]

  # 6) cell-level full grid (project BF ultimate proportionally to CL
  #    pattern between current dev and J). Base = CL$full + premium
  #    columns from PremiumFit$full so the BFFit cell layout carries
  #    both loss and premium projections.
  full <- .copy_dt(loss_grid)
  exp_cols <- intersect(
    c("premium_obs", "premium_proj", "incr_premium_proj"),
    names(exp_grid)
  )
  full <- exp_grid[, c(by_cols, "dev", exp_cols), with = FALSE
                   ][full, on = c(by_cols, "dev")]

  full <- agg[, c(by_cols, "loss_ult_bf", "q", "elr",
                  "premium_ult", "loss_latest"),
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
  full[, ("incr_premium_proj") := premium_proj -
         data.table::shift(premium_proj, 1L, fill = 0),
       by = by_cols]

  # drop intermediate workspace columns
  full[, c("loss_ult_bf", "q", "elr", "premium_ult",
           "loss_latest", "loss_proj_cl") := NULL]

  # 7) proj: NA out observed cells ----------------------------------------
  proj <- data.table::copy(full)
  proj_cols <- c("loss_proj", "incr_loss_proj",
                 "premium_proj", "incr_premium_proj")
  proj_cols <- intersect(proj_cols, names(proj))
  proj[is_observed == TRUE, (proj_cols) := NA_real_]

  # 8) cohort-level summary -----------------------------------------------
  summ <- agg[, c(by_cols, "loss_latest", "loss_ult_bf",
                         "reserve", "elr", "q"),
                    with = FALSE]
  data.table::setnames(summ,
                       c("loss_latest", "loss_ult_bf"),
                       c("latest",      "loss_ult"))

  # 9) prediction error: bootstrap composition or analytical MSEP --------
  # `type = "analytical"` forces the closed-form path; the bootstrap
  # types route through `.resolve_bootstrap_bf()`. A credibility blend
  # also routes through the analytical path -- the bootstrap composition
  # is defined for the classical (q-weighted) BF only.
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
    bf_boot <- .bf_compose_bootstrap(
      boots           = boots,
      priors          = priors,
      groups          = grp,
      by_cols         = by_cols,
      full            = full,
      summ            = summ,
      conf_level      = conf_level,
      cohorts_present = unique(dt[, .SD, .SDcols = by_cols])
    )
    full        <- bf_boot$full
    summ  <- bf_boot$summary
    proj        <- data.table::copy(full)
    proj_cols   <- intersect(
      c("loss_proj", "incr_loss_proj", "premium_proj",
        "incr_premium_proj", "loss_total_se", "loss_total_cv",
        "loss_ci_lo", "loss_ci_hi"),
      names(proj))
    proj[is_observed == TRUE, (proj_cols) := NA_real_]
    bootstrap_obj <- bf_boot$bootstrap
    ci_type       <- "bootstrap"
  } else {
    # analytical MSEP (Mack 2008 decomposition) -- cohort-level SE / CI.
    ana <- merge(agg, loss_se, by = by_cols, sort = FALSE)
    ana <- merge(ana, exp_se,  by = by_cols, sort = FALSE)
    ana[, var_elr  := data.table::fifelse(is.finite(elr_se),
                                          elr_se^2, 0)]
    ana[, var_eult := data.table::fifelse(is.finite(premium_total_se),
                                          premium_total_se^2, 0)]
    # under a credibility blend the effective weight is Z, not q; the
    # MSEP then uses Z (approximate -- treats the credibility factor as
    # a fixed plug-in).
    if (!is.null(credibility)) ana[, ("q") := Z]
    data.table::setnames(ana, "loss_ult_bf", "loss_ult")
    se_tbl <- .bf_analytical_se(ana, by_cols, conf_level)
    summ   <- merge(summ, se_tbl, by = by_cols, sort = FALSE)
    bootstrap_obj <- NULL
    ci_type       <- "analytical"
  }

  # 10) assemble output ---------------------------------------------------
  out <- list(
    call         = match.call(),
    data         = x,
    method       = "bf",
    groups       = grp,
    cohort       = attr(x, "cohort"),
    dev          = attr(x, "dev"),
    loss         = loss,
    premium      = premium,
    full         = full,
    proj         = proj,
    summary      = summ,
    prior        = priors,
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
    regime       = cl_fit$regime,
    maturity     = cl_fit$maturity
  )
  class(out) <- c("BFFit", "list")
  out
}


#' Compute the per-cohort emergence table (q_i + ultimate premium)
#'
#' @description
#' Shared by [fit_bf()] and [fit_cc()]. From a loss-side `CLFit$full`
#' and an premium-side `PremiumFit$full`, builds the per-cohort table
#' of latest observed loss, CL-ultimate loss, the emergence fraction
#' \eqn{q_i = L_{obs} / L_{ult}^{CL}}, and ultimate premium -- the
#' inputs the Bornhuetter-Ferguson / Cape Cod blend consumes.
#'
#' @param loss_full A loss-side `$full` grid (`is_observed`, `loss_obs`,
#'   `loss_proj`).
#' @param exp_full An premium-side `$full` grid (`premium_proj`).
#' @param by_cols Per-cohort key columns, `c(groups, "cohort")`.
#'
#' @return A `data.table` keyed by `by_cols` with `loss_latest`,
#'   `loss_ult_cl`, `q`, and `premium_ult`.
#'
#' @keywords internal
.compute_q_table <- function(loss_full, exp_full, by_cols) {
  is_observed <- loss_obs <- loss_proj <- NULL
  q <- loss_ult_cl <- premium_proj <- NULL

  loss_latest <- loss_full[is_observed == TRUE,
                           .SD[.N, .(loss_latest = loss_obs)],
                           by = by_cols]
  loss_ult <- loss_full[, .SD[.N, .(loss_ult_cl = loss_proj)],
                        by = by_cols]
  dt <- loss_latest[loss_ult, on = by_cols]
  dt[, q := data.table::fifelse(
    is.finite(loss_ult_cl) & loss_ult_cl > 0,
    loss_latest / loss_ult_cl,
    NA_real_
  )]

  exp_ult <- exp_full[, .SD[.N, .(premium_ult = premium_proj)],
                      by = by_cols]
  exp_ult[dt, on = by_cols]
}


#' Resolve `prior` input for `fit_bf()`
#'
#' @description
#' Coerce a `prior` argument into a per-cohort `data.table`. Three input
#' shapes are accepted:
#'
#' \itemize{
#'   \item scalar numeric -- applied uniformly to every cohort;
#'   \item per-cohort `data.frame` -- carries a `cohort` column plus
#'     `elr` (optionally group-qualified);
#'   \item per-group `data.frame` -- carries all grouping columns plus
#'     `elr` but no `cohort`; the group's ELR is broadcast to every
#'     cohort in that group.
#' }
#'
#' A `data.frame` prior may carry an optional `elr_se` column -- the
#' standard error of the a priori ELR (a *distribution prior*). When
#' present it drives the per-replicate ELR draw in the bootstrap path
#' and the `Var(ELR)` term in the analytical path. When absent the ELR
#' is treated as deterministic (`elr_se` is filled with `NA`).
#'
#' ELR coverage of every cohort present in the input triangle is
#' validated regardless of shape.
#'
#' @param prior The user-supplied prior. See [fit_bf()].
#' @param dt The per-cohort `data.table` (carrying `cohort` etc.).
#' @param by_cols Character vector of join columns (`c(groups, "cohort")`).
#'
#' @return A `data.table` with columns `by_cols + c("elr", "elr_se")`.
#'
#' @keywords internal
.resolve_bf_prior <- function(prior, dt, by_cols) {

  cohorts <- unique(dt[, .SD, .SDcols = by_cols])
  groups  <- setdiff(by_cols, "cohort")
  keep    <- c(by_cols, "elr", "elr_se")

  if (is.numeric(prior) && length(prior) == 1L) {
    if (!is.finite(prior) || prior <= 0)
      stop("`prior` (scalar) must be a positive finite numeric.",
           call. = FALSE)
    out <- data.table::copy(cohorts)
    out[, c("elr", "elr_se") := list(prior, NA_real_)]
    return(out[, keep, with = FALSE])
  }

  if (is.data.frame(prior)) {
    p <- data.table::as.data.table(prior)
    if (!("elr" %in% names(p)))
      stop("`prior` data.frame must carry an `elr` column.", call. = FALSE)
    if (!("elr_se" %in% names(p)))
      p[, ("elr_se") := NA_real_]
    if (any(p$elr_se < 0, na.rm = TRUE))
      stop("`prior` column `elr_se` must be non-negative.", call. = FALSE)

    if ("cohort" %in% names(p)) {
      # per-cohort prior (optionally group-qualified)
      join_cols <- intersect(by_cols, names(p))
    } else if (length(groups) > 0L && all(groups %in% names(p))) {
      # per-group prior: one ELR per group, broadcast to every cohort
      join_cols <- groups
    } else {
      stop("`prior` data.frame must carry either a `cohort` column ",
           "(per-cohort prior) or all grouping columns (per-group ",
           "prior).", call. = FALSE)
    }
    out <- p[cohorts, on = join_cols, nomatch = NA]
    if (any(!is.finite(out$elr)))
      stop("`prior` is missing ELR for one or more cohorts in `x`.",
           call. = FALSE)
    return(out[, keep, with = FALSE])
  }

  stop("`prior` must be a scalar numeric or a `data.frame` carrying ",
       "`elr` plus either `cohort` or the grouping columns.",
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
  cat("premium       :", x$premium,          "\n")
  cat("alpha         :", x$alpha,             "\n")
  cat("sigma_method  :", x$sigma_method,      "\n")
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
      else paste(x$groups, collapse = ", "),  "\n")
  cat("cohorts (n)   :", nrow(x$summary),     "\n")
  prior_summary <- if (length(unique(x$prior$elr)) == 1L)
    sprintf("scalar elr = %g", x$prior$elr[1L])
  else
    sprintf("per-cohort (range %g .. %g)",
            min(x$prior$elr, na.rm = TRUE),
            max(x$prior$elr, na.rm = TRUE))
  cat("prior         :", prior_summary,       "\n")
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


# Section -- Bootstrap composition ============================================
#
# fit_bf and fit_cc consume two BootstrapTriangle objects (loss-side
# + premium-side, sharing a seed so replicate indices align) and compose
# them per-replicate into a BF / Cape Cod ultimate distribution.

#' Resolve `bootstrap` input for `fit_bf()` / `fit_cc()`
#'
#' @description
#' Four-type dispatch mirroring `.resolve_bootstrap()` but returning a
#' *pair* of `BootstrapTriangle` objects (loss + premium) -- BF / Cape
#' Cod compose loss-side parameter uncertainty (via \eqn{q_i^b}) and
#' premium-side parameter uncertainty (via \eqn{E_i^{ult,b}}) into a
#' single ultimate distribution.
#'
#' Accepts:
#' \itemize{
#'   \item `NULL` / `FALSE` -- returns `NULL` (point estimate only).
#'   \item `TRUE` / `"auto"` -- two internal `bootstrap()` calls (one per
#'     target) sharing `seed` so replicate indices align.
#'   \item Named list `list(loss = BT, premium = BT)` -- validate
#'     `meta$B` and `meta$seed` match.
#'   \item Function `function(tri) -> list(loss = ..., premium = ...)`.
#' }
#'
#' @keywords internal
.resolve_bootstrap_bf <- function(arg, tri,
                                  B        = 999L,
                                  seed     = NULL,
                                  type     = "parametric",
                                  residual = "cell",
                                  process  = "gamma") {
  if (is.null(arg)) return(NULL)

  # Back-compat: bare logical
  if (is.logical(arg) && length(arg) == 1L && !is.na(arg)) {
    if (isFALSE(arg)) return(NULL)
    if (isTRUE(arg))  arg <- "auto"
  }

  if (is.list(arg) && !inherits(arg, "BootstrapTriangle") &&
      !is.function(arg) &&
      all(c("loss", "premium") %in% names(arg))) {
    bt_loss <- arg$loss
    bt_exp  <- arg$premium
    if (!inherits(bt_loss, "BootstrapTriangle"))
      stop("`bootstrap$loss` must be a BootstrapTriangle object.",
           call. = FALSE)
    if (!inherits(bt_exp, "BootstrapTriangle"))
      stop("`bootstrap$premium` must be a BootstrapTriangle object.",
           call. = FALSE)
    if (!identical(bt_loss$meta$target, "loss"))
      stop("`bootstrap$loss` has meta$target = '", bt_loss$meta$target,
           "' but `fit_bf()` / `fit_cc()` expects target = 'loss'.",
           call. = FALSE)
    if (!identical(bt_exp$meta$target, "premium"))
      stop("`bootstrap$premium` has meta$target = '",
           bt_exp$meta$target, "' but `fit_bf()` / `fit_cc()` ",
           "expects target = 'premium'.", call. = FALSE)
    if (!identical(bt_loss$meta$B, bt_exp$meta$B))
      stop("`bootstrap$loss$meta$B` (", bt_loss$meta$B,
           ") must equal `bootstrap$premium$meta$B` (",
           bt_exp$meta$B, ").", call. = FALSE)
    return(list(loss = bt_loss, premium = bt_exp))
  }

  if (identical(arg, "auto")) {
    # Force keep_pseudo = TRUE -- the BF composition needs per-replicate
    # cohort-by-dev cum loss / cum premium (Stage 1 means) to compose
    # ultimates one replicate at a time. Same seed for both calls so
    # replicate indices align. Only forward `residual` to the
    # nonparametric path; parametric path errors on its presence.
    common <- list(method      = "cl",
                   process     = process,
                   B           = B,
                   seed        = seed,
                   keep_pseudo = TRUE,
                   quantile_ci = FALSE)
    if (identical(type, "nonparametric"))
      common$residual <- residual
    bt_loss <- do.call(bootstrap, c(list(tri,
                                         type   = type,
                                         target = "loss"), common))
    bt_exp  <- do.call(bootstrap, c(list(tri,
                                         type   = type,
                                         target = "premium"), common))
    return(list(loss = bt_loss, premium = bt_exp))
  }

  if (is.function(arg)) {
    out <- arg(tri)
    if (!is.list(out) || !all(c("loss", "premium") %in% names(out)))
      stop("bootstrap function must return ",
           "`list(loss = BootstrapTriangle, premium = BootstrapTriangle)`.",
           call. = FALSE)
    return(.resolve_bootstrap_bf(out, tri))
  }

  stop("`bootstrap` must be NULL, TRUE/FALSE, \"auto\", a named list ",
       "`list(loss, premium)` of `BootstrapTriangle` objects, or a ",
       "function returning one.", call. = FALSE)
}


#' Resolve the `credibility` argument for `fit_bf()` / `fit_cc()`
#'
#' @description
#' Validate and normalise the `credibility` argument into a spec list
#' or `NULL` (classical BF / CC, weight = emergence fraction `q`).
#'
#' @param credibility `NULL` or a list `list(method = "bs", K = ...)`.
#'
#' @return `NULL` or `list(method = "bs", K = <NULL or numeric>)`.
#'
#' @keywords internal
.resolve_credibility <- function(credibility) {
  if (is.null(credibility)) return(NULL)
  if (!is.list(credibility))
    stop("`credibility` must be NULL or a list, e.g. ",
         "list(method = \"bs\", K = NULL).", call. = FALSE)
  method <- credibility$method
  if (is.null(method) || !identical(method, "bs"))
    stop("`credibility$method` must be \"bs\" (Buhlmann-Straub). ",
         "LFC is not yet available.", call. = FALSE)
  K <- credibility$K
  if (!is.null(K) && (!is.numeric(K) || length(K) != 1L ||
                      is.na(K) || K < 0))
    stop("`credibility$K` must be NULL (auto) or a non-negative ",
         "numeric scalar.", call. = FALSE)
  list(method = "bs", K = K)
}


#' Buehlmann-Straub credibility weight per cohort
#'
#' @description
#' Compute the per-cohort Buehlmann-Straub credibility factor
#'
#' \deqn{Z_i = \frac{K}{K + s_i^2}}
#'
#' that replaces the emergence fraction \eqn{q_i} as the BF / CC blend
#' weight. \eqn{s_i^2} is the variance of cohort \eqn{i}'s own chain
#' ladder loss-ratio estimate, and \eqn{K} is the variance of the
#' hypothetical means (VHM) -- the genuine between-cohort spread of the
#' true loss ratios. This is the standard credibility form
#' \eqn{Z = \tau^2 / (\tau^2 + \sigma^2/w)} written directly in terms of
#' the per-cohort estimate variance.
#'
#' The classical weight `q` only measures *how much has emerged*; a
#' rare-event or very green cohort can have a high `q` yet a chain
#' ladder estimate built on almost no data. There \eqn{s_i^2} is large,
#' so \eqn{Z_i \to 0} and the cohort is pulled toward the prior --
#' exactly the protection the credibility blend is meant to give.
#'
#' @param per_cohort A `data.table` with one row per cohort carrying
#'   `by_cols`, `lr` (cohort CL ultimate loss ratio), and `s2` (the
#'   variance of that loss-ratio estimate).
#' @param groups Group column character vector.
#' @param K `NULL` (estimate the VHM per group) or a non-negative
#'   numeric scalar overriding it.
#'
#' @return `per_cohort` with added columns `K` (the VHM scale used) and
#'   `Z` (the credibility weight).
#'
#' @keywords internal
.credibility_bs <- function(per_cohort, groups, K = NULL) {

  # data.table NSE bindings
  lr <- s2 <- NULL

  d      <- data.table::copy(per_cohort)
  by_grp <- .by_grp(groups)

  # K = VHM, estimated per group from the precision-weighted spread of
  # the cohort loss ratios (reliable cohorts dominate), or supplied.
  k_tbl <- d[, {
      ok <- is.finite(lr) & is.finite(s2) & s2 > 0
      kk <- if (!is.null(K)) {
        K
      } else if (sum(ok) < 2L) {
        0                         # < 2 cohorts: cannot estimate VHM
      } else {
        xx <- lr[ok]; ss <- s2[ok]
        u  <- 1 / ss                          # precision weights
        mu <- sum(u * xx) / sum(u)
        var_w  <- sum(u * (xx - mu)^2) / sum(u)
        s2_bar <- length(u) / sum(u)          # = weighted mean of s2
        max(0, var_w - s2_bar)
      }
      .(K = kk)
    }, by = by_grp]

  if (length(groups) == 0L) {
    d[, ("K") := k_tbl$K[1L]]
  } else {
    d <- k_tbl[d, on = groups]
  }
  d[, ("Z") := data.table::fifelse(
      is.finite(s2) & (K + s2) > 0, K / (K + s2), 0)]
  d
}


#' Analytical BF / Cape Cod prediction error (Mack 2008 decomposition)
#'
#' @description
#' Closed-form mean squared error of prediction for the per-cohort BF /
#' Cape Cod ultimate, following the decomposition of Mack (2008,
#' "The Prediction Error of Bornhuetter/Ferguson", ASTIN Bulletin
#' 38(1), Section 5):
#'
#' \deqn{\mathrm{msep}(R_i) = \mathrm{proc}_i +
#'   (\hat U_i^2 + \mathrm{Var}(\hat U_i))\,\mathrm{Var}(q_i) +
#'   \mathrm{Var}(\hat U_i)\,(1 - q_i)^2}
#'
#' where the three terms are the process error, the development-pattern
#' estimation error, and the prior estimation error. The point estimate
#' is unchanged -- only the variance is added (the "framework borrowed"
#' approach: Mack's three-term structure with the variances sourced
#' from `lossratio`'s own fits).
#'
#' Variance inputs:
#' \itemize{
#'   \item \eqn{\mathrm{Var}(\hat U_i)} -- the prior ultimate
#'     \eqn{\hat U_i = \mathrm{ELR}_i \cdot E^{ult}_i} is a product of
#'     two independent factors, so
#'     \eqn{\mathrm{Var}(\hat U_i) = (E^{ult}_i)^2\,\mathrm{Var}(\mathrm{ELR}_i)
#'     + \mathrm{ELR}_i^2\,\mathrm{Var}(E^{ult}_i)
#'     + \mathrm{Var}(\mathrm{ELR}_i)\,\mathrm{Var}(E^{ult}_i)}.
#'     `Var(ELR)` comes from the distribution prior's `elr_se` (0 for a
#'     deterministic prior); `Var(E_ult)` from the premium fit SE.
#'   \item \eqn{\mathrm{Var}(q_i)} -- delta method on
#'     \eqn{q_i = L^{obs}_i / L^{ult,CL}_i}, using the CL parameter SE.
#'   \item process -- the CL process variance scaled by the BF / CL
#'     reserve ratio (process noise is taken proportional to the
#'     projected future-loss volume).
#' }
#'
#' @param per_cohort A `data.table` with one row per cohort carrying
#'   `by_cols`, `q`, `loss_ult` (BF / CC ultimate), `loss_latest`,
#'   `reserve`, `elr`, `premium_ult`, `var_elr`, `var_eult`,
#'   `loss_ult_cl`, `loss_proc_se`, `loss_param_se`.
#' @param by_cols `c(groups, "cohort")`.
#' @param conf_level Confidence level for the normal CI bounds.
#'
#' @return A `data.table` with columns `by_cols + c("loss_total_se",
#'   "loss_total_cv", "loss_ci_lo", "loss_ci_hi")`.
#'
#' @keywords internal
.bf_analytical_se <- function(per_cohort, by_cols, conf_level) {

  # data.table NSE bindings
  elr <- premium_ult <- var_elr <- var_eult <- q <- NULL
  loss_ult <- loss_ult_cl <- loss_latest <- reserve <- NULL
  loss_proc_se <- loss_param_se <- NULL
  U_hat <- var_U <- var_q <- reserve_cl <- proc_var <- est_var <- NULL
  msep <- loss_total_se <- loss_total_cv <- loss_ci_lo <- loss_ci_hi <- NULL

  d <- data.table::copy(per_cohort)

  # prior ultimate U_hat = ELR * E_ult, and its variance as a product
  # of two independent factors.
  d[, U_hat := elr * premium_ult]
  d[, var_U := premium_ult^2 * var_elr +
               elr^2 * var_eult +
               var_elr * var_eult]

  # Var(q): delta method on q = loss_latest / loss_ult_cl.
  d[, var_q := data.table::fifelse(
      is.finite(loss_ult_cl) & loss_ult_cl > 0,
      (q^2 / loss_ult_cl^2) * loss_param_se^2, 0)]

  # Process error: the CL reserve process variance scaled to the BF /
  # CC reserve volume (process noise proportional to projected
  # future loss, consistent with Mack 2008 assumption BF3).
  d[, reserve_cl := loss_ult_cl - loss_latest]
  d[, proc_var := data.table::fifelse(
      is.finite(reserve_cl) & abs(reserve_cl) > .Machine$double.eps,
      loss_proc_se^2 * (reserve / reserve_cl),
      loss_proc_se^2)]
  d[, proc_var := pmax(proc_var, 0)]

  # Mack (2008) three-term MSEP for the reserve; the BF / CC ultimate
  # adds the observed latest loss (a constant) so its SE equals the
  # reserve SE.
  d[, est_var := (U_hat^2 + var_U) * var_q + var_U * (1 - q)^2]
  d[, msep := proc_var + est_var]
  d[, loss_total_se := sqrt(pmax(msep, 0))]
  d[, loss_total_cv := data.table::fifelse(
      is.finite(loss_ult) & loss_ult > 0,
      loss_total_se / loss_ult, NA_real_)]

  z <- stats::qnorm(1 - (1 - conf_level) / 2)
  d[, loss_ci_lo := loss_ult - z * loss_total_se]
  d[, loss_ci_hi := loss_ult + z * loss_total_se]

  d[, c(by_cols, "loss_total_se", "loss_total_cv",
        "loss_ci_lo", "loss_ci_hi"), with = FALSE]
}


#' Per-replicate BF / Cape Cod composition from two BootstrapTriangle
#'
#' @description
#' Given paired loss-side and premium-side `BootstrapTriangle` objects
#' (with `keep_pseudo = TRUE` so the per-replicate cohort-by-dev cum
#' loss / cum premium means are available), compose the BF / Cape Cod
#' ultimate distribution per replicate:
#'
#' \enumerate{
#'   \item For each replicate \eqn{b}, derive \eqn{q_i^b =
#'     L_{obs,i} / L_{ult,i}^{CL,b}} from the loss-side Stage 1 mean
#'     trajectory (last-dev cell).
#'   \item Derive \eqn{E_i^{ult,b}} from the premium-side Stage 1 mean
#'     last-dev cell.
#'   \item For BF: \eqn{L_{ult,i}^{b} = L_{obs,i} +
#'     (1 - q_i^b) \cdot \mathrm{ELR}_i \cdot E_i^{ult,b}}.
#'   \item For Cape Cod: per group \eqn{\widehat{\mathrm{ELR}}^{CC,b} =
#'     \sum_i L_{obs,i} / \sum_i E_i^{ult,b} \cdot q_i^b}, then plug
#'     into the BF formula.
#'   \item Cell-level projection per replicate: scale the per-replicate
#'     CL emergence pattern to land at \eqn{L_{ult,i}^{b}} at the last
#'     dev.
#' }
#'
#' Cell-level and cohort-level SE / CI are the SD / quantiles across
#' replicates.
#'
#' @param boots A named list `list(loss = BT, premium = BT)` from
#'   `.resolve_bootstrap_bf()`.
#' @param priors Per-cohort ELR table (see `.resolve_bf_prior()`).
#'   Pass `NULL` for the Cape Cod composition (ELR is data-pooled per
#'   replicate).
#' @param groups Group column character vector.
#' @param by_cols `c(groups, "cohort")`.
#' @param full The point-estimate `$full` data.table (used as the base
#'   for join-on bootstrap SE / CI columns).
#' @param summ The point-estimate cohort-level summary.
#' @param conf_level Confidence level for CI bounds.
#' @param cohorts_present Unique `[groups, cohort]` rows present in the
#'   triangle.
#'
#' @return List `list(full, summary, bootstrap)` where `bootstrap` is the
#'   `BFBootstrap` / `CCBootstrap` helper class.
#'
#' @keywords internal
.bf_compose_bootstrap <- function(boots, priors, groups, by_cols,
                                  full, summ, conf_level,
                                  cohorts_present,
                                  cape_cod = FALSE) {

  # data.table NSE bindings
  rep <- loss_mean <- premium_mean <- dev <- cohort <- NULL
  loss_obs <- loss_proj <- premium_proj <- is_observed <- NULL
  elr <- elr_se <- elr_b <- q_b <- premium_ult_b <- loss_ult_b <- NULL
  loss_latest <- elr_cc_b <- L_b <- NULL
  loss_ult_b_med <- loss_ult_b_se <- NULL
  loss_ult_b_lo <- loss_ult_b_hi <- NULL
  loss_ult_cl_b <- loss_proj_b <- NULL

  bt_loss <- boots$loss
  bt_exp  <- boots$premium
  B       <- bt_loss$meta$B
  seed    <- bt_loss$meta$seed
  type    <- bt_loss$meta$type
  residual<- bt_loss$meta$residual
  process <- bt_loss$meta$process

  pl <- bt_loss$pseudo_triangles
  pe <- bt_exp$pseudo_triangles
  if (is.null(pl) || is.null(pe))
    stop("BF bootstrap composition requires `keep_pseudo = TRUE` on ",
         "both BootstrapTriangle objects.", call. = FALSE)

  # Per (groups, cohort, rep) ultimate from the Stage 1 mean trajectory
  # (last dev cell). Stage 1 = parameter uncertainty; the cell-level
  # SD of loss_ult_b across rep captures the BF parameter risk.
  ult_loss <- pl[, .(loss_ult_cl_b = loss_mean[which.max(dev)]),
                 by = c(by_cols, "rep")]
  ult_exp  <- pe[, .(premium_ult_b = premium_mean[which.max(dev)]),
                 by = c(by_cols, "rep")]

  # Per-cohort observed latest loss (anchor).
  latest_loss <- full[is_observed == TRUE,
                       .(loss_latest = loss_obs[which.max(dev)]),
                       by = by_cols]

  ult_b <- merge(ult_loss, ult_exp, by = c(by_cols, "rep"), sort = FALSE)
  ult_b <- merge(ult_b, latest_loss, by = by_cols, sort = FALSE)
  ult_b[, q_b := data.table::fifelse(
    is.finite(loss_ult_cl_b) & loss_ult_cl_b > 0,
    loss_latest / loss_ult_cl_b, NA_real_)]

  if (isTRUE(cape_cod)) {
    by_grp <- .by_grp(groups)
    elr_boot <- ult_b[, .(elr_cc_b = sum(loss_latest, na.rm = TRUE) /
                            sum(premium_ult_b * q_b, na.rm = TRUE)),
                      by = c(by_grp, "rep")]
    if (length(groups) == 0L) {
      ult_b <- merge(ult_b, elr_boot, by = "rep", sort = FALSE)
    } else {
      ult_b <- merge(ult_b, elr_boot, by = c(groups, "rep"), sort = FALSE)
    }
    ult_b[, elr_b := elr_cc_b]
  } else {
    ult_b <- merge(ult_b, priors, by = by_cols, sort = FALSE)
    # Distribution prior: when the prior carries a finite `elr_se`, draw
    # a per-replicate ELR from Normal(elr, elr_se) (floored at 0 -- ELR
    # cannot be negative). A deterministic prior (elr_se NA) keeps the
    # fixed point ELR for every replicate.
    ult_b[, elr_b := elr]
    has_se <- is.finite(ult_b$elr_se) & ult_b$elr_se > 0
    if (any(has_se)) {
      ult_b[has_se, elr_b := pmax(0,
        stats::rnorm(.N, mean = elr, sd = elr_se))]
    }
  }

  ult_b[, loss_ult_b := loss_latest +
          (1 - q_b) * elr_b * premium_ult_b]

  # Cohort-level SE / CI on loss_ult_b across replicates.
  alpha2 <- (1 - conf_level) / 2
  ult_summary <- ult_b[, .(
    loss_total_se = stats::sd(loss_ult_b, na.rm = TRUE),
    loss_ci_lo    = stats::quantile(loss_ult_b, alpha2,     type = 1L,
                                    na.rm = TRUE, names = FALSE),
    loss_ci_hi    = stats::quantile(loss_ult_b, 1 - alpha2, type = 1L,
                                    na.rm = TRUE, names = FALSE)
  ), by = by_cols]
  ult_summary <- merge(ult_summary, summ[, c(by_cols, "loss_ult"),
                                                with = FALSE],
                       by = by_cols, sort = FALSE)
  ult_summary[, ("loss_total_cv") := data.table::fifelse(
    is.finite(loss_ult) & loss_ult > 0,
    loss_total_se / loss_ult, NA_real_)]
  drop_cols <- intersect(c("loss_total_se", "loss_total_cv",
                           "loss_ci_lo", "loss_ci_hi"),
                         names(summ))
  if (length(drop_cols))
    summ[, (drop_cols) := NULL]
  summ <- merge(summ,
                      ult_summary[, c(by_cols, "loss_total_se",
                                      "loss_total_cv",
                                      "loss_ci_lo", "loss_ci_hi"),
                                  with = FALSE],
                      by = by_cols, sort = FALSE)

  # Cell-level projection per replicate. Per (groups, cohort, dev, rep):
  # cl_remainder_b = loss_mean_b - loss_latest
  # ult_remainder_b = loss_ult_b - loss_latest
  # scale_b = ult_remainder_b / cl_remainder_b_last_dev (cohort scalar)
  # loss_proj_b = loss_latest + cl_remainder_b * scale_b (unobserved)
  #             = loss_obs                              (observed)
  cell <- merge(pl, latest_loss, by = by_cols, sort = FALSE)
  cell <- merge(cell, ult_b[, c(by_cols, "rep", "loss_ult_b"),
                            with = FALSE],
                by = c(by_cols, "rep"), sort = FALSE)

  cell[, ("loss_proj_b") := {
    cl_rem <- loss_mean - loss_latest
    cl_rem_last <- cl_rem[which.max(dev)]
    ult_rem <- loss_ult_b[1L] - loss_latest[1L]
    scale_b <- if (is.finite(cl_rem_last) &&
                   abs(cl_rem_last) > .Machine$double.eps)
      ult_rem / cl_rem_last else 0
    loss_latest + cl_rem * scale_b
  }, by = c(by_cols, "rep")]

  # Cell-level SE / CI across replicates.
  cell_summary <- cell[, .(
    loss_total_se = stats::sd(loss_proj_b, na.rm = TRUE),
    loss_ci_lo    = stats::quantile(loss_proj_b, alpha2,     type = 1L,
                                    na.rm = TRUE, names = FALSE),
    loss_ci_hi    = stats::quantile(loss_proj_b, 1 - alpha2, type = 1L,
                                    na.rm = TRUE, names = FALSE)
  ), by = c(by_cols, "dev")]
  cell_summary[, ("loss_total_cv") := NA_real_]

  # Strip any stale cell-level SE/CI before re-join.
  drop_cols <- intersect(c("loss_total_se", "loss_total_cv",
                           "loss_ci_lo", "loss_ci_hi"),
                         names(full))
  if (length(drop_cols))
    full[, (drop_cols) := NULL]

  full <- merge(full, cell_summary, by = c(by_cols, "dev"),
                all.x = TRUE, sort = FALSE)
  full[, ("loss_total_cv") := data.table::fifelse(
    is.finite(loss_proj) & loss_proj > 0,
    loss_total_se / loss_proj, NA_real_)]

  # Assemble per-replicate ultimate replicates (kept on the helper for
  # diagnostics + downstream consumers).
  ult_keep_cols <- c(by_cols, "rep", "q_b", "premium_ult_b",
                     "elr_b", "loss_ult_b")
  ult_replicates <- ult_b[, .SD, .SDcols = ult_keep_cols]
  data.table::setnames(ult_replicates, "rep", "b")

  helper_class <- if (isTRUE(cape_cod)) "CCBootstrap" else "BFBootstrap"
  bootstrap_helper <- structure(
    list(
      loss_bootstrap    = bt_loss,
      premium_bootstrap = bt_exp,
      ult_replicates    = ult_replicates,
      cell_replicates   = NULL,
      B                 = B,
      seed              = seed,
      type              = type,
      residual          = residual,
      process           = process
    ),
    class = c(helper_class, "list")
  )

  if (isTRUE(cape_cod)) {
    elr_cc_boot <- unique(ult_b[, c(groups, "rep", "elr_cc_b"),
                                 with = FALSE])
    data.table::setnames(elr_cc_boot, "rep", "b")
    bootstrap_helper$elr_cc_replicates <- elr_cc_boot
  }

  list(full = full, summary = summ, bootstrap = bootstrap_helper)
}

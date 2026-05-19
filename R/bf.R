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
#' This is a peer worker alongside [fit_cl()] / [fit_ed()] / [fit_loss()].
#' Standalone for the BF recipe -- composition with [fit_ratio()] is not
#' part of this worker. Point projection is always computed; bootstrap
#' SE / CI is opt-in via `bootstrap = TRUE` (Phase 3b). Closed-form
#' Mack (2008) MSEP is not yet implemented.
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
#' @param bootstrap Bootstrap configuration. Five forms accepted:
#'   \describe{
#'     \item{`NULL` / `FALSE` (default)}{Point estimate only -- no
#'       bootstrap SE/CI.}
#'     \item{`TRUE` / `"auto"`}{Internal `bootstrap()` calls (one for
#'       loss, one for exposure) sharing `seed` so replicate indices
#'       align across the two simulations.}
#'     \item{Named list `list(loss = BootstrapTriangle, exposure =
#'       BootstrapTriangle)`}{Pre-built objects from `bootstrap()`. Must
#'       have matching `meta$B` / `meta$seed` so per-replicate
#'       composition is well-defined; `meta$target` must be `"loss"`
#'       and `"exposure"` respectively.}
#'     \item{Function `function(tri) -> list(loss = ..., exposure =
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
#'   `"analytical"`. The latter is reserved for Phase 3c (Mack 2008
#'   closed-form MSEP) and currently errors.
#' @param residual Residual scope for `type = "nonparametric"`. One of
#'   `"cell"` (default) or `"link"`. See [bootstrap()].
#' @param process One of `"gamma"` (default), `"od_pois"`, or `"normal"`.
#'   See [bootstrap()].
#' @param alpha Numeric scalar passed through to the inner [fit_cl()] and
#'   [fit_exposure()] calls. Default `1`.
#' @param sigma_method Sigma extrapolation method forwarded to
#'   [fit_cl()] / [fit_exposure()]. Default `"locf"`.
#' @param recent Optional positive integer; calendar-diagonal filter
#'   forwarded to the inner fits. Default `NULL`.
#' @param regime Optional regime specification forwarded to the inner
#'   loss and exposure fits. See [fit_cl()] for the four-type dispatch.
#' @param maturity Optional maturity specification forwarded to the inner
#'   loss fit. See [fit_cl()] for the four-type dispatch.
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
#'     \item{`loss`, `exposure`}{Loss / exposure variable names.}
#'     \item{`full`}{`data.table` `[group, cohort, dev, loss_obs,
#'       loss_proj, exposure_obs, exposure_proj, is_observed,
#'       incr_loss_proj, incr_exposure_proj]`. When `bootstrap` is
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
#'     \item{`cl_fit`}{The inner `CLFit` used to derive \eqn{q_i}.}
#'     \item{`exposure_fit`}{The inner `ExposureFit` used to derive
#'       \eqn{E_i^{ult}}.}
#'     \item{`bootstrap`}{When `bootstrap` is enabled, a
#'       `BFBootstrap` helper holding both Triangle-level
#'       `BootstrapTriangle` objects and the per-replicate ultimate
#'       replicates; `NULL` otherwise.}
#'     \item{`ci_type`}{`"bootstrap"` when `bootstrap` is enabled,
#'       `"analytical"` (placeholder) otherwise.}
#'     \item{`alpha`, `sigma_method`, `recent`, `regime`, `maturity`}{
#'       Inputs forwarded to the inner [fit_cl()] / [fit_exposure()]
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
                   loss         = "loss",
                   exposure     = "exposure",
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
                   conf_level   = 0.95,
                   ...) {

  # data.table NSE bindings
  cohort <- elr <- loss_obs <- loss_proj <- exposure_proj <- NULL
  is_observed <- q <- NULL

  .assert_triangle_input(x, "fit_bf()")
  if (missing(prior))
    stop("`prior` is required: pass a scalar numeric or a ",
         "`data.frame(cohort, elr)`.", call. = FALSE)

  type         <- match.arg(type)
  residual     <- match.arg(residual)
  process      <- match.arg(process)
  sigma_method <- match.arg(sigma_method)

  if (identical(type, "analytical"))
    stop("type = 'analytical' (Mack 2008 closed-form BF MSEP) is not ",
         "yet implemented (Phase 3c). Use type = 'parametric' or ",
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

  # 1) CL on loss for q_i -------------------------------------------------
  cl_fit <- fit_cl(x, loss = loss,
                   alpha        = alpha,
                   sigma_method = sigma_method,
                   recent       = recent,
                   regime       = regime,
                   maturity     = maturity)

  # 2) CL on exposure for ultimate exposure -------------------------------
  # Worker-layer dispatch: call fit_cl directly on the exposure column
  # (mirror fit_ed pattern) rather than fit_exposure (a dispatcher) to
  # avoid the upward worker -> dispatcher dependency. Reuse the
  # exposure-side schema helper for the role-specific column rename so
  # downstream code reads `exposure_*` columns as before.
  exposure_fit <- fit_cl(x, method = "mack", loss = "exposure",
                         alpha        = alpha,
                         sigma_method = sigma_method,
                         recent       = recent,
                         regime       = regime)
  exposure_fit$full <- .exposure_rename_full(exposure_fit$full, grp,
                                             conf_level = 0.95)
  class(exposure_fit) <- c("ExposureFit", class(exposure_fit))

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
  full[, ("incr_exposure_proj") := exposure_proj -
         data.table::shift(exposure_proj, 1L, fill = 0),
       by = by_cols]

  # drop intermediate workspace columns
  full[, c("loss_ult_bf", "q", "elr", "exposure_ult",
           "loss_latest", "loss_proj_cl") := NULL]

  # 7) proj: NA out observed cells ----------------------------------------
  proj <- data.table::copy(full)
  proj_cols <- c("loss_proj", "incr_loss_proj",
                 "exposure_proj", "incr_exposure_proj")
  proj_cols <- intersect(proj_cols, names(proj))
  proj[is_observed == TRUE, (proj_cols) := NA_real_]

  # 8) cohort-level summary -----------------------------------------------
  summary_dt <- agg[, c(by_cols, "loss_latest", "loss_ult_bf",
                         "reserve", "elr", "q"),
                    with = FALSE]
  data.table::setnames(summary_dt,
                       c("loss_latest", "loss_ult_bf"),
                       c("latest",      "loss_ult"))

  # 9) bootstrap composition (optional) -----------------------------------
  boots <- .resolve_bootstrap_bf(
    bootstrap, x,
    B        = B,
    seed     = seed,
    type     = type,
    residual = residual,
    process  = process
  )

  if (!is.null(boots)) {
    bf_boot <- .bf_compose_bootstrap(
      boots         = boots,
      prior_dt      = prior_dt,
      grp           = grp,
      by_cols       = by_cols,
      full          = full,
      summary_dt    = summary_dt,
      conf_level    = conf_level,
      cohorts_present = unique(q_dt[, .SD, .SDcols = by_cols])
    )
    full        <- bf_boot$full
    summary_dt  <- bf_boot$summary
    proj        <- data.table::copy(full)
    proj_cols   <- intersect(
      c("loss_proj", "incr_loss_proj", "exposure_proj",
        "incr_exposure_proj", "loss_total_se", "loss_total_cv",
        "loss_ci_lo", "loss_ci_hi"),
      names(proj))
    proj[is_observed == TRUE, (proj_cols) := NA_real_]
    bootstrap_obj <- bf_boot$bootstrap
    ci_type       <- "bootstrap"
  } else {
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
    exposure     = exposure,
    full         = full,
    proj         = proj,
    summary      = summary_dt,
    prior        = prior_dt,
    q            = q_dt[, c(by_cols, "q"), with = FALSE],
    cl_fit       = cl_fit,
    exposure_fit = exposure_fit,
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
# + exposure-side, sharing a seed so replicate indices align) and compose
# them per-replicate into a BF / Cape Cod ultimate distribution.

#' Resolve `bootstrap` input for `fit_bf()` / `fit_cc()`
#'
#' @description
#' Four-type dispatch mirroring `.resolve_bootstrap()` but returning a
#' *pair* of `BootstrapTriangle` objects (loss + exposure) -- BF / Cape
#' Cod compose loss-side parameter uncertainty (via \eqn{q_i^b}) and
#' exposure-side parameter uncertainty (via \eqn{E_i^{ult,b}}) into a
#' single ultimate distribution.
#'
#' Accepts:
#' \itemize{
#'   \item `NULL` / `FALSE` -- returns `NULL` (point estimate only).
#'   \item `TRUE` / `"auto"` -- two internal `bootstrap()` calls (one per
#'     target) sharing `seed` so replicate indices align.
#'   \item Named list `list(loss = BT, exposure = BT)` -- validate
#'     `meta$B` and `meta$seed` match.
#'   \item Function `function(tri) -> list(loss = ..., exposure = ...)`.
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
      all(c("loss", "exposure") %in% names(arg))) {
    bt_loss <- arg$loss
    bt_exp  <- arg$exposure
    if (!inherits(bt_loss, "BootstrapTriangle"))
      stop("`bootstrap$loss` must be a BootstrapTriangle object.",
           call. = FALSE)
    if (!inherits(bt_exp, "BootstrapTriangle"))
      stop("`bootstrap$exposure` must be a BootstrapTriangle object.",
           call. = FALSE)
    if (!identical(bt_loss$meta$target, "loss"))
      stop("`bootstrap$loss` has meta$target = '", bt_loss$meta$target,
           "' but `fit_bf()` / `fit_cc()` expects target = 'loss'.",
           call. = FALSE)
    if (!identical(bt_exp$meta$target, "exposure"))
      stop("`bootstrap$exposure` has meta$target = '",
           bt_exp$meta$target, "' but `fit_bf()` / `fit_cc()` ",
           "expects target = 'exposure'.", call. = FALSE)
    if (!identical(bt_loss$meta$B, bt_exp$meta$B))
      stop("`bootstrap$loss$meta$B` (", bt_loss$meta$B,
           ") must equal `bootstrap$exposure$meta$B` (",
           bt_exp$meta$B, ").", call. = FALSE)
    return(list(loss = bt_loss, exposure = bt_exp))
  }

  if (identical(arg, "auto")) {
    # Force keep_pseudo = TRUE -- the BF composition needs per-replicate
    # cohort-by-dev cum loss / cum exposure (Stage 1 means) to compose
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
                                         target = "exposure"), common))
    return(list(loss = bt_loss, exposure = bt_exp))
  }

  if (is.function(arg)) {
    out <- arg(tri)
    if (!is.list(out) || !all(c("loss", "exposure") %in% names(out)))
      stop("bootstrap function must return ",
           "`list(loss = BootstrapTriangle, exposure = BootstrapTriangle)`.",
           call. = FALSE)
    return(.resolve_bootstrap_bf(out, tri))
  }

  stop("`bootstrap` must be NULL, TRUE/FALSE, \"auto\", a named list ",
       "`list(loss, exposure)` of `BootstrapTriangle` objects, or a ",
       "function returning one.", call. = FALSE)
}


#' Per-replicate BF / Cape Cod composition from two BootstrapTriangle
#'
#' @description
#' Given paired loss-side and exposure-side `BootstrapTriangle` objects
#' (with `keep_pseudo = TRUE` so the per-replicate cohort-by-dev cum
#' loss / cum exposure means are available), compose the BF / Cape Cod
#' ultimate distribution per replicate:
#'
#' \enumerate{
#'   \item For each replicate \eqn{b}, derive \eqn{q_i^b =
#'     L_{obs,i} / L_{ult,i}^{CL,b}} from the loss-side Stage 1 mean
#'     trajectory (last-dev cell).
#'   \item Derive \eqn{E_i^{ult,b}} from the exposure-side Stage 1 mean
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
#' @param boots A named list `list(loss = BT, exposure = BT)` from
#'   `.resolve_bootstrap_bf()`.
#' @param prior_dt Per-cohort ELR table (see `.resolve_bf_prior()`).
#'   Pass `NULL` for the Cape Cod composition (ELR is data-pooled per
#'   replicate).
#' @param grp Group column character vector.
#' @param by_cols `c(grp, "cohort")`.
#' @param full The point-estimate `$full` data.table (used as the base
#'   for join-on bootstrap SE / CI columns).
#' @param summary_dt The point-estimate cohort-level summary.
#' @param conf_level Confidence level for CI bounds.
#' @param cohorts_present Unique `[grp, cohort]` rows present in the
#'   triangle.
#'
#' @return List `list(full, summary, bootstrap)` where `bootstrap` is the
#'   `BFBootstrap` / `CCBootstrap` helper class.
#'
#' @keywords internal
.bf_compose_bootstrap <- function(boots, prior_dt, grp, by_cols,
                                  full, summary_dt, conf_level,
                                  cohorts_present,
                                  cape_cod = FALSE) {

  # data.table NSE bindings
  rep <- loss_mean <- exposure_mean <- dev <- cohort <- NULL
  loss_obs <- loss_proj <- exposure_proj <- is_observed <- NULL
  elr <- elr_b <- q_b <- exposure_ult_b <- loss_ult_b <- NULL
  loss_latest <- elr_cc_b <- L_b <- NULL
  loss_ult_b_med <- loss_ult_b_se <- NULL
  loss_ult_b_lo <- loss_ult_b_hi <- NULL

  bt_loss <- boots$loss
  bt_exp  <- boots$exposure
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

  # Per (grp, cohort, rep) ultimate from the Stage 1 mean trajectory
  # (last dev cell). Stage 1 = parameter uncertainty; the cell-level
  # SD of loss_ult_b across rep captures the BF parameter risk.
  ult_loss <- pl[, .(loss_ult_cl_b = loss_mean[which.max(dev)]),
                 by = c(by_cols, "rep")]
  ult_exp  <- pe[, .(exposure_ult_b = exposure_mean[which.max(dev)]),
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
    by_grp <- if (length(grp) == 0L) NULL else grp
    elr_b_dt <- ult_b[, .(elr_cc_b = sum(loss_latest, na.rm = TRUE) /
                            sum(exposure_ult_b * q_b, na.rm = TRUE)),
                      by = c(by_grp, "rep")]
    if (length(grp) == 0L) {
      ult_b <- merge(ult_b, elr_b_dt, by = "rep", sort = FALSE)
    } else {
      ult_b <- merge(ult_b, elr_b_dt, by = c(grp, "rep"), sort = FALSE)
    }
    ult_b[, elr_b := elr_cc_b]
  } else {
    ult_b <- merge(ult_b, prior_dt, by = by_cols, sort = FALSE)
    ult_b[, elr_b := elr]
  }

  ult_b[, loss_ult_b := loss_latest +
          (1 - q_b) * elr_b * exposure_ult_b]

  # Cohort-level SE / CI on loss_ult_b across replicates.
  alpha2 <- (1 - conf_level) / 2
  ult_summary <- ult_b[, .(
    loss_total_se = stats::sd(loss_ult_b, na.rm = TRUE),
    loss_ci_lo    = stats::quantile(loss_ult_b, alpha2,     type = 1L,
                                    na.rm = TRUE, names = FALSE),
    loss_ci_hi    = stats::quantile(loss_ult_b, 1 - alpha2, type = 1L,
                                    na.rm = TRUE, names = FALSE)
  ), by = by_cols]
  ult_summary <- merge(ult_summary, summary_dt[, c(by_cols, "loss_ult"),
                                                with = FALSE],
                       by = by_cols, sort = FALSE)
  ult_summary[, ("loss_total_cv") := data.table::fifelse(
    is.finite(loss_ult) & loss_ult > 0,
    loss_total_se / loss_ult, NA_real_)]
  drop_cols <- intersect(c("loss_total_se", "loss_total_cv",
                           "loss_ci_lo", "loss_ci_hi"),
                         names(summary_dt))
  if (length(drop_cols))
    summary_dt[, (drop_cols) := NULL]
  summary_dt <- merge(summary_dt,
                      ult_summary[, c(by_cols, "loss_total_se",
                                      "loss_total_cv",
                                      "loss_ci_lo", "loss_ci_hi"),
                                  with = FALSE],
                      by = by_cols, sort = FALSE)

  # Cell-level projection per replicate. Per (grp, cohort, dev, rep):
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
  ult_keep_cols <- c(by_cols, "rep", "q_b", "exposure_ult_b",
                     "elr_b", "loss_ult_b")
  ult_replicates <- ult_b[, .SD, .SDcols = ult_keep_cols]
  data.table::setnames(ult_replicates, "rep", "b")

  helper_class <- if (isTRUE(cape_cod)) "CCBootstrap" else "BFBootstrap"
  bootstrap_helper <- structure(
    list(
      loss_bootstrap     = bt_loss,
      exposure_bootstrap = bt_exp,
      ult_replicates     = ult_replicates,
      cell_replicates    = NULL,
      B                  = B,
      seed               = seed,
      type               = type,
      residual           = residual,
      process            = process
    ),
    class = c(helper_class, "list")
  )

  if (isTRUE(cape_cod)) {
    elr_cc_b_dt <- unique(ult_b[, c(grp, "rep", "elr_cc_b"),
                                 with = FALSE])
    data.table::setnames(elr_cc_b_dt, "rep", "b")
    bootstrap_helper$elr_cc_replicates <- elr_cc_b_dt
  }

  list(full = full, summary = summary_dt, bootstrap = bootstrap_helper)
}

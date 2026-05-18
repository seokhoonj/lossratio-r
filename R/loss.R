#' Fit a loss projection on a Triangle
#'
#' @description
#' Project cumulative loss across the cohort x development grid. Three
#' methods are supported via `method`:
#'
#' \describe{
#'   \item{`"ed"` (default)}{Pure exposure-driven (additive) across all
#'     dev periods. Unconditional safe baseline -- no maturity dependency.}
#'   \item{`"cl"`}{Pure Mack chain ladder (multiplicative). Classical
#'     reference.}
#'   \item{`"sa"`}{Stage-adaptive. ED before the maturity point, CL after
#'     -- composition of ED + CL, requires maturity detection (2-pass).}
#' }
#'
#' This function is the *loss-side* counterpart to [fit_exposure()] in
#' the role-specific dispatcher layer (see `ARCHITECTURE.md`). It owns
#' loss projection only -- exposure projection is delegated to
#' [fit_exposure()] (called internally when `exposure_fit = NULL`), and
#' the loss-ratio composition with delta method is handled by
#' [fit_ratio()].
#'
#' @param x A `"Triangle"` object. The standardized `"loss"` and
#'   `"exposure"` columns are used (`as_triangle()` produces these).
#' @param method One of `"ed"` (default), `"cl"`, or `"sa"`.
#' @param alpha Variance-structure exponent for the loss fit. Default `1`.
#' @param regime Optional regime specification applied to both loss-side
#'   and exposure-side estimation. Accepts four input types:
#'   \describe{
#'     \item{`NULL` (default)}{No regime filter.}
#'     \item{`Regime` object}{Use as-is. Typically built via
#'       [detect_regime()] or [regime_at()].}
#'     \item{`"auto"`}{Detect regime internally via `detect_regime(x)` on
#'       the input triangle.}
#'     \item{Function / closure}{A user-supplied function taking the
#'       triangle and returning a `Regime` object (or `NULL`).}
#'   }
#'   Behavior depends on `method`: SA uses a hybrid 2-pass filter (cohort
#'   cut for the ED phase, calendar-diagonal wedge for the CL phase);
#'   ED/CL use a simple cohort cut. The same resolved `Regime` is applied
#'   to the internal `fit_exposure()` call -- callers needing an
#'   asymmetric loss/exposure split should use [fit_ratio()] instead.
#' @param exposure_fit Optional pre-built `ExposureFit` (from
#'   [fit_exposure()]) supplying the exposure projection. When `NULL`,
#'   `fit_loss()` calls `fit_exposure()` internally using
#'   `exposure_method`, `exposure_alpha`, and the resolved `regime`.
#' @param exposure_method One of `"cl"` (default) or `"ed"`. Used only
#'   when `exposure_fit = NULL`. The default matches the historical
#'   `fit_ratio()` exposure choice.
#' @param exposure_alpha Variance-structure exponent for the exposure fit.
#'   Default `1`.
#' @inheritParams fit_ata
#' @param recent Optional positive integer; calendar-diagonal filter.
#' @param maturity Optional maturity specification. Accepts four input
#'   types:
#'   \describe{
#'     \item{`NULL`}{No maturity filter. SA mode requires a maturity, so
#'       this disables only ED / CL modes.}
#'     \item{`Maturity` object}{Use as-is. Typically built via
#'       [detect_maturity()] or [maturity_at()].}
#'     \item{`"auto"` (default)}{Detect maturity internally via
#'       `detect_maturity(x)` on the input triangle.}
#'     \item{Function / closure}{A user-supplied function taking the
#'       triangle and returning a `Maturity` object (e.g. from
#'       [maturity_spec()]) for deferred custom-config detection.}
#'   }
#' @param conf_level Confidence level for analytical CI on the loss
#'   projection (`loss_ci_lo`, `loss_ci_hi`). Default `0.95`.
#' @param bootstrap Bootstrap configuration. Five forms accepted:
#'   \describe{
#'     \item{`NULL` (default)}{Auto-resolved by `method`: bootstrap for
#'       `"sa"`/`"ed"`, analytical for `"cl"`. Matches the legacy
#'       `bootstrap = NULL` behavior.}
#'     \item{`TRUE` / `FALSE`}{Back-compat with the legacy logical arg.
#'       `TRUE` triggers `"auto"`; `FALSE` disables.}
#'     \item{`"auto"`}{Internal `bootstrap()` call on the loss triangle
#'       with defaults `(type = "parametric", process = "normal",
#'       target = "loss")`.}
#'     \item{`BootstrapTriangle`}{Pre-built object from `bootstrap()`.
#'       Must have `meta$target == "loss"`.}
#'     \item{Function `function(tri) -> BootstrapTriangle`}{Lazy spec
#'       invoked on the input Triangle (leakage-safe for `backtest()`).}
#'   }
#'   Premium stays at its observed values during the bootstrap (the
#'   loss-only convention); exposure-side uncertainty is layered in by
#'   `fit_ratio()` via its own bootstrap.
#' @param B Integer number of bootstrap replicates. Used only when
#'   `bootstrap` resolves to `"auto"`. Default `999`.
#' @param seed Optional integer seed for reproducible bootstrap. Default
#'   `NULL`.
#'
#' @return An object of class `"LossFit"`. List with components:
#'   `full`, `proj`, `maturity`, `loss_ata_fit`, `exposure_ata_fit`,
#'   `exposure_fit`, `ed`, `factor`, `selected`, plus metadata.
#'
#' @section Internal columns:
#' `$full` retains internal parameter columns (`g_sel`, `g_sigma2`,
#' `g_var`, `f_sel`, `f_sigma2`, `f_var`, `last_obs`) so that
#' [fit_ratio()] can run bootstrap CI on top without re-fitting.
#' Standalone callers see them as implementation columns.
#'
#' @seealso [fit_exposure()], [fit_ratio()], [fit_cl()], [fit_ed()].
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
#' lf    <- fit_loss(tri)                    # SA (default)
#' lf_ed <- fit_loss(tri, method = "ed")
#' lf_cl <- fit_loss(tri, method = "cl")
#' }
#'
#' @export
fit_loss <- function(x,
                     method          = c("ed", "cl", "sa"),
                     alpha           = 1,
                     regime          = NULL,
                     exposure_fit    = NULL,
                     exposure_method = c("cl", "ed"),
                     exposure_alpha  = 1,
                     sigma_method    = c("locf", "min_last2", "loglinear",
                                         "mack", "none"),
                     recent          = NULL,
                     maturity        = "auto",
                     conf_level      = 0.95,
                     bootstrap       = NULL,
                     B               = 999,
                     seed            = NULL) {

  # data.table NSE bindings for R CMD check
  loss_param_se <- loss_proc_se <- loss_total_se <- loss_total_cv <- NULL
  loss_ci_lo <- loss_ci_hi <- NULL
  loss_proj_boot <- loss_param_se_boot <- loss_proc_se_boot <- NULL
  loss_total_se_boot <- loss_total_cv_boot <- NULL
  loss_ci_lo_boot <- loss_ci_hi_boot <- NULL

  .assert_triangle_input(x, "fit_loss()")
  method          <- match.arg(method)
  sigma_method    <- match.arg(sigma_method)
  exposure_method <- match.arg(exposure_method)

  if (!is.null(exposure_fit) && !inherits(exposure_fit, "ExposureFit"))
    stop("`exposure_fit` must be an ExposureFit object or NULL.",
         call. = FALSE)

  if (!is.numeric(alpha) || length(alpha) != 1L ||
      is.na(alpha) || !is.finite(alpha))
    stop("`alpha` must be a single finite numeric value.", call. = FALSE)
  if (!is.numeric(exposure_alpha) || length(exposure_alpha) != 1L ||
      is.na(exposure_alpha) || !is.finite(exposure_alpha))
    stop("`exposure_alpha` must be a single finite numeric value.",
         call. = FALSE)

  if (!is.numeric(conf_level) || length(conf_level) != 1L ||
      is.na(conf_level) || conf_level <= 0 || conf_level >= 1)
    stop("`conf_level` must be a single numeric value in (0, 1).",
         call. = FALSE)

  # Legacy back-compat: NULL maps to method-dependent default (SA/ED ->
  # bootstrap, CL -> analytical). All other shapes flow through
  # `.resolve_bootstrap()` later.
  if (is.null(bootstrap)) {
    bootstrap <- if (method %in% c("sa", "ed")) "auto" else FALSE
  }
  if (!is.numeric(B) || length(B) != 1L || is.na(B) || B < 1L)
    stop("`B` must be a single positive integer.", call. = FALSE)
  B <- as.integer(B)

  # Resolve regime input (NULL / Regime / "auto" / function) -> NULL or Regime
  regime <- .resolve_regime(regime, x)

  # Resolve maturity input (NULL / Maturity / "auto" / function) -> NULL or Maturity
  maturity <- .resolve_maturity(maturity, x)

  # 1) Triangle structural attrs ----------------------------------------
  # Apply maturity-group rebucket up-front so all downstream code
  # (filter capture of `grp`, fit_ata, .apply_*_filter, projection joins)
  # sees a consistent partition. fit_ata's own rebucket becomes a no-op
  # via setequal short-circuit in .rebucket_triangle_groups.
  if (!is.null(maturity)) {
    m_groups <- attr(maturity, "groups")
    if (is.null(m_groups)) {
      stat_cols <- c("change", "ata_from", "ata_link", "mean", "median", "wt",
                     "cv", "f", "f_se", "rse", "sigma", "n_cohorts", "n_valid",
                     "n_inf", "n_nan", "valid_ratio")
      m_groups <- setdiff(names(maturity), stat_cols)
    }
    data_groups <- attr(x, "groups")
    if (is.null(data_groups)) data_groups <- character(0)
    if (length(m_groups) > 0L && !setequal(m_groups, data_groups)) {
      x <- .rebucket_triangle_groups(x, m_groups)
    }
  }

  # Triangle is guaranteed to carry standardized `loss` / `exposure`
  # columns (as_triangle convention).
  grp <- attr(x, "groups")
  coh <- attr(x, "cohort")
  dev <- attr(x, "dev")

  if (is.null(grp)) grp <- character(0)

  if (length(coh) != 1L)
    stop("`x` must contain exactly one `cohort`.", call. = FALSE)
  if (length(dev) != 1L)
    stop("`x` must contain exactly one `dev`.", call. = FALSE)

  # preserve pre-filter triangle for downstream `$usage` annotation
  x_full      <- data.table::copy(x)
  # preserve original user input -- nullified below for SA hybrid path
  regime_user <- regime
  recent_user <- recent

  # 2) SA hybrid filter (loss-side, 2-pass maturity) ---------------------
  if (!is.null(regime)) {
    cd <- .resolve_regime_change_date(regime, by = grp)

    if (!is.null(cd) && method == "sa") {
      pre_loss_fit <- fit_ata(
        x,
        loss         = "loss",
        alpha        = alpha,
        sigma_method = sigma_method,
        maturity     = maturity
      )
      m_dt <- pre_loss_fit$maturity

      if (is.null(m_dt) || nrow(m_dt) == 0L) {
        warning(
          "regime: cannot detect maturity; falling back to ",
          "simple cohort cut.", call. = FALSE
        )
        x <- .apply_regime_filter(
          x, regime,
          grp = grp,
          coh = "cohort",
          dev = "dev"
        )
        regime <- NULL
      } else {
        # Per-group `m_k` for SA hybrid: each group uses its own
        # maturity (ED/CL boundary). With multi-group `regime`, this
        # means a group with a fast maturity (small k*) only cuts its
        # narrow ED region, retaining pre-break CL data for factor
        # estimation. (Earlier `max(k*)` fallback over-cut
        # fast-maturing groups.)
        m_k_vec <- m_dt$change

        dev_split_arg <- if (length(grp) > 0L &&
                             length(unique(m_k_vec)) > 1L) {
          m_k_dt <- m_dt[, c(grp, "change"), with = FALSE]
          data.table::setnames(m_k_dt, "change", "dev_split")
          m_k_dt
        } else {
          max(m_k_vec, na.rm = TRUE)
        }

        x <- .apply_regime_filter(
          x, regime,
          grp       = grp,
          coh       = "cohort", dev = "dev",
          dev_split = dev_split_arg
        )
        if (!is.null(recent)) {
          x <- .apply_recent_filter(
            x, recent,
            grp       = grp,
            coh       = "cohort", dev = "dev",
            dev_split = dev_split_arg
          )
          recent <- NULL
        }
        regime <- NULL
      }
    }
    # method = "ed"/"cl": leave regime for fit_ata/fit_intensity
  }

  # 3) resolve exposure_fit --------------------------------------------
  # fit_loss is single-role -- the same regime applies to the internal
  # exposure fit. Asymmetric loss/exposure splits live at fit_ratio().
  if (is.null(exposure_fit)) {
    # bootstrap = FALSE: fit_loss treats exposure as a fixed projection
    # (no exposure-side simulation in fit_loss's loss-only bootstrap).
    exposure_fit <- fit_exposure(
      x,
      method       = exposure_method,
      alpha        = exposure_alpha,
      sigma_method = sigma_method,
      regime       = regime_user,
      bootstrap    = FALSE
    )
  }
  # Wrap as ATAFit-shaped object for downstream .expand_grid / join paths.
  exposure_ata_fit <- structure(
    list(
      selected     = exposure_fit$selected,
      link         = exposure_fit$link,
      data         = exposure_fit$data,
      method       = "mack",
      alpha        = exposure_alpha,
      sigma_method = sigma_method,
      maturity     = NULL
    ),
    class = "ATAFit"
  )

  # 4) loss ATA + Mack f_var ---------------------------------------------
  loss_ata_fit <- fit_ata(
    x,
    loss         = "loss",
    alpha        = alpha,
    sigma_method = sigma_method,
    recent       = recent,
    regime       = regime,
    maturity     = maturity
  )
  loss_ata_fit$selected <- .mack_f_var(
    ata_fit = loss_ata_fit,
    alpha   = alpha
  )

  # 5) ED intensities g_k + Mack g_var -----------------------------------
  intensity_fit <- fit_intensity(
    x,
    loss         = "loss",
    exposure     = "exposure",
    alpha        = alpha,
    sigma_method = sigma_method,
    recent       = recent,
    regime       = regime
  )
  ed_fit <- list(
    method       = "mack",
    link         = intensity_fit$link,
    factor       = intensity_fit$factor,
    selected     = intensity_fit$selected,
    alpha        = alpha,
    sigma_method = sigma_method,
    recent       = recent,
    regime       = regime
  )
  class(ed_fit) <- "EDFit"
  ed_fit$selected <- .ed_g_var(ed_fit, alpha = alpha)

  # 6) maturity point per group ------------------------------------------
  maturity <- loss_ata_fit$maturity

  # 7) expand triangle to full projection grid --------------------------
  full <- .expand_grid(
    triangle         = x,
    ed_fit           = ed_fit,
    exposure_ata_fit = exposure_ata_fit,
    loss             = "loss",
    exposure         = "exposure"
  )

  # Detect whether either side carries segment_id (segment_wise treatment);
  # the join must include it or a cartesian product blows up at runtime.
  has_seg_ed   <- "segment_id" %in% names(ed_fit$selected)
  has_seg_cl   <- "segment_id" %in% names(loss_ata_fit$selected)

  # 8) join ED factors (g_sel, g_sigma2, g_var) --------------------
  ed_cols <- c(grp, "ata_from",
               if (has_seg_ed) "segment_id",
               "g_sel", "sigma2", "g_var")
  ed_sel  <- ed_fit$selected[, .SD, .SDcols = ed_cols]
  data.table::setnames(ed_sel, "ata_from", "dev")
  data.table::setnames(ed_sel, "sigma2", "g_sigma2")
  full <- ed_sel[full,
                 on = c(grp, "dev", if (has_seg_ed) "segment_id")]

  # 9) join CL factors (f_sel, f_sigma2, f_var) --------------------
  cl_cols <- c(grp, "ata_from",
               if (has_seg_cl) "segment_id",
               "f_sel", "sigma2", "f_var")
  cl_sel  <- loss_ata_fit$selected[, .SD, .SDcols = cl_cols]
  data.table::setnames(cl_sel, "ata_from", "dev")
  data.table::setnames(cl_sel, "sigma2", "f_sigma2")
  full <- cl_sel[full,
                 on = c(grp, "dev", if (has_seg_cl) "segment_id")]

  # 10) maturity join per group -----------------------------------------
  if (!is.null(maturity)) {
    m_join <- .copy_dt(maturity)
    m_keep <- c(grp, "ata_from")
    m_join <- m_join[, .SD, .SDcols = intersect(m_keep, names(m_join))]
    data.table::setnames(m_join, "ata_from", "maturity_from")

    if (length(grp)) {
      full <- m_join[full, on = grp]
    } else {
      if (nrow(m_join) == 1L) {
        full[, ("maturity_from") := m_join$maturity_from[1L]]
      } else {
        full[, ("maturity_from") := NA_real_]
      }
    }
  } else {
    full[, ("maturity_from") := NA_real_]
  }

  # 11) last_obs per cohort ---------------------------------------------
  full[, ("last_obs") := {
    idx <- which(is.finite(loss_obs))
    if (length(idx)) max(idx) else 0L
  }, by = c(grp, "cohort")]

  # 12) loss point projection -------------------------------------------
  full[, ("loss_proj") := .sa_proj(
    loss_obs      = loss_obs,
    exposure_proj = exposure_proj,
    g_sel         = g_sel,
    f_sel         = f_sel,
    maturity_from = maturity_from[1L],
    method        = method
  ), by = c(grp, "cohort")]

  # 13) loss variance (process + parameter) ----------------------------
  full[, `:=`(
    loss_proc_se2  = .sa_proc_var(
      loss_proj     = loss_proj,
      exposure_proj = exposure_proj,
      g_sigma2      = g_sigma2,
      f_sigma2      = f_sigma2,
      f_sel         = f_sel,
      last_obs      = last_obs[1L],
      maturity_from = maturity_from[1L],
      alpha         = alpha,
      method        = method
    ),
    loss_param_se2 = .sa_param_var(
      loss_proj     = loss_proj,
      exposure_proj = exposure_proj,
      g_var         = g_var,
      f_var         = f_var,
      f_sel         = f_sel,
      last_obs      = last_obs[1L],
      maturity_from = maturity_from[1L],
      method        = method
    )
  ), by = c(grp, "cohort")]

  # 14) total loss variance and SE -------------------------------------
  full[, ("loss_total_se2") := loss_proc_se2 + loss_param_se2]

  full[, `:=`(
    loss_proc_se  = sqrt(loss_proc_se2),
    loss_param_se = sqrt(loss_param_se2),
    loss_total_se = sqrt(loss_total_se2)
  )]

  full[, ("loss_total_cv") := data.table::fifelse(
    is.finite(loss_proj) & loss_proj != 0,
    loss_total_se / abs(loss_proj), NA_real_
  )]

  # 15) analytical CI on loss only ------------------------------------
  z_alpha <- stats::qnorm((1 + conf_level) / 2)
  full[, `:=`(
    loss_ci_lo = pmax(0, loss_proj - z_alpha * loss_total_se),
    loss_ci_hi = loss_proj + z_alpha * loss_total_se
  )]

  # 15b) bootstrap overwrite of CI + total SE -------------------------
  # Wrap-only path: bootstrap() already produces the cohort x dev
  # `$summary` with the Pythagorean SE decomposition (param_se /
  # proc_se / total_se / total_cv + opt. ci_lo / ci_hi). fit_loss
  # just maps those columns into its own `$full` schema. Premium stays
  # at observed values (loss-only bootstrap -- exposure uncertainty is
  # layered in by fit_ratio).
  boots <- .resolve_bootstrap(
    bootstrap, x_full,
    B           = B,
    seed        = seed,
    type        = "parametric",
    process     = "normal",
    target      = "loss",
    alpha       = alpha,
    quantile_ci = TRUE,
    keep_pseudo = FALSE
  )

  if (!is.null(boots)) {
    bsum <- data.table::copy(boots$summary)
    data.table::setnames(
      bsum,
      c("mean_proj", "param_se", "proc_se", "total_se", "total_cv"),
      c("loss_proj_boot", "loss_param_se_boot", "loss_proc_se_boot",
        "loss_total_se_boot", "loss_total_cv_boot")
    )
    has_ci <- all(c("ci_lo", "ci_hi") %in% names(bsum))
    if (has_ci) {
      data.table::setnames(bsum, c("ci_lo", "ci_hi"),
                                  c("loss_ci_lo_boot", "loss_ci_hi_boot"))
    }

    full <- merge(full, bsum,
                  by = c(grp, "cohort", "dev"),
                  all.x = TRUE, sort = FALSE)

    # Only override SE/CI for non-observed cells. Observed cells keep
    # their analytical SE = 0 (the value is known); under residual
    # bootstrap, the pseudo observed cells would otherwise produce a
    # spurious nonzero SE.
    is_proj <- full$is_observed == FALSE
    full[is_proj & is.finite(loss_param_se_boot), loss_param_se := loss_param_se_boot]
    full[is_proj & is.finite(loss_proc_se_boot),  loss_proc_se  := loss_proc_se_boot]
    full[is_proj & is.finite(loss_total_se_boot), loss_total_se := loss_total_se_boot]
    full[is_proj & is.finite(loss_total_cv_boot), loss_total_cv := loss_total_cv_boot]
    if (has_ci) {
      full[is_proj & is.finite(loss_ci_lo_boot), loss_ci_lo := loss_ci_lo_boot]
      full[is_proj & is.finite(loss_ci_hi_boot), loss_ci_hi := loss_ci_hi_boot]
    }
    drop_boot <- c("loss_proj_boot", "loss_param_se_boot",
                    "loss_proc_se_boot", "loss_total_se_boot",
                    "loss_total_cv_boot")
    if (has_ci) drop_boot <- c(drop_boot, "loss_ci_lo_boot", "loss_ci_hi_boot")
    full[, (drop_boot) := NULL]
  }

  # 16) incremental projections (loss + exposure) ------------------
  full[, ("incr_loss_proj") := loss_proj - data.table::shift(loss_proj, 1L, fill = 0),
       by = c(grp, "cohort")]
  full[, ("incr_exposure_proj") := exposure_proj - data.table::shift(exposure_proj, 1L, fill = 0),
       by = c(grp, "cohort")]

  # 17) $proj: NA-mask observed cells (loss-side columns only) --------
  proj    <- data.table::copy(full)
  na_cols <- c(
    "loss_proj", "exposure_proj",
    "incr_loss_proj", "incr_exposure_proj",
    "loss_proc_se2", "loss_param_se2", "loss_total_se2",
    "loss_proc_se",  "loss_param_se",  "loss_total_se",
    "loss_total_cv",
    "loss_ci_lo", "loss_ci_hi"
  )
  proj[is_observed == TRUE, (na_cols) := NA_real_]

  # 18) usage map (one row per (group, cohort, dev) cell of the
  # *pre-filter* triangle, status = used / unused / holdout / future).
  # Computed once here so `plot_triangle(fit, view = "usage")` can
  # render directly without re-deriving the filter logic.
  usage <- .build_usage(
    x_full,
    regime   = regime_user,
    recent   = recent_user,
    holdout  = NULL,
    maturity = maturity,
    metric   = "loss"
  )

  # 19) assemble LossFit ----------------------------------------------
  # NOTE: $full retains internal columns (g_sel, g_sigma2, g_var,
  # f_sel, f_sigma2, f_var, last_obs) so that fit_ratio can run
  # bootstrap CI without re-fitting. fit_ratio drops them after bootstrap.
  out <- list(
    call             = match.call(),
    data             = x,
    groups           = grp,
    cohort           = coh,
    dev              = dev,
    full             = full,
    proj             = proj,
    maturity         = maturity,
    loss_ata_fit     = loss_ata_fit,
    exposure_ata_fit = exposure_ata_fit,
    exposure_fit     = exposure_fit,
    ed               = ed_fit$link,
    factor           = ed_fit$factor,
    selected         = ed_fit$selected,
    method           = method,
    alpha            = alpha,
    sigma_method     = sigma_method,
    recent           = recent_user,
    regime           = regime_user,
    conf_level       = conf_level,
    ci_type          = if (!is.null(boots)) "bootstrap" else "analytical",
    bootstrap        = if (!is.null(boots))
                         list(B = boots$meta$B, seed = boots$meta$seed)
                       else NULL,
    usage            = usage
  )

  class(out) <- "LossFit"
  out
}


#' Print method for `LossFit`
#' @param x A `LossFit` object.
#' @param ... Unused.
#' @export
print.LossFit <- function(x, ...) {
  grp <- x$groups
  if (is.null(grp)) grp <- character(0)

  # Maturity labels are dynamic (depend on group string lengths), so
  # the colon column is computed from the union of static + dynamic
  # labels rather than a hardcoded width.
  mat_labels <- character(0)
  if (!is.null(x$maturity) && nrow(x$maturity)) {
    if (length(grp)) {
      grp_txt <- vapply(seq_len(nrow(x$maturity)), function(i)
        paste(x$maturity[i, grp, with = FALSE], collapse = "/"),
        character(1L))
      mat_labels <- sprintf("maturity[%s]", grp_txt)
    } else {
      mat_labels <- "maturity"
    }
  }

  static_labels <- c("method", "alpha", "sigma_method", "recent", "regime",
                     "ci_type", "groups", "n_cohorts")
  lw  <- max(nchar(c(static_labels, mat_labels)))
  pad <- function(label) formatC(label, width = lw, flag = "-")

  cat("<LossFit>\n")
  cat(pad("method"),       ":", x$method,       "\n")
  cat(pad("alpha"),        ":", x$alpha,        "\n")
  cat(pad("sigma_method"), ":", x$sigma_method, "\n")
  cat(pad("recent"),       ":",
      if (!is.null(x$recent)) x$recent else "all", "\n")
  cat(pad("regime"),       ":")
  if (is.null(x$regime)) {
    cat(" none\n")
  } else if (inherits(x$regime, "Regime")) {
    cat("\n"); print(x$regime)
  } else {
    cat(" ", format(x$regime), "\n", sep = "")
  }

  if (!is.null(x$ci_type)) {
    cat(pad("ci_type"), ":", x$ci_type,
        if (!is.null(x$bootstrap))
          sprintf(" (B = %d, seed = %s)", x$bootstrap$B,
                  if (is.null(x$bootstrap$seed)) "NULL" else x$bootstrap$seed)
        else "",
        "\n")
  }

  if (length(mat_labels)) {
    mat <- .copy_dt(x$maturity)
    for (i in seq_along(mat_labels)) {
      cat(pad(mat_labels[i]), ":", mat$change[i], "\n")
    }
  }

  if (length(grp)) {
    cat(pad("groups"), ":", paste(grp, collapse = ", "), "\n")
  } else {
    cat(pad("groups"), ": none\n", sep = "")
  }

  cat(pad("n_cohorts"), ":", length(unique(x$full$cohort)), "\n")
  invisible(x)
}


#' Summary method for `LossFit`
#'
#' @description
#' Per-cohort ultimate loss, SE, and CV.
#'
#' @param object A `LossFit` object.
#' @param ... Unused.
#' @export
summary.LossFit <- function(object, ...) {
  grp <- object$groups
  if (is.null(grp)) grp <- character(0)

  full <- .copy_dt(object$full)
  by_cols <- c(grp, "cohort")
  out <- full[, .SD[which.max(dev)], by = by_cols]
  keep <- c(by_cols, "loss_proj", "loss_total_se", "loss_total_cv")
  out <- out[, .SD, .SDcols = keep]
  data.table::setnames(out, "loss_proj", "loss_ult")
  out[]
}


# Projection helpers --------------------------------------------------------

#' Hybrid point projection for a single cohort
#'
#' @description
#' Internal helper that projects cumulative loss:
#'
#' \itemize{
#'   \item \strong{sa (stage-adaptive)}: ED before maturity, CL after.
#'   \item \strong{ed}: ED for all periods.
#'   \item \strong{cl}: CL for all periods.
#' }
#'
#' @param loss_obs Numeric vector of observed cumulative loss.
#' @param exposure_proj Numeric vector of projected cumulative exposure.
#' @param g_sel Numeric vector of ED intensities.
#' @param f_sel Numeric vector of CL factors.
#' @param maturity_from Numeric scalar; switch point. `NA` = no switch.
#' @param method One of `"ed"`, `"cl"`, or `"sa"`.
#'
#' @return A numeric vector with projected cumulative loss.
#'
#' @keywords internal
.sa_proj <- function(loss_obs,
                     exposure_proj,
                     g_sel,
                     f_sel,
                     maturity_from,
                     method = "sa") {

  n        <- length(loss_obs)
  last_obs <- max(which(is.finite(loss_obs)), 0L)

  if (last_obs == 0L || last_obs == n) return(loss_obs)

  v <- loss_obs

  # determine switch point
  mat <- if (method == "sa" && is.finite(maturity_from)) {
    maturity_from
  } else if (method == "cl") {
    0   # always CL
  } else {
    Inf # always ED
  }

  for (i in seq(last_obs + 1L, n)) {
    k <- i - 1L
    v_prev <- v[i - 1L]

    if (!is.finite(v_prev)) next

    if (k < mat) {
      # ED phase: additive, exposure-driven
      g_now <- g_sel[k]
      e_now <- exposure_proj[k]

      if (is.finite(g_now) && is.finite(e_now)) {
        v[i] <- v_prev + g_now * e_now
      }
    } else {
      # CL phase: multiplicative, loss-driven
      f_now <- f_sel[k]

      if (is.finite(f_now)) {
        v[i] <- f_now * v_prev
      }
    }
  }

  v
}


#' Hybrid process variance for a single cohort
#'
#' @description
#' Internal helper for process variance:
#'
#' \itemize{
#'   \item ED phase (additive):
#'     \eqn{\text{proc}_{k+1} = \text{proc}_k
#'       + g_{\sigma^2,k} \cdot (C^P_k)^\alpha}
#'   \item CL phase (multiplicative, Mack):
#'     \eqn{\text{proc}_{k+1} = f_k^2 \cdot \text{proc}_k
#'       + f_{\sigma^2,k} \cdot (C^L_k)^\alpha}
#' }
#'
#' @keywords internal
.sa_proc_var <- function(loss_proj,
                         exposure_proj,
                         g_sigma2,
                         f_sigma2,
                         f_sel,
                         last_obs,
                         maturity_from,
                         alpha  = 1,
                         method = "sa") {

  n    <- length(loss_proj)
  proc <- numeric(n)

  if (last_obs == n) return(proc)

  mat <- if (method == "sa" && is.finite(maturity_from)) {
    maturity_from
  } else if (method == "cl") {
    0
  } else {
    Inf
  }

  for (i in seq(last_obs + 1L, n)) {
    k <- i - 1L

    if (k < mat) {
      # ED phase: additive variance
      s2  <- g_sigma2[k]
      e_k <- exposure_proj[k]

      proc[i] <- proc[i - 1L]
      if (is.finite(s2) && is.finite(e_k) && e_k > 0) {
        proc[i] <- proc[i] + s2 * e_k^alpha
      }
    } else {
      # CL phase: multiplicative variance (Mack)
      f_k <- f_sel[k]
      s2  <- f_sigma2[k]
      v_k <- loss_proj[k]

      if (!is.finite(f_k)) { proc[i] <- proc[i - 1L]; next }

      proc[i] <- f_k^2 * proc[i - 1L]
      if (is.finite(s2) && is.finite(v_k) && v_k > 0) {
        proc[i] <- proc[i] + s2 * v_k^alpha
      }
    }
  }

  proc
}


#' Hybrid parameter variance for a single cohort
#'
#' @description
#' Internal helper for parameter variance:
#'
#' \itemize{
#'   \item ED phase:
#'     \eqn{\text{param}_{k+1} = \text{param}_k
#'       + (C^P_k)^2 \cdot \mathrm{Var}(\hat{g}_k)}
#'   \item CL phase:
#'     \eqn{\text{param}_{k+1} = f_k^2 \cdot \text{param}_k
#'       + (C^L_k)^2 \cdot \mathrm{Var}(\hat{f}_k)}
#' }
#'
#' @keywords internal
.sa_param_var <- function(loss_proj,
                          exposure_proj,
                          g_var,
                          f_var,
                          f_sel,
                          last_obs,
                          maturity_from,
                          method = "sa") {

  n     <- length(loss_proj)
  param <- numeric(n)

  if (last_obs == n) return(param)

  mat <- if (method == "sa" && is.finite(maturity_from)) {
    maturity_from
  } else if (method == "cl") {
    0
  } else {
    Inf
  }

  for (i in seq(last_obs + 1L, n)) {
    k <- i - 1L

    if (k < mat) {
      # ED phase: additive
      gv  <- g_var[k]
      e_k <- exposure_proj[k]

      param[i] <- param[i - 1L]
      if (is.finite(gv) && is.finite(e_k)) {
        param[i] <- param[i] + e_k^2 * gv
      }
    } else {
      # CL phase: multiplicative (Mack)
      f_k  <- f_sel[k]
      fv   <- f_var[k]
      v_k  <- loss_proj[k]

      if (!is.finite(f_k)) { param[i] <- param[i - 1L]; next }

      param[i] <- f_k^2 * param[i - 1L]
      if (is.finite(fv) && is.finite(v_k)) {
        param[i] <- param[i] + v_k^2 * fv
      }
    }
  }

  param
}


#' Expand a `Triangle` object to a full projection grid
#'
#' @keywords internal
.expand_grid <- function(triangle,
                         ed_fit,
                         exposure_ata_fit,
                         loss,
                         exposure) {

  grp <- attr(triangle, "groups")

  if (is.null(grp)) grp <- character(0)

  raw <- .copy_dt(triangle)

  loss_col <- loss    # rebind, was target
  exp_col  <- exposure
  obs <- raw[, .(
    loss_obs     = get(loss_col),
    exposure_obs = get(exp_col)
  ), by = c(grp, "cohort", "dev")]

  max_dev_ed       <- max(ed_fit$selected$ata_to, na.rm = TRUE)
  max_dev_exposure <- max(exposure_ata_fit$selected$ata_to, na.rm = TRUE)
  max_dev          <- max(max_dev_ed, max_dev_exposure)

  full <- unique(obs[, .SD, .SDcols = c(grp, "cohort")])
  full <- full[, .(dev = seq_len(max_dev)), by = c(grp, "cohort")]

  full <- obs[full, on = c(grp, "cohort", "dev")]
  data.table::setorderv(full, c(grp, "cohort", "dev"))

  full[, ("is_observed") := is.finite(loss_obs)]

  # Attach segment_id when either side of the projection was fitted
  # segment_wise. ED loss-side regime is on ed_fit; exposure-side regime
  # is on exposure_ata_fit. If both are segment_wise they share the same
  # Regime in practice (fit_ed passes its regime down to fit_cl), so
  # one assignment is sufficient.
  has_seg_ed       <- "segment_id" %in% names(ed_fit$selected)
  has_seg_exposure <- "segment_id" %in% names(exposure_ata_fit$selected)
  if (has_seg_ed || has_seg_exposure) {
    reg <- if (has_seg_ed) ed_fit$regime else exposure_ata_fit$regime
    grp_dt <- if (length(grp)) full[, grp, with = FALSE] else NULL
    full[, ("segment_id") := .assign_segment(cohort, reg, grp_dt)]
  }

  exposure_cols <- c(grp, "ata_from",
                     if (has_seg_exposure) "segment_id",
                     "f_sel")
  exposure_sel <- exposure_ata_fit$selected[, .SD, .SDcols = exposure_cols]
  data.table::setnames(exposure_sel, c("ata_from", "f_sel"),
                       c("dev", "f_exposure"))
  full <- exposure_sel[full,
                       on = c(grp, "dev", if (has_seg_exposure) "segment_id")]

  full[, ("exposure_proj") := .cl_proj(
    loss_obs = exposure_obs,
    f_sel    = f_exposure
  ), by = c(grp, "cohort")]

  full[, ("f_exposure") := NULL]
  full
}

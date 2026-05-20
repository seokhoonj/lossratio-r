#' Fit a loss projection on a Triangle
#'
#' @description
#' Project cumulative loss across the cohort x development grid. `fit_loss()`
#' is the role-specific *dispatcher* on the loss side -- it forwards to a
#' worker selected by `method`:
#'
#' \describe{
#'   \item{`"ed"` (default)}{[fit_ed()] -- pure exposure-driven
#'     (additive). Unconditional safe baseline; no maturity dependency.}
#'   \item{`"cl"`}{[fit_cl()] -- pure Mack chain ladder (multiplicative).
#'     Classical reference.}
#'   \item{`"sa"`}{[fit_sa()] -- stage-adaptive composition: ED before
#'     the maturity point, CL after.}
#'   \item{`"bf"`}{[fit_bf()] -- Bornhuetter-Ferguson; requires a `prior`
#'     ELR (scalar or per-cohort table) passed via `...`.}
#'   \item{`"cc"`}{[fit_cc()] -- Cape Cod (BF with a pooled ELR derived
#'     from the data).}
#' }
#'
#' The dispatcher returns a `LossFit` object whose `$full` schema is
#' uniform across methods (`loss_obs`, `loss_proj`, `loss_total_se`,
#' `loss_ci_lo`, `loss_ci_hi`, `exposure_obs`, `exposure_proj`,
#' `incr_exposure_proj`, plus method-specific extras). Missing slots on
#' worker outputs (e.g. `loss_ata_fit` for ED, `ed`/`selected` for CL/BF/CC)
#' are synthesized as `NULL` so downstream code such as [fit_ratio()] can
#' guard uniformly.
#'
#' @param x A `"Triangle"` object. The standardized `"loss"` and
#'   `"exposure"` columns are used (`as_triangle()` produces these).
#' @param method One of `"ed"` (default), `"cl"`, `"sa"`, `"bf"`, or `"cc"`.
#' @param alpha Variance-structure exponent for the loss fit. Default `1`.
#' @param regime Optional regime specification (loss-side). Accepts the
#'   standard 4-type dispatch (`NULL` / `Regime` / `"auto"` / function).
#'   Behavior depends on `method`: SA uses a hybrid 2-pass filter; ED / CL
#'   / BF / CC use a simple cohort cut. The same resolved regime is
#'   applied to the internal exposure fit -- callers needing an asymmetric
#'   loss/exposure split should use [fit_ratio()].
#' @param exposure_fit Optional pre-built `ExposureFit` supplying the
#'   exposure projection. Only used by `"ed"` (via `fit_ed`'s internal
#'   exposure handling) and `"sa"`. When `NULL`, the worker calls
#'   [fit_exposure()] internally.
#' @param exposure_method One of `"cl"` (default) or `"ed"`. Used only
#'   when `exposure_fit = NULL` for `"sa"`.
#' @param exposure_alpha Variance-structure exponent for the exposure fit.
#'   Default `1`.
#' @inheritParams fit_ata
#' @param recent Optional positive integer; calendar-diagonal filter.
#' @param maturity Optional maturity specification. Accepts the standard
#'   4-type dispatch (`NULL` / `Maturity` / `"auto"` / function). Only
#'   used by `"cl"`, `"sa"`, and `"bf"`. Default `"auto"`.
#' @param tail Tail factor (logical or numeric). Forwarded to `"cl"` /
#'   `"sa"` workers. Default `FALSE`.
#' @param conf_level Confidence level for analytical CI on the loss
#'   projection (`loss_ci_lo`, `loss_ci_hi`). Default `0.95`.
#' @param bootstrap Bootstrap configuration. Five forms accepted (see
#'   [fit_sa()] / [fit_ed()] / [fit_cl()] for method-specific defaults).
#' @param B Integer number of bootstrap replicates. Default `999`.
#' @param seed Optional integer seed.
#' @param type Bootstrap process type. Forwarded where applicable
#'   (`"sa"`, `"bf"`, `"cc"`).
#' @param ... Method-specific arguments forwarded to the chosen worker.
#'   For `method = "bf"`, `prior` is required.
#'
#' @return An object of class `"LossFit"`. List with components:
#'   `full`, `proj`, `maturity`, `loss_ata_fit`, `exposure_ata_fit`,
#'   `exposure_fit`, `ed`, `factor`, `selected`, plus metadata.
#'
#' @seealso [fit_ed()], [fit_cl()], [fit_sa()], [fit_bf()], [fit_cc()],
#'   [fit_exposure()], [fit_ratio()].
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
#' lf    <- fit_loss(tri)                    # ED (default)
#' lf_cl <- fit_loss(tri, method = "cl")
#' lf_sa <- fit_loss(tri, method = "sa")
#' }
#'
#' @export
fit_loss <- function(x,
                     method          = c("ed", "cl", "sa", "bf", "cc"),
                     alpha           = 1,
                     regime          = NULL,
                     exposure_fit    = NULL,
                     exposure_method = c("cl", "ed"),
                     exposure_alpha  = 1,
                     sigma_method    = c("locf", "min_last2", "loglinear",
                                         "mack", "none"),
                     recent          = NULL,
                     maturity        = "auto",
                     tail            = FALSE,
                     conf_level      = 0.95,
                     bootstrap       = NULL,
                     B               = 999L,
                     seed            = NULL,
                     type,
                     ...) {

  .assert_triangle_input(x, "fit_loss()")
  method          <- match.arg(method)
  sigma_method    <- match.arg(sigma_method)
  exposure_method <- match.arg(exposure_method)

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

  dots <- list(...)
  if (method == "bf" && is.null(dots$prior))
    stop("`prior` is required when method = 'bf'. Pass a scalar ELR ",
         "or a data.frame(cohort, elr).", call. = FALSE)

  # Legacy NULL default: SA / ED bootstrap, CL analytical (BF / CC
  # carry their own bootstrap-NULL handling in the worker).
  if (is.null(bootstrap) && method %in% c("sa", "ed", "cl")) {
    bootstrap <- if (method %in% c("sa", "ed")) "auto" else FALSE
  }

  # Common worker args -- intersection of worker signatures.
  common <- list(
    x            = x,
    loss         = "loss",
    alpha        = alpha,
    sigma_method = sigma_method,
    recent       = recent,
    regime       = regime
  )

  # Dispatch to worker. SA / BF / CC handle bootstrap themselves;
  # CL / ED workers don't, so the dispatcher applies bootstrap via
  # .lossfit_bootstrap() after the analytical fit.
  fit <- switch(method,
    cl = do.call(fit_cl, c(common, list(
                  maturity = if (identical(maturity, "auto"))
                               NULL else maturity,
                  tail     = tail))),
    ed = do.call(fit_ed, c(common, list(
                  exposure = "exposure"))),
    sa = do.call(fit_sa, c(common, list(
                  exposure        = "exposure",
                  maturity        = maturity,
                  exposure_fit    = exposure_fit,
                  exposure_method = exposure_method,
                  exposure_alpha  = exposure_alpha,
                  tail            = tail,
                  conf_level      = conf_level,
                  bootstrap       = bootstrap,
                  B               = B,
                  seed            = seed,
                  type            = if (missing(type)) "parametric" else type))),
    bf = do.call(fit_bf, c(common, list(
                  exposure   = "exposure",
                  maturity   = if (identical(maturity, "auto"))
                                 NULL else maturity,
                  prior      = dots$prior,
                  conf_level = conf_level,
                  bootstrap  = bootstrap,
                  B          = B,
                  seed       = seed,
                  type       = if (missing(type)) "parametric" else type))),
    cc = do.call(fit_cc, c(common, list(
                  exposure   = "exposure",
                  conf_level = conf_level,
                  bootstrap  = bootstrap,
                  B          = B,
                  seed       = seed,
                  type       = if (missing(type)) "parametric" else type)))
  )

  # Augment to LossFit schema --------------------------------------------
  out <- .lossfit_augment(
    fit               = fit,
    triangle          = x,
    method            = method,
    exposure_fit      = exposure_fit,
    exposure_method   = exposure_method,
    exposure_alpha    = exposure_alpha,
    sigma_method      = sigma_method,
    recent            = recent,
    regime            = regime,
    maturity_arg      = maturity,
    conf_level        = conf_level
  )

  # For CL / ED workers, the dispatcher owns bootstrap overwriting (the
  # workers themselves don't run bootstrap). SA / BF / CC handled it
  # natively.
  if (method %in% c("cl", "ed")) {
    out <- .lossfit_bootstrap(
      fit        = out,
      triangle   = x,
      bootstrap  = bootstrap,
      B          = B,
      seed       = seed,
      alpha      = alpha,
      conf_level = conf_level
    )
  }

  out$call <- match.call()
  out
}


#' Augment a worker-fit to the LossFit schema
#'
#' @description
#' Worker fits (`CLFit`, `EDFit`, `SAFit`, `BFFit`, `CCFit`) each have
#' their own slot layouts. This helper adds missing slots (`loss_ata_fit`,
#' `exposure_ata_fit`, `exposure_fit`, `ed`, `factor`, `selected`,
#' `usage`, `ci_type`, `conf_level`, `bootstrap`) as `NULL` if absent,
#' ensures `$full` carries the dispatcher-uniform columns
#' (`exposure_obs`, `exposure_proj`, `incr_exposure_proj`, `loss_ci_lo`,
#' `loss_ci_hi`, `loss_total_cv`), and assigns class `"LossFit"`.
#'
#' For `"cl"`, this synthesizes the exposure columns by running an
#' [fit_exposure()] internally when none are present.
#'
#' @keywords internal
.lossfit_augment <- function(fit,
                             triangle,
                             method,
                             exposure_fit,
                             exposure_method,
                             exposure_alpha,
                             sigma_method,
                             recent,
                             regime,
                             maturity_arg,
                             conf_level) {

  # data.table NSE bindings
  loss_proj <- loss_total_se <- exposure_proj <- is_observed <- NULL

  grp <- .resolve_groups(triangle)

  # Standard slot list (NULL-fill missing) -------------------------------
  std_slots <- c("data", "method", "groups", "cohort", "dev",
                 "full", "proj", "summary",
                 "maturity", "loss_ata_fit", "exposure_ata_fit",
                 "exposure_fit", "ed", "factor", "selected",
                 "alpha", "sigma_method", "recent", "regime",
                 "conf_level", "ci_type", "bootstrap", "usage")
  for (slot in std_slots) {
    if (!slot %in% names(fit)) {
      # Single-bracket + list(NULL) explicitly adds a NULL slot to the
      # list (double-bracket assignment would *remove* an existing slot).
      fit[slot] <- list(NULL)
    }
  }
  # set dispatcher-level method label
  fit$method <- method
  if (is.null(fit$conf_level)) fit$conf_level <- conf_level

  # Resolve maturity for downstream slot consistency. SA / CL / BF workers
  # already set $maturity from their own fit_ata path; for ED / CC the
  # slot is empty -- resolve the user's input directly so the slot mirrors
  # the original monolithic fit_loss behavior.
  if (is.null(fit$maturity) && !is.null(maturity_arg) &&
      !identical(maturity_arg, NULL)) {
    fit$maturity <- .resolve_maturity(maturity_arg, triangle)
  }

  # Ensure $full has exposure columns -----------------------------------
  full <- fit$full
  needs_exposure <- !all(c("exposure_obs", "exposure_proj",
                            "incr_exposure_proj") %in% names(full))
  if (needs_exposure) {
    # Run internal exposure fit and join exposure columns.
    if (is.null(exposure_fit)) {
      exposure_fit <- fit_exposure(
        triangle,
        method       = exposure_method,
        alpha        = exposure_alpha,
        sigma_method = sigma_method,
        regime       = regime,
        bootstrap    = FALSE
      )
    }
    pf_full  <- .copy_dt(exposure_fit$full)
    keep_keys <- intersect(c(grp, "cohort", "dev"), names(pf_full))
    pf_cols   <- c(keep_keys, "exposure_obs", "exposure_proj",
                   "incr_exposure_proj")
    pf_cols   <- intersect(pf_cols, names(pf_full))
    pf_join   <- pf_full[, .SD, .SDcols = pf_cols]
    full      <- pf_join[full, on = keep_keys]
    fit$exposure_fit <- exposure_fit
  }

  # Ensure incr_exposure_proj exists (workers using legacy suffix already
  # patched, but guard anyway).
  if ("exposure_proj" %in% names(full) &&
      !"incr_exposure_proj" %in% names(full)) {
    full[, ("incr_exposure_proj") := exposure_proj -
           data.table::shift(exposure_proj, 1L, fill = 0),
         by = c(grp, "cohort")]
  }

  # `maturity_from` is an SA-specific column read by `.ratio_summary()`.
  # Non-SA workers don't produce it -- fill with NA so downstream code
  # doesn't error on missing-column references.
  if (!"maturity_from" %in% names(full)) {
    full[, ("maturity_from") := NA_real_]
  }

  # Ensure loss_ci_lo / loss_ci_hi exist --------------------------------
  if (!all(c("loss_ci_lo", "loss_ci_hi") %in% names(full)) &&
      all(c("loss_proj", "loss_total_se") %in% names(full))) {
    z_alpha <- stats::qnorm((1 + conf_level) / 2)
    full[, `:=`(
      loss_ci_lo = pmax(0, loss_proj - z_alpha * loss_total_se),
      loss_ci_hi = loss_proj + z_alpha * loss_total_se
    )]
  }

  # Ensure loss_total_cv exists -----------------------------------------
  if (!"loss_total_cv" %in% names(full) &&
      all(c("loss_total_se", "loss_proj") %in% names(full))) {
    full[, ("loss_total_cv") := data.table::fifelse(
      is.finite(loss_proj) & loss_proj != 0,
      loss_total_se / abs(loss_proj), NA_real_
    )]
  }

  fit$full <- full

  # Rebuild $proj with consistent NA-masking
  if (!is.null(fit$proj)) {
    proj <- data.table::copy(full)
    na_cols <- c(
      "loss_proj", "exposure_proj",
      "incr_loss_proj", "incr_exposure_proj",
      "loss_proc_se2", "loss_param_se2", "loss_total_se2",
      "loss_proc_se",  "loss_param_se",  "loss_total_se",
      "loss_total_cv",
      "loss_ci_lo", "loss_ci_hi"
    )
    na_cols <- intersect(na_cols, names(proj))
    proj[is_observed == TRUE, (na_cols) := NA_real_]
    fit$proj <- proj
  }

  # ci_type default
  if (is.null(fit$ci_type)) {
    fit$ci_type <- "analytical"
  }

  # Build $usage if missing (CL / BF / CC workers don't emit it) -------
  if (is.null(fit$usage)) {
    mat_for_usage <- fit$maturity
    fit$usage <- .build_usage(
      triangle,
      regime   = regime,
      recent   = recent,
      holdout  = NULL,
      maturity = mat_for_usage,
      metric   = "loss"
    )
  }

  # Class -- keep worker class for plot/summary dispatch, prepend LossFit
  class(fit) <- unique(c("LossFit", class(fit)))
  fit
}


#' Print method for `LossFit`
#'
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
  keep <- intersect(keep, names(out))
  out <- out[, .SD, .SDcols = keep]
  if ("loss_proj" %in% keep) {
    data.table::setnames(out, "loss_proj", "loss_ult")
  }
  out[]
}


# ____________________________________ ------------------------------------

# Shared grid expansion helper --------------------------------------------

#' Expand a `Triangle` object to a full projection grid (loss + exposure)
#'
#' @description
#' Internal helper used by `fit_sa()` and `fit_ed()`. Builds a complete
#' cohort x dev grid plus the projected exposure path (CL projection
#' anchored on the supplied `exposure_ata_fit`). The ED loss-side projection
#' is added downstream by the caller.
#'
#' Lives here because both `fit_sa()` (R/sa.R) and `fit_ed()` (R/ed.R)
#' need a single source of truth for the grid layout. Future cleanup may
#' relocate it to a dedicated helper file.
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
  # segment_wise.
  has_seg_ed       <- "segment_id" %in% names(ed_fit$selected)
  has_seg_exposure <- "segment_id" %in% names(exposure_ata_fit$selected)
  if (has_seg_ed || has_seg_exposure) {
    reg <- if (has_seg_ed) ed_fit$regime else exposure_ata_fit$regime
    grp_cols <- if (length(grp)) full[, grp, with = FALSE] else NULL
    full[, ("segment_id") := .assign_segment(cohort, reg, grp_cols)]
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

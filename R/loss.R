#' Fit a loss projection on a Triangle
#'
#' @description
#' Project cumulative loss across the cohort x development grid. Three
#' methods are supported via `method`:
#'
#' \describe{
#'   \item{`"sa"` (default)}{Stage-adaptive. Exposure-driven (ED) before
#'     the maturity point, chain ladder (CL) after.}
#'   \item{`"ed"`}{Pure exposure-driven (additive) across all dev
#'     periods.}
#'   \item{`"cl"`}{Pure Mack chain ladder (multiplicative).}
#' }
#'
#' This function is the *loss-side* counterpart to [fit_premium()] in
#' the role-specific dispatcher layer (see `ARCHITECTURE.md`). It owns
#' loss projection only -- premium projection is handled by
#' [fit_premium()] (when needed), and the loss-ratio composition with
#' delta method is handled by [fit_lr()].
#'
#' @param x A `"Triangle"` object.
#' @param loss Loss column to project. Default `"loss"`. Accepts bare
#'   column reference (NSE) or string.
#' @param premium Premium column (used as ED exposure). Default
#'   `"premium"`.
#' @param method One of `"sa"` (default), `"ed"`, or `"cl"`.
#' @param premium_fit Optional pre-fit `PremiumFit` (from
#'   [fit_premium()]) supplying the premium projection. When `NULL`
#'   (current default in this thin-wrapper phase) the legacy `fit_lr()`
#'   internals provide the premium chain ladder. Future phase will
#'   delegate to [fit_premium()] explicitly.
#' @param alpha Variance-structure exponent. Default `1`.
#' @param sigma_method Sigma extrapolation. One of `"locf"` (default),
#'   `"min_last2"`, `"loglinear"`.
#' @param recent Optional positive integer; calendar-diagonal filter.
#' @param regime_break Optional cohort cutoff for regime break (loss
#'   side). See [fit_lr()] for the full spec.
#' @param maturity_args A named list forwarded to [detect_maturity()].
#' @param ... Additional arguments forwarded to [fit_lr()].
#'
#' @return An object of class `"LossFit"`. Currently structured as the
#'   `LRFit` result (a thin wrapper around [fit_lr()]); future phase
#'   will strip the LR-specific columns and return a focused loss-only
#'   projection result.
#'
#' @seealso [fit_premium()], [fit_lr()], [fit_cl()], [fit_ed()].
#'
#' @examples
#' \dontrun{
#' data(experience)
#' tri <- build_triangle(experience[coverage == "SUR"], group_var = coverage)
#'
#' lf <- fit_loss(tri)                    # SA (default)
#' lf_ed <- fit_loss(tri, method = "ed")
#' lf_cl <- fit_loss(tri, method = "cl")
#' }
#'
#' @export
fit_loss <- function(x,
                     loss          = "loss",
                     premium       = "premium",
                     method        = c("sa", "ed", "cl"),
                     premium_fit   = NULL,
                     alpha         = 1,
                     sigma_method  = c("locf", "min_last2", "loglinear"),
                     recent        = NULL,
                     regime_break  = NULL,
                     maturity_args = NULL,
                     ...) {

  .assert_triangle_input(x, "fit_loss()")
  method       <- match.arg(method)
  sigma_method <- match.arg(sigma_method)

  l_var <- .capture_names(x, !!rlang::enquo(loss))
  p_var <- .capture_names(x, !!rlang::enquo(premium))
  if (length(l_var) != 1L)
    stop("`loss` must resolve to exactly one column.", call. = FALSE)
  if (length(p_var) != 1L)
    stop("`premium` must resolve to exactly one column.", call. = FALSE)

  if (!is.null(premium_fit) && !inherits(premium_fit, "PremiumFit"))
    stop("`premium_fit` must be a PremiumFit object or NULL.",
         call. = FALSE)
  if (!is.null(premium_fit))
    warning("`premium_fit` is accepted for forward-compat but not yet ",
            "consumed; fit_lr() supplies its own premium chain ladder ",
            "in this phase.", call. = FALSE)

  lr_fit <- fit_lr(
    x,
    method        = method,
    loss_var      = l_var,
    premium_var   = p_var,
    loss_alpha    = alpha,
    sigma_method  = sigma_method,
    recent        = recent,
    regime_break  = regime_break,
    maturity_args = maturity_args,
    ...
  )

  attr(lr_fit, "loss_method") <- method
  attr(lr_fit, "loss")        <- l_var
  attr(lr_fit, "premium")     <- p_var
  class(lr_fit) <- c("LossFit", class(lr_fit))
  lr_fit
}


#' Print method for `LossFit`
#' @param x A `LossFit` object.
#' @param ... Unused.
#' @export
print.LossFit <- function(x, ...) {
  method <- attr(x, "loss_method")
  cat("LossFit\n")
  cat("  loss method  :", method, "\n")
  cat("  loss         :", attr(x, "loss"), "\n")
  cat("  premium      :", attr(x, "premium"), "\n")
  cat("  n_cohorts    :", length(unique(x$full$cohort)), "\n")
  invisible(x)
}


#' Summary method for `LossFit`
#'
#' @description
#' Per-cohort loss summary: ultimate, SE, and CV. Strips the LR-specific
#' columns (`lr_ult`, `se_lr`, `cv_lr`) that the inherited LRFit summary
#' would expose.
#'
#' @param object A `LossFit` object.
#' @param ... Unused.
#' @export
summary.LossFit <- function(object, ...) {
  full <- data.table::as.data.table(object$full)
  out <- full[, .SD[which.max(dev)], by = cohort]
  out[, .(cohort,
          ultimate    = loss_proj,
          se_ultimate = se_proj,
          cv_ultimate = cv_proj)]
}

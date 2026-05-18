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
#' This is a *standalone* worker -- it does not currently integrate
#' with [fit_loss()] / [fit_ratio()]. Point projection only.
#'
#' @param x A `Triangle` object.
#' @param loss A single cumulative loss variable. Default `"loss"`.
#' @param exposure A single cumulative exposure variable. Default
#'   `"exposure"`.
#' @param ... Reserved for future extension (currently unused).
#'
#' @return An object of class `"CapeCodFit"` containing:
#'   \describe{
#'     \item{`call`}{The matched call.}
#'     \item{`data`}{The input `Triangle`.}
#'     \item{`method`}{`"capecod"`.}
#'     \item{`groups`, `cohort`, `dev`, `loss`, `exposure`}{Metadata.}
#'     \item{`full`, `proj`, `summary`}{Same shape as `BFFit`.}
#'     \item{`elr_cc`}{`data.table(group..., elr_cc)` -- the pooled ELR
#'       per group (or scalar if no group).}
#'     \item{`q`}{Per-cohort emerged fraction.}
#'     \item{`cl_fit`, `exposure_fit`}{Inner CL / Exposure fits.}
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
#' cc <- fit_capecod(tri)
#' summary(cc)
#' cc$elr_cc   # pooled ELR per group
#' }
#'
#' @keywords internal
#' @export
fit_capecod <- function(x,
                        loss     = "loss",
                        exposure = "exposure",
                        ...) {

  # data.table NSE bindings
  cohort <- elr <- elr_cc <- loss_obs <- loss_proj <- exposure_proj <- NULL
  is_observed <- q <- loss_latest <- exposure_ult <- NULL

  .assert_triangle_input(x, "fit_capecod()")

  grp <- attr(x, "groups")
  if (is.null(grp)) grp <- character(0)
  by_cols <- c(grp, "cohort")

  # 1) CL on loss for q_i + ultimate exposure -----------------------------
  cl_fit       <- fit_cl(x, loss = loss)
  exposure_fit <- fit_exposure(x, method = "cl", bootstrap = FALSE)

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

  # 8) assemble output ----------------------------------------------------
  out <- list(
    call         = match.call(),
    data         = x,
    method       = "capecod",
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
    exposure_fit = exposure_fit
  )
  class(out) <- "CapeCodFit"
  out
}


#' Print method for `CapeCodFit`
#'
#' @param x A `CapeCodFit` object.
#' @param ... Unused.
#'
#' @method print CapeCodFit
#' @export
print.CapeCodFit <- function(x, ...) {

  cat("<CapeCodFit>\n")
  cat("method        :", x$method,    "\n")
  cat("loss          :", x$loss,      "\n")
  cat("exposure      :", x$exposure,  "\n")
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
  invisible(x)
}


#' Summary method for `CapeCodFit`
#'
#' @param object A `CapeCodFit` object.
#' @param ... Unused.
#'
#' @method summary CapeCodFit
#' @export
summary.CapeCodFit <- function(object, ...) {
  object$summary
}

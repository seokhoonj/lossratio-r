# Setup
data(experience)
sub <- as_triangle(experience[coverage == "surgery"],
                   groups   = "coverage",
                   cohort   = "uy_m",
                   calendar = "cy_m",
                   loss     = "incr_loss",
                   exposure = "incr_exposure")


test_that("fit_capecod returns class 'CapeCodFit'", {
  fit <- fit_capecod(sub)
  expect_s3_class(fit, "CapeCodFit")
  expect_equal(fit$method, "capecod")
})

test_that("fit_capecod produces a single pooled ELR per group", {
  fit <- fit_capecod(sub)
  expect_true("elr_cc" %in% names(fit$elr_cc))
  expect_equal(nrow(fit$elr_cc), 1L)   # single group
  expect_gt(fit$elr_cc$elr_cc, 0)
})

test_that("fit_capecod $summary uses the pooled ELR for every cohort", {
  fit <- fit_capecod(sub)
  elr_cc <- fit$elr_cc$elr_cc[1L]
  expect_true(all(abs(fit$summary$elr - elr_cc) < 1e-10))
})

test_that("fit_capecod reserve is non-negative for non-fully-emerged cohorts", {
  fit <- fit_capecod(sub)
  with_dev <- fit$summary[fit$summary$q < 1, ]
  expect_true(all(with_dev$reserve >= 0))
})

test_that("fit_capecod $full and $proj match the BFFit cell layout", {
  fit <- fit_capecod(sub)
  for (nm in c("loss_obs", "loss_proj", "exposure_proj",
               "is_observed", "incr_loss_proj")) {
    expect_true(nm %in% names(fit$full), info = paste("missing", nm))
  }
  n_full_na <- sum(is.na(fit$full$loss_proj))
  n_proj_na <- sum(is.na(fit$proj$loss_proj))
  expect_gt(n_proj_na, n_full_na)
})

test_that("fit_capecod pooled ELR matches the Stanard 1985 closed form", {
  fit <- fit_capecod(sub)
  # Reproduce the Cape Cod ELR directly from the underlying CL and
  # exposure fits to make sure the formula is implemented as documented.
  cl_fit  <- fit$cl_fit
  exp_fit <- fit$exposure_fit
  by_cols <- c(fit$groups, "cohort")

  loss_latest <- cl_fit$full[is_observed == TRUE,
                              .SD[.N, .(L = loss_obs)],
                              by = by_cols]
  loss_ult_cl <- cl_fit$full[, .SD[.N, .(L_ult = loss_proj)],
                              by = by_cols]
  q_dt <- loss_latest[loss_ult_cl, on = by_cols]
  q_dt[, q := L / L_ult]
  exp_ult <- exp_fit$full[, .SD[.N, .(E = exposure_proj)],
                          by = by_cols]
  q_dt <- exp_ult[q_dt, on = by_cols]

  expected_elr <- sum(q_dt$L, na.rm = TRUE) /
                  sum(q_dt$E * q_dt$q, na.rm = TRUE)
  expect_equal(fit$elr_cc$elr_cc[1L], expected_elr, tolerance = 1e-10)
})

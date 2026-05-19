# Tests for fit_sa() worker

test_that("fit_sa(tri) returns SAFit class", {
  tri <- make_sub_tri("surgery")
  sa  <- fit_sa(tri, bootstrap = FALSE)
  expect_s3_class(sa, "SAFit")
  expect_identical(sa$method, "sa")
})

test_that("fit_sa $full carries the LossFit-compatible columns", {
  tri <- make_sub_tri("surgery")
  sa  <- fit_sa(tri, bootstrap = FALSE)
  for (nm in c("cohort", "dev",
               "loss_obs", "exposure_obs", "is_observed",
               "loss_proj", "exposure_proj",
               "incr_loss_proj", "incr_exposure_proj",
               "loss_total_se", "loss_total_cv",
               "loss_ci_lo", "loss_ci_hi")) {
    expect_true(nm %in% names(sa$full), info = paste("missing", nm))
  }
})

test_that("fit_sa exposes ed / loss_ata_fit / exposure_ata_fit slots", {
  tri <- make_sub_tri("surgery")
  sa  <- fit_sa(tri, bootstrap = FALSE)
  expect_true(!is.null(sa$ed))
  expect_s3_class(sa$loss_ata_fit,     "ATAFit")
  expect_s3_class(sa$exposure_ata_fit, "ATAFit")
  expect_s3_class(sa$exposure_fit,     "ExposureFit")
})

test_that("fit_sa default uses bootstrap (ci_type = 'bootstrap')", {
  tri <- make_sub_tri("surgery")
  sa  <- fit_sa(tri, B = 30, seed = 1)
  expect_identical(sa$ci_type, "bootstrap")
  expect_false(is.null(sa$bootstrap))
})

test_that("fit_sa bootstrap = FALSE falls back to analytical", {
  tri <- make_sub_tri("surgery")
  sa  <- fit_sa(tri, bootstrap = FALSE)
  expect_identical(sa$ci_type, "analytical")
  expect_null(sa$bootstrap)
})

test_that("summary(SAFit) returns per-cohort ultimate loss table", {
  tri <- make_sub_tri("surgery")
  sa  <- fit_sa(tri, bootstrap = FALSE)
  s   <- summary(sa)
  expect_true(inherits(s, "data.table"))
  for (nm in c("cohort", "loss_ult", "loss_total_se", "loss_total_cv")) {
    expect_true(nm %in% names(s), info = paste("missing", nm))
  }
})

test_that("print(SAFit) does not error", {
  tri <- make_sub_tri("surgery")
  sa  <- fit_sa(tri, bootstrap = FALSE)
  expect_no_error(capture.output(print(sa)))
})

test_that("fit_sa(tri) == fit_loss(tri, method='sa') byte-identical loss_proj", {
  tri    <- make_sub_tri("surgery")
  sa     <- fit_sa(tri, bootstrap = FALSE)
  via_lf <- fit_loss(tri, method = "sa", bootstrap = FALSE)
  expect_equal(sa$full$loss_proj, via_lf$full$loss_proj, tolerance = 0)
})

test_that("fit_sa supports a Maturity object (eager override)", {
  tri <- make_sub_tri("surgery")
  m   <- maturity_at(coverage = "surgery", change = 4)
  sa  <- fit_sa(tri, maturity = m, bootstrap = FALSE)
  expect_s3_class(sa$maturity, "Maturity")
  expect_equal(sa$maturity$change, 4)
})

test_that("fit_sa accepts a Regime object (hybrid filter path)", {
  tri <- make_sub_tri("surgery")
  reg <- regime_at(change = "2025-07-01")
  sa  <- fit_sa(tri, regime = reg, bootstrap = FALSE)
  expect_s3_class(sa, "SAFit")
  expect_s3_class(sa$regime, "Regime")
})

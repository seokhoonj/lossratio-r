# Setup
data(experience)
exp <- as_experience(experience)
tri <- build_triangle(exp, group_var = cv_nm)

test_that("fit_lr default (method = 'sa') returns class 'LRFit'", {
  lr <- fit_lr(tri)
  expect_s3_class(lr, "LRFit")
  expect_equal(lr$method, "sa")
})

test_that("LRFit has expected list elements", {
  lr <- fit_lr(tri, method = "sa")
  for (nm in c("data", "method", "group_var", "cohort_var", "dev_var",
               "loss_var", "exposure_var", "full", "pred", "summary",
               "ed", "loss_ata_fit", "exposure_ata_fit", "maturity",
               "delta_method", "rho", "conf_level")) {
    expect_true(nm %in% names(lr), info = paste("missing", nm))
  }
})

test_that("$full has expected columns", {
  lr <- fit_lr(tri, method = "sa")
  for (nm in c("cv_nm", "cohort", "dev", "loss_obs", "exposure_obs",
               "is_observed",
               "loss_proj", "exposure_proj", "lr_proj",
               "loss_inc_proj", "exposure_inc_proj", "lr_inc_proj")) {
    expect_true(nm %in% names(lr$full), info = paste("missing", nm))
  }
})

test_that("incremental projections recover cumulative via per-cohort cumsum", {
  lr <- fit_lr(tri, method = "sa")
  full <- data.table::copy(lr$full)
  data.table::setorder(full, cv_nm, cohort, dev)
  full[, .loss_recovered     := cumsum(loss_inc_proj),     by = .(cv_nm, cohort)]
  full[, .exposure_recovered := cumsum(exposure_inc_proj), by = .(cv_nm, cohort)]
  rows <- full[is.finite(loss_proj) & is.finite(loss_inc_proj)]
  expect_equal(rows$.loss_recovered,     rows$loss_proj,     tolerance = 1e-8)
  expect_equal(rows$.exposure_recovered, rows$exposure_proj, tolerance = 1e-8)
})

test_that("$pred masks incremental projections on observed cells", {
  lr <- fit_lr(tri, method = "sa")
  obs <- lr$pred[lr$pred$is_observed == TRUE, ]
  expect_true(all(is.na(obs$loss_inc_proj)))
  expect_true(all(is.na(obs$exposure_inc_proj)))
  expect_true(all(is.na(obs$lr_inc_proj)))
})

test_that("$summary has cohort-level entries with expected columns", {
  lr <- fit_lr(tri, method = "sa")
  for (nm in c("cv_nm", "cohort", "latest", "ultimate", "reserve")) {
    expect_true(nm %in% names(lr$summary), info = paste("missing", nm))
  }
})

test_that("methods 'sa', 'ed', 'cl' all run", {
  for (m in c("sa", "ed", "cl")) {
    lr <- fit_lr(tri, method = m)
    expect_s3_class(lr, "LRFit")
    expect_equal(lr$method, m)
  }
})

test_that("delta_method 'simple' and 'full' both run", {
  expect_s3_class(fit_lr(tri, delta_method = "simple"), "LRFit")
  expect_s3_class(fit_lr(tri, delta_method = "full", rho = 0.3), "LRFit")
})

test_that("bootstrap = TRUE runs and returns class 'LRFit'", {
  lr_b <- fit_lr(tri, method = "sa", bootstrap = TRUE, B = 25, seed = 1)
  expect_s3_class(lr_b, "LRFit")
  expect_false(is.null(lr_b$bootstrap))
})

test_that("bootstrap reproducibility via seed", {
  lr_a <- fit_lr(tri, method = "sa", bootstrap = TRUE, B = 25, seed = 42)
  lr_b <- fit_lr(tri, method = "sa", bootstrap = TRUE, B = 25, seed = 42)
  expect_equal(lr_a$summary$ci_lower, lr_b$summary$ci_lower)
})

test_that("summary(LRFit) returns the $summary table", {
  lr <- fit_lr(tri, method = "sa")
  expect_identical(summary(lr), lr$summary)
})

test_that("print.LRFit doesn't error", {
  lr <- fit_lr(tri, method = "sa")
  expect_no_error(capture.output(print(lr)))
})

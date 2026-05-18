# Setup
data(experience)
exp <- experience
tri <- as_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")

test_that("fit_ratio default (method = 'ed') returns class 'RatioFit'", {
  lr <- fit_ratio(tri, bootstrap = FALSE)
  expect_s3_class(lr, "RatioFit")
  expect_equal(lr$method, "ed")
})

test_that("RatioFit has expected list elements", {
  lr <- fit_ratio(tri, method = "sa", bootstrap = FALSE)
  for (nm in c("data", "method", "groups", "cohort", "dev",
               "full", "proj", "summary",
               "ed", "loss_ata_fit", "exposure_ata_fit", "maturity",
               "se_method", "rho", "conf_level",
               "loss_regime", "exposure_regime")) {
    expect_true(nm %in% names(lr), info = paste("missing", nm))
  }
})

test_that("$full has expected columns", {
  lr <- fit_ratio(tri, method = "sa", bootstrap = FALSE)
  for (nm in c("coverage", "cohort", "dev", "loss_obs", "exposure_obs",
               "is_observed",
               "loss_proj", "exposure_proj", "ratio_proj",
               "incr_loss_proj", "incr_exposure_proj", "incr_ratio_proj")) {
    expect_true(nm %in% names(lr$full), info = paste("missing", nm))
  }
})

test_that("incremental projections recover cumulative via per-cohort cumsum", {
  lr <- fit_ratio(tri, method = "sa", bootstrap = FALSE)
  full <- data.table::copy(lr$full)
  data.table::setorder(full, coverage, cohort, dev)
  full[, .loss_recovered     := cumsum(incr_loss_proj),     by = .(coverage, cohort)]
  full[, .exposure_recovered := cumsum(incr_exposure_proj), by = .(coverage, cohort)]
  rows <- full[is.finite(loss_proj) & is.finite(incr_loss_proj)]
  expect_equal(rows$.loss_recovered,     rows$loss_proj,     tolerance = 1e-8)
  expect_equal(rows$.exposure_recovered, rows$exposure_proj, tolerance = 1e-8)
})

test_that("$pred masks incremental projections on observed cells", {
  lr <- fit_ratio(tri, method = "sa", bootstrap = FALSE)
  obs <- lr$pred[lr$pred$is_observed == TRUE, ]
  expect_true(all(is.na(obs$incr_loss_proj)))
  expect_true(all(is.na(obs$incr_exposure_proj)))
  expect_true(all(is.na(obs$incr_ratio_proj)))
})

test_that("$summary has cohort-level entries with expected columns", {
  lr <- fit_ratio(tri, method = "sa", bootstrap = FALSE)
  for (nm in c("coverage", "cohort", "latest", "loss_ult", "reserve")) {
    expect_true(nm %in% names(lr$summary), info = paste("missing", nm))
  }
})

test_that("methods 'sa', 'ed', 'cl' all run", {
  for (m in c("sa", "ed", "cl")) {
    lr <- fit_ratio(tri, method = m, bootstrap = FALSE)
    expect_s3_class(lr, "RatioFit")
    expect_equal(lr$method, m)
  }
})

test_that("se_method 'fixed' and 'delta' both run", {
  expect_s3_class(fit_ratio(tri, se_method = "fixed", bootstrap = FALSE), "RatioFit")
  expect_s3_class(fit_ratio(tri, se_method = "delta", rho = 0.3, bootstrap = FALSE), "RatioFit")
})

test_that("bootstrap = TRUE runs and returns class 'RatioFit'", {
  lr_b <- fit_ratio(tri, method = "sa", bootstrap = TRUE, B = 25, seed = 1)
  expect_s3_class(lr_b, "RatioFit")
  expect_false(is.null(lr_b$bootstrap))
})

test_that("bootstrap reproducibility via seed", {
  lr_a <- fit_ratio(tri, method = "sa", bootstrap = TRUE, B = 25, seed = 42)
  lr_b <- fit_ratio(tri, method = "sa", bootstrap = TRUE, B = 25, seed = 42)
  expect_equal(lr_a$summary$ratio_ci_lo, lr_b$summary$ratio_ci_lo)
})

test_that("summary(RatioFit) returns the $summary table", {
  lr <- fit_ratio(tri, method = "sa", bootstrap = FALSE)
  expect_identical(summary(lr), lr$summary)
})

test_that("print.RatioFit doesn't error", {
  lr <- fit_ratio(tri, method = "sa", bootstrap = FALSE)
  expect_no_error(capture.output(print(lr)))
})

test_that("fit_ratio with loss_regime + method=sa applies hybrid filter", {
  data(experience)
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")
  reg <- regime_at(change = "2025-07-01")
  fit_full <- fit_ratio(tri, method = "sa", bootstrap = FALSE)
  fit_brk  <- fit_ratio(tri, method = "sa", loss_regime = reg,
                     recent = 18L, bootstrap = FALSE)
  # ED parameters (g_sel) should differ for early dev (k < k*)
  expect_false(identical(fit_full$selected$g_sel,
                         fit_brk$selected$g_sel))
  expect_s3_class(fit_brk$loss_regime, "Regime")
})

test_that("fit_ratio with loss_regime + method=ed drops pre-break cohorts", {
  data(experience)
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")
  reg <- regime_at(change = "2025-07-01")
  fit_full <- fit_ratio(tri, method = "ed", bootstrap = FALSE)
  fit_brk  <- fit_ratio(tri, method = "ed", loss_regime = reg, bootstrap = FALSE)
  expect_false(identical(fit_full$full$ratio_proj, fit_brk$full$ratio_proj))
})

test_that("fit_ratio with NULL loss_regime is unchanged", {
  data(experience)
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")
  a <- fit_ratio(tri, method = "sa", bootstrap = FALSE)
  b <- fit_ratio(tri, method = "sa", loss_regime = NULL, bootstrap = FALSE)
  expect_identical(a$full$ratio_proj, b$full$ratio_proj)
})

test_that("fit_ratio with Regime preserves the Regime object", {
  data(experience)
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")
  reg <- detect_regime(tri)
  fit_reg <- fit_ratio(tri, method = "sa", loss_regime = reg, recent = 18L, bootstrap = FALSE)
  expect_s3_class(fit_reg$loss_regime, "Regime")
  expect_identical(fit_reg$loss_regime$changes, reg$changes)
})

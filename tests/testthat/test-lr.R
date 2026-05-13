# Setup
data(experience)
exp <- experience
tri <- build_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")

test_that("fit_lr default (method = 'sa') returns class 'LRFit'", {
  lr <- fit_lr(tri)
  expect_s3_class(lr, "LRFit")
  expect_equal(lr$method, "sa")
})

test_that("LRFit has expected list elements", {
  lr <- fit_lr(tri, method = "sa")
  for (nm in c("data", "method", "groups", "cohort", "dev",
               "full", "proj", "summary",
               "ed", "loss_ata_fit", "premium_ata_fit", "maturity",
               "se_method", "rho", "conf_level",
               "loss_regime", "premium_regime")) {
    expect_true(nm %in% names(lr), info = paste("missing", nm))
  }
})

test_that("$full has expected columns", {
  lr <- fit_lr(tri, method = "sa")
  for (nm in c("coverage", "cohort", "dev", "loss_obs", "premium_obs",
               "is_observed",
               "loss_proj", "premium_proj", "lr_proj",
               "loss_incr_proj", "premium_incr_proj", "lr_incr_proj")) {
    expect_true(nm %in% names(lr$full), info = paste("missing", nm))
  }
})

test_that("incremental projections recover cumulative via per-cohort cumsum", {
  lr <- fit_lr(tri, method = "sa")
  full <- data.table::copy(lr$full)
  data.table::setorder(full, coverage, cohort, dev)
  full[, .loss_recovered     := cumsum(loss_incr_proj),     by = .(coverage, cohort)]
  full[, .premium_recovered := cumsum(premium_incr_proj), by = .(coverage, cohort)]
  rows <- full[is.finite(loss_proj) & is.finite(loss_incr_proj)]
  expect_equal(rows$.loss_recovered,     rows$loss_proj,     tolerance = 1e-8)
  expect_equal(rows$.premium_recovered, rows$premium_proj, tolerance = 1e-8)
})

test_that("$pred masks incremental projections on observed cells", {
  lr <- fit_lr(tri, method = "sa")
  obs <- lr$pred[lr$pred$is_observed == TRUE, ]
  expect_true(all(is.na(obs$loss_incr_proj)))
  expect_true(all(is.na(obs$premium_incr_proj)))
  expect_true(all(is.na(obs$lr_incr_proj)))
})

test_that("$summary has cohort-level entries with expected columns", {
  lr <- fit_lr(tri, method = "sa")
  for (nm in c("coverage", "cohort", "latest", "loss_ult", "reserve")) {
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

test_that("se_method 'fixed' and 'delta' both run", {
  expect_s3_class(fit_lr(tri, se_method = "fixed"), "LRFit")
  expect_s3_class(fit_lr(tri, se_method = "delta", rho = 0.3), "LRFit")
})

test_that("bootstrap = TRUE runs and returns class 'LRFit'", {
  lr_b <- fit_lr(tri, method = "sa", bootstrap = TRUE, B = 25, seed = 1)
  expect_s3_class(lr_b, "LRFit")
  expect_false(is.null(lr_b$bootstrap))
})

test_that("bootstrap reproducibility via seed", {
  lr_a <- fit_lr(tri, method = "sa", bootstrap = TRUE, B = 25, seed = 42)
  lr_b <- fit_lr(tri, method = "sa", bootstrap = TRUE, B = 25, seed = 42)
  expect_equal(lr_a$summary$lr_ci_lower, lr_b$summary$lr_ci_lower)
})

test_that("summary(LRFit) returns the $summary table", {
  lr <- fit_lr(tri, method = "sa")
  expect_identical(summary(lr), lr$summary)
})

test_that("print.LRFit doesn't error", {
  lr <- fit_lr(tri, method = "sa")
  expect_no_error(capture.output(print(lr)))
})

test_that("fit_lr with loss_regime + method=sa applies hybrid filter", {
  data(experience)
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  reg <- regime_at(breakpoint = "2025-07-01")
  fit_full <- fit_lr(tri, method = "sa")
  fit_brk  <- fit_lr(tri, method = "sa", loss_regime = reg,
                     recent = 18L)
  # ED parameters (g_selected) should differ for early dev (k < k*)
  expect_false(identical(fit_full$selected$g_selected,
                         fit_brk$selected$g_selected))
  expect_s3_class(fit_brk$loss_regime, "Regime")
})

test_that("fit_lr with loss_regime + method=ed drops pre-break cohorts", {
  data(experience)
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  reg <- regime_at(breakpoint = "2025-07-01")
  fit_full <- fit_lr(tri, method = "ed")
  fit_brk  <- fit_lr(tri, method = "ed", loss_regime = reg)
  expect_false(identical(fit_full$full$lr_proj, fit_brk$full$lr_proj))
})

test_that("fit_lr with NULL loss_regime is unchanged", {
  data(experience)
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  a <- fit_lr(tri, method = "sa")
  b <- fit_lr(tri, method = "sa", loss_regime = NULL)
  expect_identical(a$full$lr_proj, b$full$lr_proj)
})

test_that("fit_lr with Regime preserves the Regime object", {
  data(experience)
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  reg <- detect_regime(tri)
  fit_reg <- fit_lr(tri, method = "sa", loss_regime = reg, recent = 18L)
  expect_s3_class(fit_reg$loss_regime, "Regime")
  expect_identical(fit_reg$loss_regime$breakpoints, reg$breakpoints)
})

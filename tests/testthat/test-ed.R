# Setup
data(experience)
exp <- experience
tri <- build_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
ed  <- build_link(tri, target = "loss", exposure = "premium")

test_that("build_link (ED mode) returns class 'Link' with expected columns", {
  expect_s3_class(ed, "Link")
  for (nm in c("coverage", "cohort", "ata_from", "ata_to", "ata_link",
               "target_from", "target_to", "target_delta",
               "exposure_from", "exposure_to", "intensity")) {
    expect_true(nm %in% names(ed), info = paste("missing", nm))
  }
})

test_that("build_link (ED mode) attributes set correctly", {
  for (a in c("groups", "cohort", "dev", "target", "exposure")) {
    expect_false(is.null(attr(ed, a)), info = paste("missing attr", a))
  }
})

test_that("intensity == target_delta / exposure_from when exposure_from > 0", {
  ok <- is.finite(ed$intensity) & ed$exposure_from > 0
  expect_equal(ed$intensity[ok],
               ed$target_delta[ok] / ed$exposure_from[ok], tolerance = 1e-6)
})

test_that("target_delta == target_to - target_from", {
  ok <- is.finite(ed$target_delta)
  expect_equal(ed$target_delta[ok],
               ed$target_to[ok] - ed$target_from[ok],
               tolerance = 1e-6)
})

test_that("build_link warns (self-anchored) when target == exposure", {
  # Self-anchored ED is mathematically equivalent to chain ladder on
  # the same column (f_k = 1 + g_k). Allowed, but warned.
  expect_warning(
    build_link(tri, target = "loss", exposure = "loss"),
    "self-anchored"
  )
})

# fit_ed -----------------------------------------------------------------

test_that("fit_ed returns class 'EDFit' with expected components", {
  ef <- fit_ed(tri, target = "loss", exposure = "premium")
  expect_s3_class(ef, "EDFit")
  for (nm in c("factor", "selected")) {
    expect_true(nm %in% names(ef), info = paste("missing", nm))
  }
})

test_that("fit_ed method = 'mack' works", {
  ef_mack <- fit_ed(tri, target = "loss", exposure = "premium", method = "mack")
  expect_s3_class(ef_mack, "EDFit")
})

test_that("fit_ed sigma_method variants run", {
  for (sm in c("min_last2", "locf", "loglinear")) {
    expect_no_error(fit_ed(tri, target = "loss", exposure = "premium", sigma_method = sm))
  }
})

test_that("recent reduces selected rows count", {
  ef_full   <- fit_ed(tri, target = "loss", exposure = "premium")
  ef_recent <- fit_ed(tri, target = "loss", exposure = "premium", recent = 6)
  expect_true(nrow(ef_recent$selected) <= nrow(ef_full$selected))
})

test_that("print.EDFit doesn't error", {
  ef <- fit_ed(tri, target = "loss", exposure = "premium")
  expect_no_error(capture.output(print(ef)))
})

# summary.Link (ED mode) -------------------------------------------------

test_that("summary.Link (ed mode) returns EDSummary with expected columns", {
  smr <- summary(ed, alpha = 1)
  expect_s3_class(smr, "EDSummary")
  for (nm in c("ata_from", "ata_to", "mean", "median", "wt", "g")) {
    expect_true(nm %in% names(smr), info = paste("missing", nm))
  }
})

# regime -----------------------------------------------------------------

test_that("fit_ed with regime drops pre-break cohorts", {
  data(experience)
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  ed <- build_link(tri, target = "loss", exposure = "premium")
  fit_full <- fit_ed(tri, target = "loss", exposure = "premium")
  fit_brk  <- fit_ed(tri, target = "loss", exposure = "premium",
                     regime = regime_at(breakpoint = "2025-07-01"))
  expect_false(identical(fit_full$selected$g_selected,
                         fit_brk$selected$g_selected))
  expect_s3_class(fit_brk$regime, "Regime")
})

test_that("fit_ed with NULL regime is unchanged", {
  data(experience)
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  ed <- build_link(tri, target = "loss", exposure = "premium")
  fit_default <- fit_ed(tri, target = "loss", exposure = "premium")
  fit_null    <- fit_ed(tri, target = "loss", exposure = "premium", regime = NULL)
  expect_identical(fit_default$selected$g_selected,
                   fit_null$selected$g_selected)
})

test_that("fit_ed with Regime input preserves the Regime object", {
  data(experience)
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  reg <- detect_regime(tri)
  ed <- build_link(tri, target = "loss", exposure = "premium")
  fit_reg <- fit_ed(tri, target = "loss", exposure = "premium", regime = reg)
  expect_s3_class(fit_reg$regime, "Regime")
  expect_identical(fit_reg$regime$breakpoints, reg$breakpoints)
})

# fit_ed $full projection -----------------------------------------------

test_that("fit_ed returns $full with projection columns", {
  data(experience)
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  ef <- fit_ed(tri, target = "loss", exposure = "premium")
  expect_true("full" %in% names(ef))
  expect_s3_class(ef$full, "data.table")
  # Worker layer: target projection + exposure projection only.
  # LR composition (lr_proj, lr_se, lr_cv) belongs to fit_lr().
  for (nm in c("cohort", "dev", "target_obs", "exposure_obs",
               "target_proj", "exposure_proj",
               "target_total_se", "is_observed")) {
    expect_true(nm %in% names(ef$full), info = paste("missing", nm))
  }
  # projection columns finite for at least some cells
  expect_true(any(is.finite(ef$full$target_proj)))
  expect_true(any(is.finite(ef$full$exposure_proj)))
})

test_that("fit_ed target projection matches fit_lr method = 'ed'", {
  data(experience)
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  ef <- fit_ed(tri, target = "loss", exposure = "premium")
  lr <- fit_lr(tri, method = "ed")

  # Worker (fit_ed) produces the target/exposure projection; the LR
  # composition (lr_proj) is fit_lr's concern. Compare common columns.
  expect_equal(ef$full$target_proj,     lr$full$loss_proj,       tolerance = 1e-8)
  expect_equal(ef$full$exposure_proj,   lr$full$premium_proj,    tolerance = 1e-8)
  expect_equal(ef$full$target_total_se, lr$full$loss_total_se,   tolerance = 1e-8)
})

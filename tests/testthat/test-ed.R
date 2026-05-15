# Setup
data(experience)
exp <- experience
tri <- as_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_prem")
ed  <- as_link(tri, target = "loss", exposure = "prem")

test_that("as_link (ED mode) returns class 'Link' with expected columns", {
  expect_s3_class(ed, "Link")
  for (nm in c("coverage", "cohort", "ata_from", "ata_to", "ata_link",
               "target_from", "target_to", "target_delta",
               "exposure_from", "exposure_to", "intensity")) {
    expect_true(nm %in% names(ed), info = paste("missing", nm))
  }
})

test_that("as_link (ED mode) attributes set correctly", {
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

test_that("as_link warns (self-anchored) when target == exposure", {
  # Self-anchored ED is mathematically equivalent to chain ladder on
  # the same column (f_k = 1 + g_k). Allowed, but warned.
  expect_warning(
    as_link(tri, target = "loss", exposure = "loss"),
    "self-anchored"
  )
})

# fit_ed -----------------------------------------------------------------

test_that("fit_ed returns class 'EDFit' with expected components", {
  ef <- fit_ed(tri, target = "loss", exposure = "prem")
  expect_s3_class(ef, "EDFit")
  for (nm in c("factor", "selected")) {
    expect_true(nm %in% names(ef), info = paste("missing", nm))
  }
})

test_that("fit_ed method = 'mack' works", {
  ef_mack <- fit_ed(tri, target = "loss", exposure = "prem", method = "mack")
  expect_s3_class(ef_mack, "EDFit")
})

test_that("fit_ed sigma_method variants run", {
  for (sm in c("min_last2", "locf", "loglinear")) {
    expect_no_error(fit_ed(tri, target = "loss", exposure = "prem", sigma_method = sm))
  }
})

test_that("recent reduces selected rows count", {
  ef_full   <- fit_ed(tri, target = "loss", exposure = "prem")
  ef_recent <- fit_ed(tri, target = "loss", exposure = "prem", recent = 6)
  expect_true(nrow(ef_recent$selected) <= nrow(ef_full$selected))
})

test_that("print.EDFit doesn't error", {
  ef <- fit_ed(tri, target = "loss", exposure = "prem")
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
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_prem")
  ed <- as_link(tri, target = "loss", exposure = "prem")
  fit_full <- fit_ed(tri, target = "loss", exposure = "prem")
  fit_brk  <- fit_ed(tri, target = "loss", exposure = "prem",
                     regime = regime_at(change = "2025-07-01"))
  expect_false(identical(fit_full$selected$g_sel,
                         fit_brk$selected$g_sel))
  expect_s3_class(fit_brk$regime, "Regime")
})

test_that("fit_ed with NULL regime is unchanged", {
  data(experience)
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_prem")
  ed <- as_link(tri, target = "loss", exposure = "prem")
  fit_default <- fit_ed(tri, target = "loss", exposure = "prem")
  fit_null    <- fit_ed(tri, target = "loss", exposure = "prem", regime = NULL)
  expect_identical(fit_default$selected$g_sel,
                   fit_null$selected$g_sel)
})

test_that("fit_ed with Regime input preserves the Regime object", {
  data(experience)
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_prem")
  reg <- detect_regime(tri)
  ed <- as_link(tri, target = "loss", exposure = "prem")
  fit_reg <- fit_ed(tri, target = "loss", exposure = "prem", regime = reg)
  expect_s3_class(fit_reg$regime, "Regime")
  expect_identical(fit_reg$regime$changes, reg$changes)
})

# fit_ed $full projection -----------------------------------------------

test_that("fit_ed returns $full with projection columns", {
  data(experience)
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_prem")
  ef <- fit_ed(tri, target = "loss", exposure = "prem")
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
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_prem")
  ef <- fit_ed(tri, target = "loss", exposure = "prem")
  lr <- fit_lr(tri, method = "ed", bootstrap = FALSE)

  # Worker (fit_ed) produces the target/exposure projection; the LR
  # composition (lr_proj) is fit_lr's concern. Compare common columns.
  expect_equal(ef$full$target_proj,     lr$full$loss_proj,       tolerance = 1e-8)
  expect_equal(ef$full$exposure_proj,   lr$full$prem_proj,    tolerance = 1e-8)
  expect_equal(ef$full$target_total_se, lr$full$loss_total_se,   tolerance = 1e-8)
})

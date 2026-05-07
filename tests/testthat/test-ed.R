# Setup
data(experience)
exp <- as_experience(experience)
tri <- build_triangle(exp, group_var = cv_nm)
ed  <- build_link(tri, value_var = "closs", exposure_var = "crp")

test_that("build_link (ED mode) returns class 'Link' with expected columns", {
  expect_s3_class(ed, "Link")
  for (nm in c("cv_nm", "cohort", "ata_from", "ata_to", "ata_link",
               "value_from", "value_to", "delta_value",
               "exposure_from", "exposure_to", "g")) {
    expect_true(nm %in% names(ed), info = paste("missing", nm))
  }
})

test_that("build_link (ED mode) attributes set correctly", {
  for (a in c("group_var", "cohort_var", "dev_var", "value_var", "exposure_var")) {
    expect_false(is.null(attr(ed, a)), info = paste("missing attr", a))
  }
})

test_that("g == delta_value / exposure_from when exposure_from > 0", {
  ok <- is.finite(ed$g) & ed$exposure_from > 0
  expect_equal(ed$g[ok], ed$delta_value[ok] / ed$exposure_from[ok], tolerance = 1e-6)
})

test_that("delta_value == value_to - value_from", {
  ok <- is.finite(ed$delta_value)
  expect_equal(ed$delta_value[ok],
               ed$value_to[ok] - ed$value_from[ok],
               tolerance = 1e-6)
})

test_that("build_link errors when value_var == exposure_var", {
  expect_error(build_link(tri, value_var = "closs", exposure_var = "closs"))
})

# fit_ed -----------------------------------------------------------------

test_that("fit_ed returns class 'EDFit' with expected components", {
  ef <- fit_ed(tri, value_var = "closs", exposure_var = "crp")
  expect_s3_class(ef, "EDFit")
  for (nm in c("factor", "selected")) {
    expect_true(nm %in% names(ef), info = paste("missing", nm))
  }
})

test_that("fit_ed method = 'basic' and 'mack' both work", {
  expect_no_error(fit_ed(tri, value_var = "closs", exposure_var = "crp", method = "basic"))
  ef_mack <- fit_ed(tri, value_var = "closs", exposure_var = "crp", method = "mack")
  expect_s3_class(ef_mack, "EDFit")
})

test_that("fit_ed sigma_method variants run", {
  for (sm in c("min_last2", "locf", "loglinear")) {
    expect_no_error(fit_ed(tri, value_var = "closs", exposure_var = "crp", sigma_method = sm))
  }
})

test_that("recent reduces selected rows count", {
  ef_full   <- fit_ed(tri, value_var = "closs", exposure_var = "crp")
  ef_recent <- fit_ed(tri, value_var = "closs", exposure_var = "crp", recent = 6)
  expect_true(nrow(ef_recent$selected) <= nrow(ef_full$selected))
})

test_that("print.EDFit doesn't error", {
  ef <- fit_ed(tri, value_var = "closs", exposure_var = "crp")
  expect_no_error(capture.output(print(ef)))
})

# summary.Link (ED mode) -------------------------------------------------

test_that("summary.Link (ed mode) returns EDSummary with expected columns", {
  sm <- summary(ed, alpha = 1)
  expect_s3_class(sm, "EDSummary")
  for (nm in c("ata_from", "ata_to", "mean", "median", "wt", "g")) {
    expect_true(nm %in% names(sm), info = paste("missing", nm))
  }
})

# regime_break -----------------------------------------------------------

test_that("fit_ed with regime_break drops pre-break cohorts", {
  data(experience)
  exp <- as_experience(experience[cv_nm == "SUR"])
  tri <- build_triangle(exp, group_var = "cv_nm",
                        cohort_var = "uym", dev_var = "elap_m")
  ed <- build_link(tri, value_var = "closs", exposure_var = "crp")
  fit_full <- fit_ed(tri, value_var = "closs", exposure_var = "crp")
  fit_brk  <- fit_ed(tri, value_var = "closs", exposure_var = "crp", regime_break = "2024-04-01")
  expect_false(identical(fit_full$selected$g_selected,
                         fit_brk$selected$g_selected))
  expect_equal(fit_brk$regime_break, as.Date("2024-04-01"))
})

test_that("fit_ed with NULL regime_break is unchanged", {
  data(experience)
  exp <- as_experience(experience[cv_nm == "SUR"])
  tri <- build_triangle(exp, group_var = "cv_nm",
                        cohort_var = "uym", dev_var = "elap_m")
  ed <- build_link(tri, value_var = "closs", exposure_var = "crp")
  fit_default <- fit_ed(tri, value_var = "closs", exposure_var = "crp")
  fit_null    <- fit_ed(tri, value_var = "closs", exposure_var = "crp", regime_break = NULL)
  expect_identical(fit_default$selected$g_selected,
                   fit_null$selected$g_selected)
})

test_that("fit_ed with Regime input extracts last breakpoint", {
  data(experience)
  exp <- as_experience(experience[cv_nm == "SUR"])
  tri <- build_triangle(exp, group_var = "cv_nm",
                        cohort_var = "uym", dev_var = "elap_m")
  reg <- detect_regime(tri)
  ed <- build_link(tri, value_var = "closs", exposure_var = "crp")
  fit_reg <- fit_ed(tri, value_var = "closs", exposure_var = "crp", regime_break = reg)
  if (length(reg$breakpoints) > 0L) {
    expect_equal(fit_reg$regime_break, max(reg$breakpoints))
  }
})

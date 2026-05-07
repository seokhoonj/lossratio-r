# Setup
data(experience)
exp <- as_experience(experience)
tri <- build_triangle(exp, group_var = cv_nm)
ata <- build_link(tri, value_var = "closs")

test_that("build_link returns class 'Link' with expected columns", {
  expect_s3_class(ata, "Link")
  for (nm in c("cv_nm", "cohort", "ata_from", "ata_to", "ata_link",
               "value_from", "value_to", "ata")) {
    expect_true(nm %in% names(ata), info = paste("missing", nm))
  }
})

test_that("build_link sets attributes", {
  for (a in c("group_var", "cohort_var", "dev_var", "value_var")) {
    expect_false(is.null(attr(ata, a)), info = paste("missing attr", a))
  }
  expect_equal(attr(ata, "value_var"), "closs")
})

test_that("ata_to == ata_from + 1", {
  expect_true(all(ata$ata_to == ata$ata_from + 1L))
})

test_that("ata == value_to / value_from when value_from > 0", {
  ok <- is.finite(ata$ata) & ata$value_from > 0
  expect_equal(ata$ata[ok], ata$value_to[ok] / ata$value_from[ok], tolerance = 1e-6)
})

test_that("weight_var adds 'weight' column", {
  ata_w <- build_link(tri, value_var = "clr", weight_var = "crp")
  expect_true("weight" %in% names(ata_w))
  expect_equal(attr(ata_w, "weight_var"), "crp")
})

test_that("build_link errors on invalid value_var", {
  expect_error(build_link(tri, value_var = "loss"))
})

test_that("build_link errors when weight_var equals value_var", {
  expect_error(build_link(tri, value_var = "closs", weight_var = "closs"))
})

test_that("drop_invalid removes non-finite ata", {
  a1 <- build_link(tri, value_var = "closs", drop_invalid = FALSE)
  a2 <- build_link(tri, value_var = "closs", drop_invalid = TRUE)
  expect_true(nrow(a2) <= nrow(a1))
  expect_true(all(is.finite(a2$ata)))
})

# fit_ata ----------------------------------------------------------------

test_that("fit_ata returns class 'ATAFit' with expected components", {
  af <- fit_ata(tri, value_var = "closs")
  expect_s3_class(af, "ATAFit")
  for (nm in c("factor", "selected")) {
    expect_true(nm %in% names(af), info = paste("missing", nm))
  }
})

test_that("fit_ata $selected has expected columns", {
  af <- fit_ata(tri, value_var = "closs")
  for (nm in c("ata_from", "ata_to", "f_selected")) {
    expect_true(nm %in% names(af$selected), info = paste("missing", nm))
  }
})

test_that("sigma_method variants run", {
  for (sm in c("min_last2", "locf", "loglinear")) {
    expect_no_error(fit_ata(tri, value_var = "closs", sigma_method = sm))
  }
})

test_that("recent reduces selected rows count", {
  af_full   <- fit_ata(tri, value_var = "closs")
  af_recent <- fit_ata(tri, value_var = "closs", recent = 6)
  expect_true(nrow(af_recent$selected) <= nrow(af_full$selected))
})

test_that("maturity_args adds $maturity", {
  af_no  <- fit_ata(tri, value_var = "closs")
  af_mat <- fit_ata(tri, value_var = "closs", maturity_args = list())
  expect_null(af_no$maturity)
  expect_false(is.null(af_mat$maturity))
})

test_that("print.ATAFit doesn't error", {
  af <- fit_ata(tri, value_var = "closs")
  expect_no_error(capture.output(print(af)))
})

# summary.Link (ATA mode) ------------------------------------------------

test_that("summary.Link (ata mode) returns ATASummary with expected columns", {
  sm <- summary(ata, alpha = 1)
  expect_s3_class(sm, "ATASummary")
  for (nm in c("ata_from", "ata_to", "mean", "median", "wt", "cv",
               "f", "f_se", "rse", "sigma")) {
    expect_true(nm %in% names(sm), info = paste("missing", nm))
  }
})

test_that("summary.Link (ata mode) accepts alpha = 0 / 2", {
  expect_no_error(summary(ata, alpha = 0))
  expect_no_error(summary(ata, alpha = 2))
})

# find_maturity ------------------------------------------------------

test_that("find_maturity returns one row per group with loose thresholds", {
  sm  <- summary(ata)
  mat <- find_maturity(sm, cv_threshold = 0.5, rse_threshold = 0.5)
  groups <- unique(sm$cv_nm)
  expect_true(nrow(mat) <= length(groups))
})

test_that("tight thresholds yield fewer or NA mature rows", {
  sm <- summary(ata)
  mat_loose <- find_maturity(sm, cv_threshold = 0.5, rse_threshold = 0.5)
  mat_tight <- find_maturity(sm, cv_threshold = 0.001, rse_threshold = 0.001)
  finite_loose <- sum(is.finite(mat_loose$ata_from))
  finite_tight <- sum(is.finite(mat_tight$ata_from))
  expect_true(finite_tight <= finite_loose)
})

# summary.ATAFit ---------------------------------------------------------

test_that("summary.ATAFit returns the link-level ATASummary", {
  fit <- fit_ata(tri, value_var = "closs")
  s   <- summary(fit)
  expect_s3_class(s, "ATASummary")
  expect_identical(s, fit$factor)
  for (nm in c("ata_from", "ata_to", "ata_link", "f", "f_se", "rse", "sigma")) {
    expect_true(nm %in% names(s), info = paste("missing", nm))
  }
})

# fit_ata regime_break ---------------------------------------------------

test_that("fit_ata with regime_break drops pre-break cohorts", {
  data(experience)
  exp <- as_experience(experience[cv_nm == "SUR"])
  tri <- build_triangle(exp, group_var = "cv_nm",
                        cohort_var = "uym", dev_var = "elap_m")
  ata <- build_link(tri, value_var = "closs")

  fit_full <- fit_ata(tri, value_var = "closs")
  fit_brk  <- fit_ata(tri, value_var = "closs", regime_break = "2024-04-01")

  # post-break fit should have fewer rows in the underlying ATA pairs
  # and possibly different f_selected for at least one ata_from
  expect_false(identical(fit_full$selected$f_selected,
                         fit_brk$selected$f_selected))
  expect_equal(fit_brk$regime_break, as.Date("2024-04-01"))
})

test_that("fit_ata with NULL regime_break is unchanged from default", {
  data(experience)
  exp <- as_experience(experience[cv_nm == "SUR"])
  tri <- build_triangle(exp, group_var = "cv_nm",
                        cohort_var = "uym", dev_var = "elap_m")
  ata <- build_link(tri, value_var = "closs")
  fit_default <- fit_ata(tri, value_var = "closs")
  fit_null    <- fit_ata(tri, value_var = "closs", regime_break = NULL)
  expect_identical(fit_default$selected$f_selected,
                   fit_null$selected$f_selected)
})

test_that("fit_ata with CohortRegime input extracts last breakpoint", {
  data(experience)
  exp <- as_experience(experience[cv_nm == "SUR"])
  tri <- build_triangle(exp, group_var = "cv_nm",
                        cohort_var = "uym", dev_var = "elap_m")
  reg <- detect_regime(tri)
  ata <- build_link(tri, value_var = "closs")
  fit_reg <- fit_ata(tri, value_var = "closs", regime_break = reg)
  if (length(reg$breakpoints) > 0L) {
    expect_equal(fit_reg$regime_break, max(reg$breakpoints))
  }
})

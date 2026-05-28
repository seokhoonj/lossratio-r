# Setup
data(experience)
exp <- experience
tri <- as_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_premium")
ata <- as_link(tri, loss = "loss")

test_that("as_link returns class 'Link' with expected columns", {
  expect_s3_class(ata, "Link")
  for (nm in c("coverage", "cohort", "ata_from", "ata_to", "ata_link",
               "loss_from", "loss_to", "ata")) {
    expect_true(nm %in% names(ata), info = paste("missing", nm))
  }
})

test_that("as_link sets attributes", {
  for (a in c("groups", "cohort", "dev", "loss")) {
    expect_false(is.null(attr(ata, a)), info = paste("missing attr", a))
  }
  expect_equal(attr(ata, "loss"), "loss")
})

test_that("ata_to == ata_from + 1", {
  expect_true(all(ata$ata_to == ata$ata_from + 1L))
})

test_that("ata == loss_to / loss_from when loss_from > 0", {
  ok <- is.finite(ata$ata) & ata$loss_from > 0
  expect_equal(ata$ata[ok], ata$loss_to[ok] / ata$loss_from[ok], tolerance = 1e-6)
})

test_that("weight adds 'weight' column", {
  ata_w <- as_link(tri, loss = "ratio", weight = "premium")
  expect_true("weight" %in% names(ata_w))
  expect_equal(attr(ata_w, "weight"), "premium")
})

test_that("as_link errors on invalid loss", {
  expect_error(as_link(tri, loss = "nonexistent"))
})

test_that("as_link errors when weight equals loss", {
  expect_error(as_link(tri, loss = "loss", weight = "loss"))
})

test_that("drop_invalid removes non-finite ata", {
  a1 <- as_link(tri, loss = "loss", drop_invalid = FALSE)
  a2 <- as_link(tri, loss = "loss", drop_invalid = TRUE)
  expect_true(nrow(a2) <= nrow(a1))
  expect_true(all(is.finite(a2$ata)))
})

# fit_ata ----------------------------------------------------------------

test_that("fit_ata returns class 'ATAFit' with expected components", {
  af <- fit_ata(tri, loss = "loss")
  expect_s3_class(af, "ATAFit")
  for (nm in c("factor", "selected")) {
    expect_true(nm %in% names(af), info = paste("missing", nm))
  }
})

test_that("fit_ata $selected has expected columns", {
  af <- fit_ata(tri, loss = "loss")
  for (nm in c("ata_from", "ata_to", "f_sel")) {
    expect_true(nm %in% names(af$selected), info = paste("missing", nm))
  }
})

test_that("sigma_method variants run", {
  for (sm in c("min_last2", "locf", "loglinear", "mack", "none")) {
    expect_no_error(suppressWarnings(
      fit_ata(tri, loss = "loss", sigma_method = sm)))
  }
})

test_that("sigma_method = 'mack' fills only the last unestimated link", {
  # synthetic ATAFit-style selected table with a few unestimated tail rows
  sel <- data.table::data.table(
    ata_from = 1:6,
    sigma    = c(2.0, 1.8, 1.6, 1.4, NA_real_, NA_real_))
  out <- suppressWarnings(
    lossratio:::.extrapolate_sigma_ata(sel, method = "mack"))
  expect_true(all(is.finite(out$sigma)))
  # earlier unestimated row = LOCF (last valid = 1.4)
  expect_equal(out$sigma[5], 1.4)
  # last unestimated row = Mack tail estimator
  s2_last <- 1.4^2; s2_prev <- 1.6^2
  expect_equal(out$sigma[6]^2, min(s2_last^2 / s2_prev, s2_last, s2_prev))
})

test_that("sigma_method = 'mack' warns when multiple links are unestimated", {
  sel <- data.table::data.table(
    ata_from = 1:6,
    sigma    = c(2.0, 1.8, 1.6, 1.4, NA_real_, NA_real_))
  expect_warning(
    lossratio:::.extrapolate_sigma_ata(sel, method = "mack"),
    regexp = "Mack tail estimator covers only the last link")
})

test_that("sigma_method = 'mack' falls back to LOCF when < 3 valid sigmas", {
  sel <- data.table::data.table(
    ata_from = 1:4, sigma = c(2.0, 1.8, NA_real_, NA_real_))
  expect_warning(
    out <- lossratio:::.extrapolate_sigma_ata(sel, method = "mack"),
    regexp = "requires >= 3 valid sigma values")
  expect_equal(out$sigma[3:4], c(1.8, 1.8))
})

test_that("sigma_method = 'none' leaves NA sigma in place", {
  sel <- data.table::data.table(
    ata_from = 1:5,
    sigma    = c(2.0, 1.8, 1.6, NA_real_, NA_real_))
  out <- lossratio:::.extrapolate_sigma_ata(sel, method = "none")
  expect_true(all(is.na(out$sigma[4:5])))
  expect_true(all(out$sigma_extrapolated[4:5]))
})

test_that("recent reduces selected rows count", {
  af_full   <- fit_ata(tri, loss = "loss")
  af_recent <- fit_ata(tri, loss = "loss", recent = 6)
  expect_true(nrow(af_recent$selected) <= nrow(af_full$selected))
})

test_that("maturity = \"auto\" adds $maturity", {
  af_no  <- fit_ata(tri, loss = "loss")
  af_mat <- fit_ata(tri, loss = "loss", maturity = "auto")
  expect_null(af_no$maturity)
  expect_false(is.null(af_mat$maturity))
})

test_that("print.ATAFit doesn't error", {
  af <- fit_ata(tri, loss = "loss")
  expect_no_error(capture.output(print(af)))
})

# summary.Link (ATA mode) ------------------------------------------------

test_that("summary.Link (ata mode) returns ATASummary with expected columns", {
  smr <- summary(ata, alpha = 1)
  expect_s3_class(smr, "ATASummary")
  for (nm in c("ata_from", "ata_to", "mean", "median", "wt", "cv",
               "f", "f_se", "rse", "sigma")) {
    expect_true(nm %in% names(smr), info = paste("missing", nm))
  }
})

test_that("summary.Link (ata mode) accepts alpha = 0 / 2", {
  expect_no_error(summary(ata, alpha = 0))
  expect_no_error(summary(ata, alpha = 2))
})

# detect_maturity ------------------------------------------------------

test_that("detect_maturity returns one row per group with loose thresholds", {
  smr <- summary(ata)
  mat <- detect_maturity(tri, max_cv = 0.5, max_rse = 0.5)
  groups <- unique(smr$coverage)
  expect_true(nrow(mat) <= length(groups))
})

test_that("tight thresholds yield fewer or NA mature rows", {
  smr <- summary(ata)
  mat_loose <- detect_maturity(tri, max_cv = 0.5, max_rse = 0.5)
  mat_tight <- detect_maturity(tri, max_cv = 0.001, max_rse = 0.001)
  finite_loose <- sum(is.finite(mat_loose$ata_from))
  finite_tight <- sum(is.finite(mat_tight$ata_from))
  expect_true(finite_tight <= finite_loose)
})

# summary.ATAFit ---------------------------------------------------------

test_that("summary.ATAFit returns the link-level ATASummary", {
  fit <- fit_ata(tri, loss = "loss")
  s   <- summary(fit)
  expect_s3_class(s, "ATASummary")
  expect_identical(s, fit$factor)
  for (nm in c("ata_from", "ata_to", "ata_link", "f", "f_se", "rse", "sigma")) {
    expect_true(nm %in% names(s), info = paste("missing", nm))
  }
})

# fit_ata regime ---------------------------------------------------------

test_that("fit_ata with regime drops pre-break cohorts", {
  data(experience)
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_premium")
  ata <- as_link(tri, loss = "loss")

  fit_full <- fit_ata(tri, loss = "loss")
  fit_brk  <- fit_ata(tri, loss = "loss",
                      regime = regime_at(change = "2024-07-01"))

  # post-change fit should have fewer rows in the underlying ATA pairs
  # and possibly different f_sel for at least one ata_from
  expect_false(identical(fit_full$selected$f_sel,
                         fit_brk$selected$f_sel))
  expect_s3_class(fit_brk$regime, "Regime")
})

test_that("fit_ata with NULL regime is unchanged from default", {
  data(experience)
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_premium")
  ata <- as_link(tri, loss = "loss")
  fit_default <- fit_ata(tri, loss = "loss")
  fit_null    <- fit_ata(tri, loss = "loss", regime = NULL)
  expect_identical(fit_default$selected$f_sel,
                   fit_null$selected$f_sel)
})

test_that("fit_ata with Regime input preserves the Regime object", {
  data(experience)
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_premium")
  reg <- detect_regime(tri)
  ata <- as_link(tri, loss = "loss")
  fit_reg <- fit_ata(tri, loss = "loss", regime = reg)
  expect_s3_class(fit_reg$regime, "Regime")
  expect_identical(fit_reg$regime$changes, reg$changes)
})

test_that("fit_ata segment treatments: borrowed keeps segment_id, bridged pools", {
  data(experience)
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m",
                        loss = "incr_loss", premium = "incr_premium")
  reg_bor <- regime_at(change = "2024-04-01",
                       treatment = "segment_bridged_borrowed")
  reg_brd <- regime_at(change = "2024-04-01",
                       treatment = "segment_bridged")

  fit_bor <- fit_ata(tri, loss = "loss", regime = reg_bor)
  fit_brd <- fit_ata(tri, loss = "loss", regime = reg_brd)

  # segment_bridged_borrowed estimates factors per segment (segment_id
  # present); segment_bridged pools the band (segment_id absent).
  expect_true("segment_id" %in% names(fit_bor$selected))
  expect_false("segment_id" %in% names(fit_brd$selected))

  # Two segments expected under the per-segment (borrowed) treatment.
  expect_equal(sort(unique(fit_bor$selected$segment_id)), c(1L, 2L))
})

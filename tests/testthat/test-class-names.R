# PascalCase class-name regression and lowercase-class negative assertions.
#
# CLAUDE.md mandates Style A PascalCase for every S3 class (acronyms in
# full caps: `ATA`, `ED`, `CLFit`, `LRFit`, ...). The legacy lowercase
# names (`triangle`, `ata`, `cl_fit`, ...) were swept out and must never
# be reintroduced. These tests lock in both directions.

# Positive: PascalCase classes ----------------------------------------------

test_that("Triangle / Calendar / Total carry PascalCase classes", {
  fits <- make_fit_set()
  expect_s3_class(fits$tri, "Triangle")
  expect_s3_class(fits$cal, "Calendar")
  expect_s3_class(fits$tot, "Total")
})

test_that("ATA family carries PascalCase classes", {
  fits <- make_fit_set()
  expect_s3_class(fits$ata,     "Link")
  expect_s3_class(fits$ata_fit, "ATAFit")
  expect_s3_class(fits$ata_sm,  "ATASummary")

  mat <- detect_maturity(fits$tri, max_cv = 0.5, max_rse = 0.5)
  expect_s3_class(mat, "Maturity")
})

test_that("ED family carries PascalCase classes", {
  fits <- make_fit_set()
  expect_s3_class(fits$ed,     "Link")
  expect_s3_class(fits$ed_fit, "EDFit")
  expect_s3_class(fits$ed_sm,  "EDSummary")
})

test_that("CLFit / LRFit carry PascalCase classes", {
  fits <- make_fit_set()
  expect_s3_class(fits$cl, "CLFit")
  expect_s3_class(fits$lr, "LRFit")
})

test_that("Regime and Backtest carry PascalCase classes", {
  sub <- make_sub_tri("SUR")
  reg <- detect_regime(sub, K = 12, method = "e_divisive")
  expect_s3_class(reg, "Regime")
  expect_s3_class(summary(reg), "summary.Regime")

  bt <- backtest(sub, holdout = 6L, target = "loss", loss_method = "cl")
  expect_s3_class(bt, "Backtest")
  expect_s3_class(summary(bt), "summary.Backtest")
})

test_that("TriangleSummary / TriangleLonger / TriangleSummaryLonger classes set", {
  tri <- make_tri()
  smr  <- summary(tri)
  expect_s3_class(smr, "TriangleSummary")

  lng <- attr(tri, "longer")
  expect_s3_class(lng, "TriangleLonger")

  sm_lng <- attr(smr, "longer")
  expect_s3_class(sm_lng, "TriangleSummaryLonger")
})

test_that("CalendarLonger and validation classes set", {
  exp <- make_exp()
  cal <- build_calendar(exp, groups = coverage, calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  expect_s3_class(attr(cal, "longer"), "CalendarLonger")

  val_tri <- validate_triangle(exp, groups = coverage, cohort = "uy_m", dev = "dev_m")
  expect_s3_class(val_tri, "TriangleValidation")
})

# Negative: lowercase names not reintroduced --------------------------------

test_that("lowercase class names not introduced (Triangle family)", {
  fits <- make_fit_set()
  for (nm in c("triangle", "calendar", "total", "experience",
               "triangle_summary", "triangle_longer",
               "calendar_longer", "triangle_summary_longer",
               "triangle_validation", "calendar_validation")) {
    expect_false(inherits(fits$tri, nm), info = paste("tri inherits", nm))
    expect_false(inherits(fits$cal, nm), info = paste("cal inherits", nm))
    expect_false(inherits(fits$exp, nm), info = paste("exp inherits", nm))
  }
})

test_that("lowercase class names not introduced (ATA / ED family)", {
  fits <- make_fit_set()
  for (nm in c("ata", "ata_fit", "ata_summary", "ata_maturity",
               "ed", "ed_fit", "ed_summary")) {
    expect_false(inherits(fits$ata,     nm), info = paste("ata inherits", nm))
    expect_false(inherits(fits$ata_fit, nm), info = paste("ata_fit inherits", nm))
    expect_false(inherits(fits$ed,      nm), info = paste("ed inherits", nm))
    expect_false(inherits(fits$ed_fit,  nm), info = paste("ed_fit inherits", nm))
  }
})

test_that("lowercase class names not introduced (CL / LR / regime / backtest)", {
  fits <- make_fit_set()
  sub  <- make_sub_tri("SUR")
  reg  <- detect_regime(sub, K = 12, method = "e_divisive")
  bt   <- backtest(sub, holdout = 6L, target = "loss", loss_method = "cl")

  for (nm in c("cl_fit", "lr_fit", "cohort_regime", "backtest")) {
    expect_false(inherits(fits$cl, nm), info = paste("cl inherits", nm))
    expect_false(inherits(fits$lr, nm), info = paste("lr inherits", nm))
    expect_false(inherits(reg, nm), info = paste("reg inherits", nm))
    expect_false(inherits(bt,  nm), info = paste("bt inherits",  nm))
  }
})

# Attributes regression -----------------------------------------------------

test_that("Triangle attribute names preserved (raw / standard split)", {
  tri <- make_tri()
  expect_identical(attr(tri, "dev"),     "dev_m")
  expect_identical(attr(tri, "cohort"),  "uy_m")
  expect_identical(attr(tri, "groups"),   "coverage")

  # standard column names rename happened (raw cohort/dev replaced).
  expect_true("cohort" %in% names(tri))
  expect_true("dev"    %in% names(tri))
  expect_false("uy_m"  %in% names(tri))
  expect_false("dev_m" %in% names(tri))
})

test_that("Calendar attributes use calendar", {
  cal <- build_calendar(make_exp(), groups = coverage, calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  expect_identical(attr(cal, "calendar"), "cy_m")
  expect_identical(attr(cal, "groups"),    "coverage")
})

test_that("Forbidden legacy attribute names not present", {
  tri <- make_tri()
  cal <- build_calendar(make_exp(), groups = coverage, calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  for (a in c("period_var", "duration_var", "duration_type",
              "elapsed_var", "elp_var", "elp_type", "dur_var", "dur_type")) {
    expect_null(attr(tri, a, exact = TRUE), info = paste("tri attr", a))
    expect_null(attr(cal, a, exact = TRUE), info = paste("cal attr", a))
  }
})

test_that("Triangle column names use standard cohort/dev (no legacy aliases)", {
  tri <- make_tri()
  for (nm in c("duration", "elapsed", "uy_m", "dev_m",
               "elpm", "elpq", "elph", "elpy")) {
    expect_false(nm %in% names(tri), info = paste("tri has column", nm))
  }
})

data(experience, package = "lossratio")
exp <- experience

test_that("build_triangle returns object inheriting class 'Triangle'", {
  tri <- build_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  expect_s3_class(tri, "Triangle")
})

test_that("build_triangle output has expected columns", {
  tri <- build_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  expected <- c("cohort", "dev",
                "loss", "loss_incr", "premium", "premium_incr",
                "lr", "lr_incr")
  expect_true(all(expected %in% names(tri)))
})

test_that("build_triangle sets attributes correctly", {
  tri <- build_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  expect_equal(attr(tri, "cohort"),  "uy_m")
  expect_equal(attr(tri, "dev"),     "dev_m")
  expect_equal(attr(tri, "groups"),   "coverage")
})

test_that("loss equals cumulative sum of loss_incr within (group, cohort)", {
  tri <- build_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  data.table::setorder(tri, coverage, cohort, dev)
  chk <- tri[, .(max_abs_err = max(abs(loss - cumsum(loss_incr)))),
             by = .(coverage, cohort)]
  tol <- 1e-6
  expect_true(all(chk$max_abs_err <= tol))
})

test_that("lr equals loss/premium within each row when premium > 0", {
  tri <- build_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  pos <- tri[premium > 0]
  expect_equal(pos$lr, pos$loss / pos$premium)
})

test_that("summary.Triangle returns a TriangleSummary with expected columns", {
  tri <- build_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  smr <- summary(tri)
  expect_s3_class(smr, "TriangleSummary")
  expected <- c("lr_mean", "lr_median", "lr_wt",
                "lr_incr_mean", "lr_incr_median", "lr_incr_wt")
  expect_true(all(expected %in% names(smr)))
})

test_that("longer.Triangle returns TriangleLonger with variable/value", {
  tri <- build_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  lng <- longer(tri)
  expect_s3_class(lng, "TriangleLonger")
  expect_true(all(c("variable", "value") %in% names(lng)))
})

test_that("build_calendar returns class 'Calendar' with expected columns", {
  cal <- build_calendar(exp, groups = "coverage", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  expect_s3_class(cal, "Calendar")
  expect_true(all(c("calendar", "dev") %in% names(cal)))
  expect_equal(attr(cal, "calendar"), "cy_m")
})

test_that("build_total returns class 'Total' with one row per group", {
  tot <- build_total(exp, groups = "coverage", cohort = "uy_m", dev = "dev_m", loss = "loss_incr", premium = "premium_incr")
  expect_s3_class(tot, "Total")
  expected <- c("n_obs", "sales_start", "sales_end",
                "loss", "premium", "lr", "loss_share", "premium_share")
  expect_true(all(expected %in% names(tot)))
  expect_equal(nrow(tot), data.table::uniqueN(exp$coverage))
})

test_that("validate_triangle returns class 'TriangleValidation' with no gaps", {
  res <- validate_triangle(experience, groups = "coverage", cohort = "uy_m", dev = "dev_m")
  expect_s3_class(res, "TriangleValidation")
  expect_equal(nrow(res), 0L)
})

test_that("build_triangle errors when group is invalid", {
  expect_error(build_triangle(exp, groups = nonexistent_col, cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr"),
               regexp = "Unknown column")
})

test_that("summary.Calendar returns CalendarSummary with expected columns", {
  cal <- build_calendar(exp, groups = "coverage", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  s   <- summary(cal)
  expect_s3_class(s, "CalendarSummary")
  expected <- c("calendar", "n_obs",
                "lr_mean", "lr_median", "lr_wt",
                "lr_incr_mean", "lr_incr_median", "lr_incr_wt")
  expect_true(all(expected %in% names(s)))
  expect_equal(attr(s, "groups"),    "coverage")
  expect_equal(attr(s, "calendar"), "cy_m")
  expect_false(inherits(s, "Calendar"))
})

test_that("summary.Calendar row count matches (group, calendar) cells", {
  cal <- build_calendar(exp, groups = "coverage", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  s   <- summary(cal)
  expect_equal(nrow(s), nrow(unique(cal[, .(coverage, calendar)])))
})

test_that("summary.Total returns TotalSummary ordered by descending lr", {
  tot <- build_total(exp, groups = "coverage", cohort = "uy_m", dev = "dev_m", loss = "loss_incr", premium = "premium_incr")
  s   <- summary(tot)
  expect_s3_class(s, "TotalSummary")
  expect_false(inherits(s, "Total"))
  expect_equal(nrow(s), nrow(tot))
  expect_true(all(diff(s$lr) <= 0))
  expect_equal(attr(s, "groups"), "coverage")
})

test_that("summary.Total honors digits = NULL (no rounding)", {
  tot <- build_total(exp, groups = "coverage", cohort = "uy_m", dev = "dev_m", loss = "loss_incr", premium = "premium_incr")
  s_round <- summary(tot, digits = 2L)
  s_raw   <- summary(tot, digits = NULL)
  expect_true(all(s_round$lr == round(s_round$lr, 2L)))
  expect_true(any(s_raw$lr != round(s_raw$lr, 2L)) ||
              all(s_raw$lr == round(s_raw$lr, 6L)))
})

test_that("plot.Total returns a ggplot for default metric = 'lr'", {
  tot <- build_total(exp, groups = "coverage", cohort = "uy_m", dev = "dev_m", loss = "loss_incr", premium = "premium_incr")
  expect_no_error(p <- plot(tot))
  expect_s3_class(p, "ggplot")
})

test_that("plot.Total errors on unknown metric", {
  tot <- build_total(exp, groups = "coverage", cohort = "uy_m", dev = "dev_m", loss = "loss_incr", premium = "premium_incr")
  expect_error(plot(tot, metric = "nope"))
})

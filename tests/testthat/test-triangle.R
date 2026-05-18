data(experience, package = "lossratio")
exp <- experience

test_that("as_triangle returns object inheriting class 'Triangle'", {
  tri <- as_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")
  expect_s3_class(tri, "Triangle")
})

test_that("as_triangle output has expected columns", {
  tri <- as_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")
  expected <- c("cohort", "dev",
                "loss", "incr_loss", "exposure", "incr_exposure",
                "ratio", "incr_ratio")
  expect_true(all(expected %in% names(tri)))
})

test_that("as_triangle sets attributes correctly", {
  tri <- as_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")
  expect_equal(attr(tri, "cohort"),  "uy_m")
  expect_equal(attr(tri, "dev"),     "dev_m")
  expect_equal(attr(tri, "groups"),   "coverage")
})

test_that("loss equals cumulative sum of incr_loss within (group, cohort)", {
  tri <- as_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")
  data.table::setorder(tri, coverage, cohort, dev)
  chk <- tri[, .(max_abs_err = max(abs(loss - cumsum(incr_loss)))),
             by = .(coverage, cohort)]
  tol <- 1e-6
  expect_true(all(chk$max_abs_err <= tol))
})

test_that("ratio equals loss/exposure within each row when exposure > 0", {
  tri <- as_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")
  pos <- tri[exposure > 0]
  expect_equal(pos$ratio, pos$loss / pos$exposure)
})

test_that("summary.Triangle returns a TriangleSummary with expected columns", {
  tri <- as_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")
  smr <- summary(tri)
  expect_s3_class(smr, "TriangleSummary")
  expected <- c("ratio_mean", "ratio_median", "ratio_wt",
                "incr_ratio_mean", "incr_ratio_median", "incr_ratio_wt")
  expect_true(all(expected %in% names(smr)))
})

test_that("longer.Triangle returns TriangleLonger with variable/value", {
  tri <- as_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")
  lng <- longer(tri)
  expect_s3_class(lng, "TriangleLonger")
  expect_true(all(c("variable", "value") %in% names(lng)))
})

test_that("as_calendar(Triangle) returns class 'Calendar' with expected columns", {
  tri <- as_triangle(exp, groups = "coverage", cohort = "uy_m",
                     calendar = "cy_m", loss = "incr_loss",
                     exposure = "incr_exposure")
  cal <- as_calendar(tri)
  expect_s3_class(cal, "Calendar")
  expect_true(all(c("calendar", "cal_idx") %in% names(cal)))
  expect_equal(attr(cal, "calendar"), "cy_m")
})

test_that("as_total(Triangle) returns class 'Total' with one row per group", {
  tri <- as_triangle(exp, groups = "coverage", cohort = "uy_m",
                     dev = "dev_m", loss = "incr_loss",
                     exposure = "incr_exposure")
  tot <- as_total(tri)
  expect_s3_class(tot, "Total")
  expected <- c("n_cohorts", "sales_start", "sales_end",
                "loss", "exposure", "ratio", "loss_share", "exposure_share")
  expect_true(all(expected %in% names(tot)))
  expect_equal(nrow(tot), data.table::uniqueN(exp$coverage))
})

test_that("validate_triangle returns class 'TriangleValidation' with no gaps", {
  res <- validate_triangle(experience, groups = "coverage", cohort = "uy_m", dev = "dev_m")
  expect_s3_class(res, "TriangleValidation")
  expect_equal(nrow(res), 0L)
})

test_that("plot.TriangleValidation handles empty and non-empty cases", {
  # Empty: message + invisible(NULL); no error.
  res_empty <- validate_triangle(experience, groups = "coverage",
                                 cohort = "uy_m", dev = "dev_m")
  expect_null(suppressMessages(plot(res_empty)))

  # Non-empty: induce gaps by dropping all dev=3 rows for one coverage.
  exp_drop  <- experience[!(coverage == "surgery" & dev_m == 3)]
  res_gaps  <- validate_triangle(exp_drop, groups = "coverage",
                                 cohort = "uy_m", dev = "dev_m")
  expect_gt(nrow(res_gaps), 0L)
  p <- plot(res_gaps)
  expect_s3_class(p, "ggplot")

  # plot_triangle (heatmap view) requires calendar column.
  res_cal <- validate_triangle(exp_drop, groups = "coverage",
                              cohort = "uy_m", calendar = "cy_m")
  ph_cal <- plot_triangle(res_cal)
  expect_s3_class(ph_cal, "ggplot")
  ph_dev <- plot_triangle(res_cal, view = "dev")
  expect_s3_class(ph_dev, "ggplot")

  # No calendar => plot_triangle returns NULL + message
  expect_null(suppressMessages(plot_triangle(res_gaps)))

  # Empty validation → message + invisible(NULL)
  expect_null(suppressMessages(plot_triangle(res_empty)))
})

test_that("TriangleValidation carries dev_min / dev_max columns", {
  exp_drop <- experience[!(coverage == "surgery" & dev_m == 3)]
  res <- validate_triangle(exp_drop, groups = "coverage",
                          cohort = "uy_m", dev = "dev_m")
  expect_true(all(c("dev_min", "dev_max") %in% names(res)))
  expect_true(is.integer(res$dev_min))
  expect_true(is.integer(res$dev_max))
})

test_that("as_triangle errors when group is invalid", {
  expect_error(as_triangle(exp, groups = "nonexistent_col", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure"),
               regexp = "not found")
})

test_that("as_triangle Mode 2: cohort + dev only (no calendar)", {
  sur <- experience[coverage == "surgery"]
  tri <- as_triangle(sur, groups = "coverage",
                     cohort = "uy_m", dev = "dev_m",
                     loss = "incr_loss", exposure = "incr_exposure")
  expect_s3_class(tri, "Triangle")
  for (col in c("cohort", "dev", "loss", "exposure", "ratio"))
    expect_true(col %in% names(tri), info = paste("missing", col))
  # calendar attribute null when not supplied
  expect_null(attr(tri, "calendar"))
  # dev attribute retains the user-supplied raw column name
  expect_equal(attr(tri, "dev"), "dev_m")
})

test_that("as_triangle Mode 3: cohort + calendar + dev (cross-check ok)", {
  sur <- experience[coverage == "surgery"]
  tri <- as_triangle(sur, groups = "coverage",
                     cohort = "uy_m", calendar = "cy_m", dev = "dev_m",
                     loss = "incr_loss", exposure = "incr_exposure")
  expect_s3_class(tri, "Triangle")
  expect_equal(attr(tri, "calendar"), "cy_m")
  expect_equal(attr(tri, "dev"), "dev_m")
})

test_that("summary.Calendar returns CalendarSummary with expected columns", {
  cal <- as_calendar(as_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure"))
  s   <- summary(cal)
  expect_s3_class(s, "CalendarSummary")
  expected <- c("calendar", "n_cohorts",
                "ratio_mean", "ratio_median", "ratio_wt",
                "incr_ratio_mean", "incr_ratio_median", "incr_ratio_wt")
  expect_true(all(expected %in% names(s)))
  expect_equal(attr(s, "groups"),    "coverage")
  expect_equal(attr(s, "calendar"), "cy_m")
  expect_false(inherits(s, "Calendar"))
})

test_that("summary.Calendar row count matches (group, calendar) cells", {
  cal <- as_calendar(as_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure"))
  s   <- summary(cal)
  expect_equal(nrow(s), nrow(unique(cal[, .(coverage, calendar)])))
})

test_that("summary.Total returns TotalSummary ordered by descending ratio", {
  tot <- as_total(as_triangle(exp, groups = "coverage", cohort = "uy_m", dev = "dev_m", loss = "incr_loss", exposure = "incr_exposure"))
  s   <- summary(tot)
  expect_s3_class(s, "TotalSummary")
  expect_false(inherits(s, "Total"))
  expect_equal(nrow(s), nrow(tot))
  expect_true(all(diff(s$ratio) <= 0))
  expect_equal(attr(s, "groups"), "coverage")
})

test_that("summary.Total honors digits = NULL (no rounding)", {
  tot <- as_total(as_triangle(exp, groups = "coverage", cohort = "uy_m", dev = "dev_m", loss = "incr_loss", exposure = "incr_exposure"))
  s_round <- summary(tot, digits = 2L)
  s_raw   <- summary(tot, digits = NULL)
  expect_true(all(s_round$ratio == round(s_round$ratio, 2L)))
  expect_true(any(s_raw$ratio != round(s_raw$ratio, 2L)) ||
              all(s_raw$ratio == round(s_raw$ratio, 6L)))
})

test_that("plot.Total returns a ggplot for default metric = 'ratio'", {
  tot <- as_total(as_triangle(exp, groups = "coverage", cohort = "uy_m", dev = "dev_m", loss = "incr_loss", exposure = "incr_exposure"))
  expect_no_error(p <- plot(tot))
  expect_s3_class(p, "ggplot")
})

test_that("plot.Total errors on unknown metric", {
  tot <- as_total(as_triangle(exp, groups = "coverage", cohort = "uy_m", dev = "dev_m", loss = "incr_loss", exposure = "incr_exposure"))
  expect_error(plot(tot, metric = "nope"))
})

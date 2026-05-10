# Edge-case coverage: empty inputs, single cohort/group, NA loss,
# alternative granularities. The goal is to lock in current behaviour
# (whether that is silent zero-row pass-through or hard error).

# Empty input ---------------------------------------------------------------

test_that("as_experience accepts a zero-row data.frame and returns Experience", {
  data(experience)
  empty <- experience[0L, ]
  expect_no_error(out <- as_experience(empty))
  expect_s3_class(out, "Experience")
  expect_equal(nrow(out), 0L)
})

test_that("build_triangle accepts a zero-row Experience and returns empty Triangle", {
  exp_empty <- as_experience(make_exp()[0L, ])
  expect_no_error(tri <- build_triangle(exp_empty, group_var = coverage))
  expect_s3_class(tri, "Triangle")
  expect_equal(nrow(tri), 0L)
  expect_true(all(c("cohort", "dev", "loss", "premium") %in% names(tri)))
})

# Single cohort -------------------------------------------------------------

test_that("build_triangle on a single cohort succeeds", {
  exp <- make_exp()
  single <- exp[uy_m == as.Date("2024-01-01")]
  tri <- build_triangle(single, group_var = coverage)
  expect_s3_class(tri, "Triangle")
  expect_equal(data.table::uniqueN(tri$cohort), 1L)
  expect_gt(nrow(tri), 0L)
})

test_that("build_link on a single cohort returns Link with valid links", {
  exp <- make_exp()
  single <- exp[uy_m == as.Date("2024-01-01")]
  tri <- build_triangle(single, group_var = coverage)
  ata <- build_link(tri, loss_var = "loss")
  expect_s3_class(ata, "Link")
  expect_true(all(ata$ata_to == ata$ata_from + 1L))
})

# Single group --------------------------------------------------------------

test_that("build_triangle on a single group succeeds", {
  exp <- make_exp()
  one_grp <- exp[coverage == "SUR"]
  tri <- build_triangle(one_grp, group_var = coverage)
  expect_s3_class(tri, "Triangle")
  expect_equal(unique(tri$coverage), "SUR")
})

test_that("summary.Triangle on a single group returns one row per dev", {
  tri <- make_sub_tri("SUR")
  smr  <- summary(tri)
  expect_s3_class(smr, "TriangleSummary")
  expect_equal(nrow(smr), data.table::uniqueN(tri$dev))
})

test_that("fit_cl runs on a single-group triangle", {
  tri <- make_sub_tri("SUR")
  expect_no_error(cl <- fit_cl(tri, loss_var = "loss", method = "mack"))
  expect_s3_class(cl, "CLFit")
})

# NA loss propagation -------------------------------------------------------

test_that("build_triangle propagates NA loss without erroring", {
  exp <- make_exp()
  exp_na <- data.table::copy(exp)
  exp_na[1:50, loss_incr := NA_real_]
  expect_no_error(tri <- build_triangle(exp_na, group_var = coverage))
  expect_s3_class(tri, "Triangle")
  # at least some NAs survive aggregation
  expect_true(anyNA(tri$loss_incr))
})

test_that("as_experience refuses NA in required columns after coercion", {
  raw <- as.data.frame(make_exp())
  raw$loss_incr[1:5] <- NA
  expect_error(as_experience(raw),
               regexp = "loss_incr.*coerced.*numeric")
})

# Granularity (quarter / half / year) --------------------------------------

test_that("build_triangle with cohort_var = 'uy_q' / dev_var = 'dev_q' succeeds", {
  exp <- make_exp()
  skip_if_not("dev_q" %in% names(exp), "dev_q not present in experience")
  tri_q <- build_triangle(exp, group_var = coverage,
                          cohort_var = "uy_q", dev_var = "dev_q")
  expect_s3_class(tri_q, "Triangle")
  expect_identical(attr(tri_q, "cohort_var"), "uy_q")
  expect_identical(attr(tri_q, "dev_var"),    "dev_q")
  expect_gt(nrow(tri_q), 0L)
})

test_that("build_triangle with cohort_var = 'uy_s' / dev_var = 'dev_s' succeeds", {
  exp <- make_exp()
  skip_if_not("dev_s" %in% names(exp), "dev_s not present in experience")
  tri_s <- build_triangle(exp, group_var = coverage,
                          cohort_var = "uy_s", dev_var = "dev_s")
  expect_s3_class(tri_s, "Triangle")
  expect_identical(attr(tri_s, "cohort_var"), "uy_s")
  expect_identical(attr(tri_s, "dev_var"),    "dev_s")
  expect_gt(nrow(tri_s), 0L)
})

test_that("build_triangle with cohort_var = 'uy_a' / dev_var = 'dev_a' succeeds", {
  exp <- make_exp()
  skip_if_not("dev_a" %in% names(exp), "dev_a not present in experience")
  tri_a <- build_triangle(exp, group_var = coverage,
                          cohort_var = "uy_a", dev_var = "dev_a")
  expect_s3_class(tri_a, "Triangle")
  expect_identical(attr(tri_a, "cohort_var"), "uy_a")
  expect_identical(attr(tri_a, "dev_var"),    "dev_a")
  expect_gt(nrow(tri_a), 0L)
})

test_that("build_triangle errors on mismatched granularity (uy_m + dev_q)", {
  exp <- make_exp()
  skip_if_not("dev_q" %in% names(exp), "dev_q not present in experience")
  expect_error(
    build_triangle(exp, group_var = coverage,
                   cohort_var = "uy_m", dev_var = "dev_q"),
    regexp = "granularity"
  )
})

test_that("build_calendar with calendar_var = 'cy_q' returns Calendar quarter", {
  exp <- make_exp()
  skip_if_not("cy_q" %in% names(exp), "cy_q not present in experience")
  cal_q <- build_calendar(exp, group_var = coverage, calendar_var = "cy_q")
  expect_s3_class(cal_q, "Calendar")
  expect_identical(attr(cal_q, "calendar_var"), "cy_q")
  expect_gt(nrow(cal_q), 0L)
})

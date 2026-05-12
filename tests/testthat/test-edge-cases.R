# Edge-case coverage: empty inputs, single cohort/group, NA loss,
# alternative granularities. The goal is to lock in current behaviour
# (whether that is silent zero-row pass-through or hard error).

# Empty input ---------------------------------------------------------------

test_that("build_triangle accepts a zero-row data.frame and returns empty Triangle", {
  exp_empty <- make_exp()[0L, ]
  expect_no_error(tri <- build_triangle(exp_empty, groups = coverage, cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr"))
  expect_s3_class(tri, "Triangle")
  expect_equal(nrow(tri), 0L)
  expect_true(all(c("cohort", "dev", "loss", "premium") %in% names(tri)))
})

# Single cohort -------------------------------------------------------------

test_that("build_triangle on a single cohort succeeds", {
  exp <- make_exp()
  single <- exp[uy_m == as.Date("2024-01-01")]
  tri <- build_triangle(single, groups = coverage, cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  expect_s3_class(tri, "Triangle")
  expect_equal(data.table::uniqueN(tri$cohort), 1L)
  expect_gt(nrow(tri), 0L)
})

test_that("build_link on a single cohort returns Link with valid links", {
  exp <- make_exp()
  single <- exp[uy_m == as.Date("2024-01-01")]
  tri <- build_triangle(single, groups = coverage, cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  ata <- build_link(tri, target = "loss")
  expect_s3_class(ata, "Link")
  expect_true(all(ata$ata_to == ata$ata_from + 1L))
})

# Single group --------------------------------------------------------------

test_that("build_triangle on a single group succeeds", {
  exp <- make_exp()
  one_grp <- exp[coverage == "SUR"]
  tri <- build_triangle(one_grp, groups = coverage, cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
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
  expect_no_error(cl <- fit_cl(tri, target = "loss", method = "mack"))
  expect_s3_class(cl, "CLFit")
})

# NA loss propagation -------------------------------------------------------

test_that("build_triangle propagates NA loss without erroring", {
  exp <- make_exp()
  exp_na <- data.table::copy(exp)
  exp_na[1:50, loss_incr := NA_real_]
  expect_no_error(tri <- build_triangle(exp_na, groups = coverage, cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr"))
  expect_s3_class(tri, "Triangle")
  # at least some NAs survive aggregation
  expect_true(anyNA(tri$loss_incr))
})

# Granularity (quarter / half / year) --------------------------------------

test_that("build_triangle with cohort = 'uy_q' (Q grain) succeeds", {
  exp <- make_exp()
  skip_if_not("uy_q" %in% names(exp), "uy_q not present in experience")
  tri_q <- build_triangle(exp, groups = coverage,
                          cohort = "uy_q", calendar = "cy_q", loss = "loss_incr", premium = "premium_incr")
  expect_s3_class(tri_q, "Triangle")
  expect_identical(attr(tri_q, "cohort"), "uy_q")
  expect_identical(attr(tri_q, "dev"),    "dev_q")
  expect_identical(attr(tri_q, "grain"),      "Q")
  expect_gt(nrow(tri_q), 0L)
})

test_that("build_triangle with cohort = 'uy_s' (S grain) succeeds", {
  exp <- make_exp()
  skip_if_not("uy_s" %in% names(exp), "uy_s not present in experience")
  tri_s <- build_triangle(exp, groups = coverage,
                          cohort = "uy_s", calendar = "cy_s", loss = "loss_incr", premium = "premium_incr")
  expect_s3_class(tri_s, "Triangle")
  expect_identical(attr(tri_s, "cohort"), "uy_s")
  expect_identical(attr(tri_s, "dev"),    "dev_s")
  expect_identical(attr(tri_s, "grain"),      "S")
  expect_gt(nrow(tri_s), 0L)
})

test_that("build_triangle with cohort = 'uy_a' (A grain) succeeds", {
  exp <- make_exp()
  skip_if_not("uy_a" %in% names(exp), "uy_a not present in experience")
  tri_a <- build_triangle(exp, groups = coverage,
                          cohort = "uy_a", calendar = "cy_a", loss = "loss_incr", premium = "premium_incr")
  expect_s3_class(tri_a, "Triangle")
  expect_identical(attr(tri_a, "cohort"), "uy_a")
  expect_identical(attr(tri_a, "dev"),    "dev_a")
  expect_identical(attr(tri_a, "grain"),      "A")
  expect_gt(nrow(tri_a), 0L)
})

test_that("build_triangle errors on grain finer than input (uy_a + grain='M')", {
  exp <- make_exp()
  skip_if_not("uy_a" %in% names(exp), "uy_a not present in experience")
  expect_error(
    build_triangle(exp, groups = coverage,
                   cohort = "uy_a", calendar = "cy_a",
                   loss = "loss_incr", premium = "premium_incr",
                   grain = "M"),
    regexp = "grain"
  )
})

test_that("build_triangle aggregates M input to Q grain via grain='Q'", {
  exp <- make_exp()
  tri_q <- build_triangle(exp, groups = coverage,
                          cohort = "uy_m", calendar = "cy_m",
                          loss = "loss_incr", premium = "premium_incr",
                          grain = "Q")
  expect_s3_class(tri_q, "Triangle")
  expect_identical(attr(tri_q, "grain"),   "Q")
  expect_identical(attr(tri_q, "dev"), "dev_q")
})

test_that("build_calendar with calendar = 'cy_q' returns Calendar quarter", {
  exp <- make_exp()
  skip_if_not("cy_q" %in% names(exp), "cy_q not present in experience")
  cal_q <- build_calendar(exp, groups = coverage, calendar = "cy_q", loss = "loss_incr", premium = "premium_incr")
  expect_s3_class(cal_q, "Calendar")
  expect_identical(attr(cal_q, "calendar"), "cy_q")
  expect_gt(nrow(cal_q), 0L)
})

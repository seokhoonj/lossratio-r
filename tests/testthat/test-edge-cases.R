# Edge-case coverage: empty inputs, single cohort/group, NA loss,
# alternative granularities. The goal is to lock in current behaviour
# (whether that is silent zero-row pass-through or hard error).

# Empty input ---------------------------------------------------------------

test_that("as_triangle accepts a zero-row data.frame and returns empty Triangle", {
  exp_empty <- make_exp()[0L, ]
  expect_no_error(tri <- as_triangle(exp_empty, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure"))
  expect_s3_class(tri, "Triangle")
  expect_equal(nrow(tri), 0L)
  expect_true(all(c("cohort", "dev", "loss", "exposure") %in% names(tri)))
})

# Single cohort -------------------------------------------------------------

test_that("as_triangle on a single cohort succeeds", {
  exp <- make_exp()
  single <- exp[uy_m == as.Date("2024-01-01")]
  tri <- as_triangle(single, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")
  expect_s3_class(tri, "Triangle")
  expect_equal(data.table::uniqueN(tri$cohort), 1L)
  expect_gt(nrow(tri), 0L)
})

test_that("as_link on a single cohort returns Link with valid links", {
  exp <- make_exp()
  single <- exp[uy_m == as.Date("2024-01-01")]
  tri <- as_triangle(single, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")
  ata <- as_link(tri, loss = "loss")
  expect_s3_class(ata, "Link")
  expect_true(all(ata$ata_to == ata$ata_from + 1L))
})

# Single group --------------------------------------------------------------

test_that("as_triangle on a single group succeeds", {
  exp <- make_exp()
  one_grp <- exp[coverage == "surgery"]
  tri <- as_triangle(one_grp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")
  expect_s3_class(tri, "Triangle")
  expect_equal(unique(tri$coverage), "surgery")
})

test_that("summary.Triangle on a single group returns one row per dev", {
  tri <- make_sub_tri("surgery")
  smr  <- summary(tri)
  expect_s3_class(smr, "TriangleSummary")
  expect_equal(nrow(smr), data.table::uniqueN(tri$dev))
})

test_that("fit_cl runs on a single-group triangle", {
  tri <- make_sub_tri("surgery")
  expect_no_error(cl <- fit_cl(tri, loss = "loss", method = "mack"))
  expect_s3_class(cl, "CLFit")
})

# NA loss propagation -------------------------------------------------------

test_that("as_triangle propagates NA loss without erroring", {
  exp <- make_exp()
  exp_na <- data.table::copy(exp)
  exp_na[1:50, incr_loss := NA_real_]
  expect_no_error(tri <- as_triangle(exp_na, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure"))
  expect_s3_class(tri, "Triangle")
  # at least some NAs survive aggregation
  expect_true(anyNA(tri$incr_loss))
})

# Granularity (quarter / half / year) --------------------------------------

test_that("as_triangle with cohort = 'uy_q' (Q grain) succeeds", {
  exp <- make_exp()
  skip_if_not("uy_q" %in% names(exp), "uy_q not present in experience")
  tri_q <- as_triangle(exp, groups = "coverage",
                          cohort = "uy_q", calendar = "cy_q", loss = "incr_loss", exposure = "incr_exposure")
  expect_s3_class(tri_q, "Triangle")
  expect_identical(attr(tri_q, "cohort"), "uy_q")
  expect_identical(attr(tri_q, "dev"),    "dev_q")
  expect_identical(attr(tri_q, "grain"),      "Q")
  expect_gt(nrow(tri_q), 0L)
})

test_that("as_triangle with cohort = 'uy_h' (H grain) succeeds", {
  exp <- make_exp()
  skip_if_not("uy_h" %in% names(exp), "uy_h not present in experience")
  tri_h <- as_triangle(exp, groups = "coverage",
                          cohort = "uy_h", calendar = "cy_h", loss = "incr_loss", exposure = "incr_exposure")
  expect_s3_class(tri_h, "Triangle")
  expect_identical(attr(tri_h, "cohort"), "uy_h")
  expect_identical(attr(tri_h, "dev"),    "dev_h")
  expect_identical(attr(tri_h, "grain"),      "H")
  expect_gt(nrow(tri_h), 0L)
})

test_that("as_triangle with cohort = 'uy' (Y grain) succeeds", {
  exp <- make_exp()
  skip_if_not("uy" %in% names(exp), "uy not present in experience")
  tri_y <- as_triangle(exp, groups = "coverage",
                          cohort = "uy", calendar = "cy", loss = "incr_loss", exposure = "incr_exposure")
  expect_s3_class(tri_y, "Triangle")
  expect_identical(attr(tri_y, "cohort"), "uy")
  expect_identical(attr(tri_y, "dev"),    "dev_y")
  expect_identical(attr(tri_y, "grain"),      "Y")
  expect_gt(nrow(tri_y), 0L)
})

test_that("as_triangle errors on grain finer than input (uy + grain='M')", {
  exp <- make_exp()
  skip_if_not("uy" %in% names(exp), "uy not present in experience")
  expect_error(
    as_triangle(exp, groups = "coverage",
                   cohort = "uy", calendar = "cy",
                   loss = "incr_loss", exposure = "incr_exposure",
                   grain = "M"),
    regexp = "grain"
  )
})

test_that("as_triangle aggregates M input to Q grain via grain='Q'", {
  exp <- make_exp()
  tri_q <- as_triangle(exp, groups = "coverage",
                          cohort = "uy_m", calendar = "cy_m",
                          loss = "incr_loss", exposure = "incr_exposure",
                          grain = "Q")
  expect_s3_class(tri_q, "Triangle")
  expect_identical(attr(tri_q, "grain"),   "Q")
  expect_identical(attr(tri_q, "dev"), "dev_q")
})

test_that("as_calendar with calendar = 'cy_q' returns Calendar quarter", {
  exp <- make_exp()
  skip_if_not("cy_q" %in% names(exp), "cy_q not present in experience")
  cal_q <- as_calendar(as_triangle(exp, groups = "coverage", cohort = "uy_q", calendar = "cy_q", loss = "incr_loss", exposure = "incr_exposure"))
  expect_s3_class(cal_q, "Calendar")
  expect_identical(attr(cal_q, "calendar"), "cy_q")
  expect_gt(nrow(cal_q), 0L)
})

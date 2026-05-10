data(experience, package = "lossratio")

test_that("check_experience accepts valid input", {
  expect_no_error(check_experience(experience))
})

test_that("as_experience errors when required columns are missing", {
  broken <- as.data.frame(experience)[, setdiff(names(experience), "cy_m")]
  expect_error(as_experience(broken),
               regexp = "Missing columns.*'cy_m'")

  broken2 <- as.data.frame(experience)[, setdiff(names(experience),
                                                 c("uy_m", "loss_incr", "premium_incr"))]
  expect_error(as_experience(broken2),
               regexp = "Missing columns.*'uy_m'.*'loss_incr'.*'premium_incr'")
})

test_that("as_experience returns an object inheriting class 'Experience'", {
  exp <- as_experience(experience)
  expect_s3_class(exp, "Experience")
})

test_that("is_experience distinguishes coerced from raw input", {
  expect_true(is_experience(as_experience(experience)))
  expect_false(is_experience(experience))
})

test_that("as_experience coerces date columns to Date class", {
  raw <- as.data.frame(experience)
  raw$cy_m <- as.character(raw$cy_m)
  raw$uy_m <- as.character(raw$uy_m)
  exp <- as_experience(raw)
  expect_s3_class(exp$cy_m, "Date")
  expect_s3_class(exp$uy_m, "Date")
})

test_that("derive_grain_columns adds expected period columns", {
  base <- data.frame(
    uy_m  = as.Date(c("2023-01-01", "2023-04-01", "2023-07-01")),
    cy_m  = as.Date(c("2023-03-01", "2023-06-01", "2023-09-01")),
    dev_m = c(3L, 3L, 3L)
  )
  out <- derive_grain_columns(base)
  expected <- c("uy_a", "uy_s", "uy_q", "cy_a", "cy_s", "cy_q",
                "dev_a", "dev_s", "dev_q")
  expect_true(all(expected %in% names(out)))
  expect_s3_class(out$uy_a, "Date")
  expect_s3_class(out$cy_a, "Date")
  expect_type(out$dev_a, "integer")
})

test_that("derive_grain_columns derives dev_m when missing", {
  base <- data.frame(
    uy_m = as.Date("2023-01-01"),
    cy_m = as.Date("2023-04-01")
  )
  out <- derive_grain_columns(base)
  expect_true("dev_m" %in% names(out))
  expect_equal(out$dev_m, 4L)
})

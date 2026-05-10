data(experience, package = "lossratio")

test_that("plot_triangle(type = 'usage') returns ggplot", {
  exp <- as_experience(experience[coverage == "SUR"])
  tri <- build_triangle(exp, group_var = "coverage",
                        cohort_var = "uy_m", dev_var = "dev_m")
  p <- plot_triangle(tri, type = "usage", holdout = 6L)
  expect_s3_class(p, "ggplot")
})

test_that("plot_triangle(type = 'usage', recent) marks excluded cells", {
  exp <- as_experience(experience[coverage == "SUR"])
  tri <- build_triangle(exp, group_var = "coverage",
                        cohort_var = "uy_m", dev_var = "dev_m")
  p <- plot_triangle(tri, type = "usage", recent = 18L, holdout = 6L)
  expect_s3_class(p, "ggplot")
})

test_that("plot_triangle(type = 'usage') with regime_break + recent activates hybrid", {
  exp <- as_experience(experience[coverage == "SUR"])
  tri <- build_triangle(exp, group_var = "coverage",
                        cohort_var = "uy_m", dev_var = "dev_m")
  p <- plot_triangle(tri, type = "usage", recent = 18L,
                     regime_break = "2025-07-01", holdout = 6L)
  expect_s3_class(p, "ggplot")
})

test_that(".compute_triangle_usage hybrid mask matches expected pattern", {
  exp <- as_experience(experience[coverage == "SUR"])
  tri <- build_triangle(exp, group_var = "coverage",
                        cohort_var = "uy_m", dev_var = "dev_m")
  d <- lossratio:::.compute_triangle_usage(
    tri, recent = 18L, regime_break = as.Date("2025-07-01"),
    holdout = 6L, mat_k = 4L
  )
  pre <- d[cohort < as.Date("2025-07-01") & dev <= 4L & is_held_out == FALSE]
  expect_true(nrow(pre) > 0L)
  expect_true(all(pre$status == "excluded"))

  post <- d[cohort >= as.Date("2025-07-01") & dev <= 4L &
            is_held_out == FALSE & is_observed == TRUE]
  expect_true(nrow(post) > 0L)
  expect_true(all(post$status == "fit_data"))
})

test_that(".compute_triangle_usage status counts add up", {
  exp <- as_experience(experience[coverage == "SUR"])
  tri <- build_triangle(exp, group_var = "coverage",
                        cohort_var = "uy_m", dev_var = "dev_m")
  d <- lossratio:::.compute_triangle_usage(tri, holdout = 6L)
  expect_equal(sum(d$is_observed), nrow(tri))
  expect_equal(
    sum(d$status %in% c("fit_data", "held_out", "excluded")),
    sum(d$is_observed)
  )
  expect_equal(sum(d$status == "future"), nrow(d) - nrow(tri))
})

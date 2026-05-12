data(experience, package = "lossratio")

test_that("plot_triangle(type = 'usage') returns ggplot", {
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  p <- plot_triangle(tri, type = "usage", holdout = 6L)
  expect_s3_class(p, "ggplot")
})

test_that("plot_triangle(type = 'usage', recent) marks excluded cells", {
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  p <- plot_triangle(tri, type = "usage", recent = 18L, holdout = 6L)
  expect_s3_class(p, "ggplot")
})

test_that("plot_triangle(type = 'usage') with regime_break + recent activates hybrid", {
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  p <- plot_triangle(tri, type = "usage", recent = 18L,
                     regime_break = "2024-07-01", holdout = 6L)
  expect_s3_class(p, "ggplot")

  # Hybrid mode must draw the maturity vline. The 2-pass fit_ata call
  # inside `.plot_triangle_usage` previously silently returned NULL
  # because fit_ata was being fed a Link instead of a Triangle, leaving
  # the geom_vline absent. Guard against that regression.
  vline_layers <- vapply(p$layers, function(l) {
    inherits(l$geom, "GeomVline")
  }, logical(1L))
  expect_true(any(vline_layers))
})

test_that(".compute_triangle_usage hybrid mask matches expected pattern", {
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  d <- lossratio:::.compute_triangle_usage(
    tri, recent = 18L, regime_break = as.Date("2024-07-01"),
    holdout = 6L, m_k = 4L
  )
  # m_k = 4: ED region is dev < 4. Cohort cut applies only to ED region.
  pre <- d[cohort < as.Date("2024-07-01") & dev < 4L & is_held_out == FALSE]
  expect_true(nrow(pre) > 0L)
  expect_true(all(pre$status == "unused"))

  post <- d[cohort >= as.Date("2024-07-01") & dev < 4L &
            is_held_out == FALSE & is_observed == TRUE]
  expect_true(nrow(post) > 0L)
  expect_true(all(post$status == "used"))
})

test_that(".compute_triangle_usage status counts add up", {
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  d <- lossratio:::.compute_triangle_usage(tri, holdout = 6L)
  expect_equal(sum(d$is_observed), nrow(tri))
  expect_equal(
    sum(d$status %in% c("used", "holdout", "unused")),
    sum(d$is_observed)
  )
  expect_equal(sum(d$status == "future"), nrow(d) - nrow(tri))
})

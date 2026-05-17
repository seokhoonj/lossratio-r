data(experience, package = "lossratio")

test_that("plot_triangle(view = 'usage') returns ggplot", {
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", prem = "incr_prem")
  p <- plot_triangle(tri, view = "usage", holdout = 6L)
  expect_s3_class(p, "ggplot")
})

test_that("plot_triangle(view = 'usage', recent) marks excluded cells", {
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", prem = "incr_prem")
  p <- plot_triangle(tri, view = "usage", recent = 18L, holdout = 6L)
  expect_s3_class(p, "ggplot")
})

test_that("plot_triangle(view = 'usage') with regime + recent activates hybrid", {
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", prem = "incr_prem")
  p <- plot_triangle(tri, view = "usage", recent = 18L,
                     regime = "2024-07-01", holdout = 6L)
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
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", prem = "incr_prem")
  d <- lossratio:::.compute_triangle_usage(
    tri, recent = 18L, regime = as.Date("2024-07-01"),
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
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", prem = "incr_prem")
  d <- lossratio:::.compute_triangle_usage(tri, holdout = 6L)
  expect_equal(sum(d$is_observed), nrow(tri))
  expect_equal(
    sum(d$status %in% c("used", "holdout", "unused")),
    sum(d$is_observed)
  )
  expect_equal(sum(d$status == "future"), nrow(d) - nrow(tri))
})

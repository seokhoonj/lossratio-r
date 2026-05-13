# Setup
data(experience)
exp <- experience
tri <- build_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
sub <- build_triangle(exp[coverage == "SUR"], groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")


test_that("fit_intensity returns class 'IntensityFit'", {
  intensity_fit <- fit_intensity(sub)
  expect_s3_class(intensity_fit, "IntensityFit")
})

test_that("fit_intensity bundles expected components", {
  intensity_fit <- fit_intensity(sub)
  for (nm in c("call", "data", "groups", "cohort", "dev",
               "target", "exposure", "link", "factor", "selected",
               "alpha", "na_method", "sigma_method", "recent",
               "regime")) {
    expect_true(nm %in% names(intensity_fit), info = paste("missing", nm))
  }
})

test_that("fit_intensity$factor inherits 'EDSummary'", {
  intensity_fit <- fit_intensity(sub)
  expect_s3_class(intensity_fit$factor, "EDSummary")
})

test_that("fit_intensity$selected has g_selected and sigma2 columns", {
  intensity_fit <- fit_intensity(sub)
  expect_true("g_selected" %in% names(intensity_fit$selected))
  expect_true("sigma2"     %in% names(intensity_fit$selected))
  expect_true("sigma_extrapolated" %in% names(intensity_fit$selected))
})

test_that("fit_intensity preserves multi-group structure", {
  intensity_fit <- fit_intensity(tri)
  expect_gt(length(unique(intensity_fit$factor$coverage)), 1L)
})

test_that("fit_intensity rejects non-Triangle input", {
  expect_error(fit_intensity(data.frame(x = 1)))
})

test_that("fit_intensity respects recent filter", {
  intf_full   <- fit_intensity(sub)
  intf_recent <- fit_intensity(sub, recent = 12L)
  expect_equal(intf_recent$recent, 12L)
  # $link is the (filtered) Link; $data stays as the input Triangle
  expect_lt(nrow(intf_recent$link), nrow(intf_full$link))
  expect_equal(nrow(intf_recent$data), nrow(intf_full$data))
})

test_that("summary.IntensityFit returns the EDSummary", {
  intensity_fit <- fit_intensity(sub)
  s <- summary(intensity_fit)
  expect_s3_class(s, "EDSummary")
  expect_identical(s, intensity_fit$factor)
})

test_that("print.IntensityFit does not error", {
  intensity_fit <- fit_intensity(sub)
  expect_no_error(capture.output(print(intensity_fit)))
})

test_that("Link (ED mode) carries `intensity` column (not `g`)", {
  link_ed <- build_link(sub, target = "loss", exposure = "premium")
  expect_true("intensity" %in% names(link_ed))
  expect_false("g" %in% names(link_ed))
})

test_that("intensity == target_delta / exposure_from when exposure_from > 0", {
  link_ed <- build_link(sub, target = "loss", exposure = "premium")
  ok <- is.finite(link_ed$intensity) & link_ed$exposure_from > 0
  expect_equal(link_ed$intensity[ok],
               link_ed$target_delta[ok] / link_ed$exposure_from[ok],
               tolerance = 1e-6)
})

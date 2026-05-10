# Setup
data(experience)
exp <- as_experience(experience)
tri <- build_triangle(exp, group_var = coverage)
sub <- build_triangle(exp[coverage == "SUR"], group_var = coverage)


test_that("fit_intensity returns class 'IntensityFit'", {
  intf <- fit_intensity(sub)
  expect_s3_class(intf, "IntensityFit")
})

test_that("fit_intensity bundles expected components", {
  intf <- fit_intensity(sub)
  for (nm in c("call", "data", "group_var", "cohort_var", "dev_var",
               "loss_var", "premium_var", "link", "factor", "selected",
               "alpha", "na_method", "sigma_method", "recent",
               "regime_break")) {
    expect_true(nm %in% names(intf), info = paste("missing", nm))
  }
})

test_that("fit_intensity$factor inherits 'EDSummary'", {
  intf <- fit_intensity(sub)
  expect_s3_class(intf$factor, "EDSummary")
})

test_that("fit_intensity$selected has g_selected and sigma2 columns", {
  intf <- fit_intensity(sub)
  expect_true("g_selected" %in% names(intf$selected))
  expect_true("sigma2"     %in% names(intf$selected))
  expect_true("sigma_extrapolated" %in% names(intf$selected))
})

test_that("fit_intensity preserves multi-group structure", {
  intf <- fit_intensity(tri)
  expect_gt(length(unique(intf$factor$coverage)), 1L)
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
  intf <- fit_intensity(sub)
  s <- summary(intf)
  expect_s3_class(s, "EDSummary")
  expect_identical(s, intf$factor)
})

test_that("print.IntensityFit does not error", {
  intf <- fit_intensity(sub)
  expect_no_error(capture.output(print(intf)))
})

test_that("Link (ED mode) carries `intensity` column (not `g`)", {
  link_ed <- build_link(sub, loss_var = "loss", premium_var = "premium")
  expect_true("intensity" %in% names(link_ed))
  expect_false("g" %in% names(link_ed))
})

test_that("intensity == loss_delta / premium_from when premium_from > 0", {
  link_ed <- build_link(sub, loss_var = "loss", premium_var = "premium")
  ok <- is.finite(link_ed$intensity) & link_ed$premium_from > 0
  expect_equal(link_ed$intensity[ok],
               link_ed$loss_delta[ok] / link_ed$premium_from[ok],
               tolerance = 1e-6)
})

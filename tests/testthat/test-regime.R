# Setup — use a single-group subset to keep test fast
data(experience)
exp <- experience
sub <- build_triangle(exp[coverage == "SUR"], groups = coverage, cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")

test_that("detect_regime returns class 'Regime' (e_divisive default)", {
  r <- detect_regime(sub, K = 12, method = "e_divisive")
  expect_s3_class(r, "Regime")
  expect_equal(r$method, "e_divisive")
  expect_equal(r$K, 12)
})

test_that("Regime has expected list elements", {
  r <- detect_regime(sub, K = 12, method = "e_divisive")
  for (nm in c("method", "target", "K", "cohort", "dev",
               "groups", "labels", "breakpoints", "n_regimes",
               "trajectory", "pca")) {
    expect_true(nm %in% names(r), info = paste("missing", nm))
  }
})

test_that("$labels has cohort and regime columns", {
  r <- detect_regime(sub, K = 12, method = "e_divisive")
  expect_true("cohort" %in% names(r$labels))
  expect_true("regime" %in% names(r$labels))
})

test_that("$trajectory is a numeric matrix", {
  r <- detect_regime(sub, K = 12, method = "e_divisive")
  expect_true(is.matrix(r$trajectory))
  expect_true(is.numeric(r$trajectory))
})

test_that("$pca$sdev is positive numeric vector", {
  r <- detect_regime(sub, K = 12, method = "e_divisive")
  expect_true(is.numeric(r$pca$sdev))
  expect_true(all(r$pca$sdev >= 0))
})

test_that("methods 'pelt' and 'hclust' run", {
  expect_s3_class(detect_regime(sub, K = 12, method = "pelt"),
                  "Regime")
  expect_s3_class(detect_regime(sub, K = 12, method = "hclust"),
                  "Regime")
})

test_that("hclust with n_regimes = 3 runs", {
  # Note: hclust with k = 3 can produce > 3 sequential regime segments
  # if non-adjacent cohorts share a cluster. Just verify the call runs.
  r <- detect_regime(sub, K = 12, method = "hclust", n_regimes = 3)
  expect_s3_class(r, "Regime")
  expect_true(r$n_regimes >= 1L)
})

test_that("target = 'lr' runs", {
  expect_s3_class(detect_regime(sub, K = 12, method = "e_divisive", target = "lr"),
                  "Regime")
})

test_that("summary.Regime returns class 'summary.Regime'", {
  r <- detect_regime(sub, K = 12, method = "e_divisive")
  s <- summary(r)
  expect_s3_class(s, "summary.Regime")
})

test_that("print methods don't error", {
  r <- detect_regime(sub, K = 12, method = "e_divisive")
  expect_no_error(capture.output(print(r)))
  expect_no_error(capture.output(print(summary(r))))
})

# Multi-group regime detection --------------------------------------------

tri_all <- build_triangle(exp, groups = coverage, cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")

test_that("multi-group detect_regime returns class 'Regime'", {
  r <- detect_regime(tri_all, K = 12, method = "e_divisive")
  expect_s3_class(r, "Regime")
  expect_true(isTRUE(r$multi_group))
})

test_that("multi-group $breakpoints is a data.table with group + breakpoint", {
  r <- detect_regime(tri_all, K = 12, method = "e_divisive")
  expect_true(data.table::is.data.table(r$breakpoints))
  expect_true("coverage" %in% names(r$breakpoints))
  expect_true("breakpoint" %in% names(r$breakpoints))
  expect_true(inherits(r$breakpoints$breakpoint, "Date"))
})

test_that("multi-group $labels has group column", {
  r <- detect_regime(tri_all, K = 12, method = "e_divisive")
  expect_true(data.table::is.data.table(r$labels))
  expect_true("coverage" %in% names(r$labels))
  expect_true("cohort"   %in% names(r$labels))
  expect_true("regime"   %in% names(r$labels))
})

test_that("multi-group $n_regimes is named integer vector", {
  r <- detect_regime(tri_all, K = 12, method = "e_divisive")
  expect_true(is.integer(r$n_regimes))
  expect_true(length(names(r$n_regimes)) == length(r$n_regimes))
  expect_true(all(r$n_regimes >= 1L))
})

test_that("multi-group $trajectory and $pca are named lists", {
  r <- detect_regime(tri_all, K = 12, method = "e_divisive")
  expect_true(is.list(r$trajectory))
  expect_true(is.list(r$pca))
  expect_true(all(vapply(r$trajectory, is.matrix, logical(1L))))
  expect_true(all(vapply(r$pca, inherits, logical(1L), "prcomp")))
})

test_that("multi-group hclust runs", {
  r <- detect_regime(tri_all, K = 12, method = "hclust", n_regimes = 2L)
  expect_s3_class(r, "Regime")
  expect_true(isTRUE(r$multi_group))
})

test_that("multi-group print / summary don't error", {
  r <- detect_regime(tri_all, K = 12, method = "e_divisive")
  expect_no_error(capture.output(print(r)))
  expect_no_error(capture.output(print(summary(r))))
})

test_that(".resolve_break_date handles multi-group Regime", {
  r <- detect_regime(tri_all, K = 12, method = "e_divisive")
  if (nrow(r$breakpoints)) {
    bd <- lossratio:::.resolve_break_date(r)
    expect_true(inherits(bd, "Date"))
    expect_equal(bd, max(r$breakpoints$breakpoint))
  } else {
    expect_null(lossratio:::.resolve_break_date(r))
  }
})

test_that("multi-group plot.Regime returns a ggplot or patchwork object", {
  r <- detect_regime(tri_all, K = 12, method = "e_divisive")
  p <- plot(r)
  expect_true(inherits(p, "ggplot") || inherits(p, "patchwork") ||
              is.list(p))
})

test_that("detect_regime errors when no group has enough cohorts", {
  # K larger than any group's cohort count -> every group dropped
  expect_error(
    detect_regime(tri_all, K = 1000L, method = "e_divisive"),
    "No group produced a usable detection result"
  )
})

test_that("detect_regime warns and skips groups that fail individually", {
  # Build a synthetic triangle where one group has too few cohorts but
  # others remain valid. Drop most of one coverage's cohorts.
  big_K <- 12L
  exp_part <- experience[!(coverage == "CI" & uy_m > as.Date("2023-03-01"))]
  tri_part <- build_triangle(exp_part, groups = coverage, cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  expect_warning(
    r_part <- detect_regime(tri_part, K = big_K, method = "e_divisive"),
    "skipped"
  )
  expect_s3_class(r_part, "Regime")
  expect_true(isTRUE(r_part$multi_group))
  expect_false("CI" %in% names(r_part$trajectory))
})

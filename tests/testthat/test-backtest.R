# Setup
data(experience)
exp <- experience
tri <- as_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_prem")
sub <- as_triangle(exp[coverage == "SUR"], groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_prem")

test_that("backtest returns class 'Backtest'", {
  bt <- backtest(sub, holdout = 6L, target = "loss", loss_method = "cl")
  expect_s3_class(bt, "Backtest")
})

test_that("Backtest has expected list elements", {
  bt <- backtest(sub, holdout = 6L, target = "loss", loss_method = "cl")
  for (nm in c("call", "data", "masked", "fit",
               "ae_err", "col_summary", "diag_summary",
               "target", "holdout", "dispatcher",
               "groups", "cohort", "dev")) {
    expect_true(nm %in% names(bt), info = paste("missing", nm))
  }
})

test_that("ae_err has expected columns", {
  bt <- backtest(sub, holdout = 6L, target = "loss", loss_method = "cl")
  for (nm in c("coverage", "cohort", "dev", "actual", "expected",
               "ae_err", "calendar_idx")) {
    expect_true(nm %in% names(bt$ae_err), info = paste("missing", nm))
  }
})

test_that("backtest stores both cumulative and incremental views", {
  for (t in c("lr", "loss", "prem")) {
    bt <- backtest(sub, holdout = 6L, target = t, loss_method = "cl")
    expect_s3_class(bt, "Backtest")
    # Cumulative columns
    for (nm in c("actual", "expected", "aeg", "ae_err"))
      expect_true(nm %in% names(bt$ae_err),
                  info = paste(t, "missing", nm))
    # Incremental columns
    for (nm in c("incr_actual", "incr_expected",
                 "incr_aeg", "incr_ae_err"))
      expect_true(nm %in% names(bt$ae_err),
                  info = paste(t, "missing", nm))
  }
})

test_that("ae_err = actual / expected - 1 (cell-wise, A/E convention)", {
  bt <- backtest(sub, holdout = 6L, target = "loss", loss_method = "cl")
  ok <- with(bt$ae_err, is.finite(expected) & expected != 0 &
                     is.finite(actual))
  expect_equal(bt$ae_err$ae_err[ok],
               (bt$ae_err$actual[ok] / bt$ae_err$expected[ok]) - 1,
               tolerance = 1e-8)
})

test_that("aeg = actual - expected (raw gap, cumulative + incremental)", {
  bt <- backtest(sub, holdout = 6L, target = "loss", loss_method = "cl")
  expect_equal(bt$ae_err$aeg,
               bt$ae_err$actual - bt$ae_err$expected,
               tolerance = 1e-8)
  ok <- with(bt$ae_err, is.finite(incr_actual) & is.finite(incr_expected))
  expect_equal(bt$ae_err$incr_aeg[ok],
               (bt$ae_err$incr_actual - bt$ae_err$incr_expected)[ok],
               tolerance = 1e-8)
})

test_that("col_summary and diag_summary keyed correctly", {
  bt <- backtest(sub, holdout = 6L, target = "loss", loss_method = "cl")
  expect_true(all(c("coverage", "dev", "n", "ae_err_mean",
                    "ae_err_med", "ae_err_wt") %in% names(bt$col_summary)))
  expect_true(all(c("coverage", "calendar_idx", "n", "ae_err_mean",
                    "ae_err_med", "ae_err_wt") %in% names(bt$diag_summary)))
})

test_that("masked triangle has fewer rows than original", {
  bt <- backtest(sub, holdout = 6L, target = "loss", loss_method = "cl")
  expect_lt(nrow(bt$masked), nrow(sub))
  expect_s3_class(bt$masked, "Triangle")
})

test_that("backtest preserves multi-group structure", {
  bt <- backtest(tri, holdout = 6L, target = "loss", loss_method = "cl")
  expect_true("coverage" %in% names(bt$ae_err))
  expect_gt(length(unique(bt$ae_err$coverage)), 1L)
})

test_that("backtest errors on invalid holdout", {
  expect_error(backtest(sub, holdout = 0),
               regexp = "holdout.*positive integer")
  expect_error(backtest(sub, holdout = -3),
               regexp = "holdout.*positive integer")
  expect_error(backtest(sub, holdout = 9999),
               regexp = "no observations remain")
})

test_that("backtest errors on invalid target", {
  # `target` is one of "lr" / "loss" / "prem" (match.arg).
  expect_error(
    backtest(sub, holdout = 6L, target = "nonexistent")
  )
})

test_that("summary.Backtest returns class 'summary.Backtest'", {
  bt <- backtest(sub, holdout = 6L, target = "loss", loss_method = "cl")
  s <- summary(bt)
  expect_s3_class(s, "summary.Backtest")
})

test_that("print methods don't error", {
  bt <- backtest(sub, holdout = 6L, target = "loss", loss_method = "cl")
  expect_no_error(capture.output(print(bt)))
  expect_no_error(capture.output(print(summary(bt))))
})

# Plot dispatch ---------------------------------------------------------

is_plot <- function(x) inherits(x, "ggplot") || inherits(x, "gtable")

test_that("plot.Backtest dispatches across types", {
  bt <- backtest(sub, holdout = 6L, target = "loss", loss_method = "cl")
  for (tp in c("col", "diag", "cell")) {
    p <- suppressWarnings(plot(bt, type = tp))
    expect_true(is_plot(p), info = paste("type =", tp))
  }
})

test_that("plot_triangle.Backtest dispatches", {
  bt <- backtest(sub, holdout = 6L, target = "loss", loss_method = "cl")
  expect_true(is_plot(suppressWarnings(plot_triangle(bt))))
})

# fit_lr / target = "lr" support ----------------------------------------

test_that("backtest works with target = 'lr', loss_method = 'sa'", {
  bt <- backtest(sub, holdout = 6L, target = "lr", loss_method = "sa")
  expect_s3_class(bt, "Backtest")
  expect_s3_class(bt$fit, "LRFit")
  expect_true("expected" %in% names(bt$ae_err))
  expect_true(any(is.finite(bt$ae_err$ae_err)))
})

test_that("backtest works with target = 'lr', loss_method = 'ed'", {
  bt <- backtest(sub, holdout = 6L, target = "lr", loss_method = "ed")
  expect_s3_class(bt, "Backtest")
  expect_s3_class(bt$fit, "LRFit")
  expect_true(any(is.finite(bt$ae_err$ae_err)))
})

test_that("backtest works with target = 'lr', loss_method = 'cl'", {
  bt <- backtest(sub, holdout = 6L, target = "lr", loss_method = "cl")
  expect_s3_class(bt, "Backtest")
  expect_s3_class(bt$fit, "LRFit")
  expect_true(any(is.finite(bt$ae_err$ae_err)))
})

test_that("backtest target = 'lr' uses lr_proj", {
  bt <- backtest(sub, holdout = 6L, target = "lr", loss_method = "sa")
  cell <- bt$ae_err[is.finite(bt$ae_err$expected), ][1L, ]
  full <- bt$fit$full
  match_row <- full[full$cohort == cell$cohort & full$dev == cell$dev, ]
  expect_equal(nrow(match_row), 1L)
  expect_equal(cell$expected, match_row$lr_proj, tolerance = 1e-8)
})

test_that("backtest preserves multi-group structure with target = 'lr'", {
  bt <- backtest(tri, holdout = 6L, target = "lr", loss_method = "cl")
  expect_gt(length(unique(bt$ae_err$coverage)), 1L)
})

test_that("plot.Backtest dispatches for lr backtests", {
  bt <- backtest(sub, holdout = 6L, target = "lr", loss_method = "sa")
  for (tp in c("col", "diag", "cell")) {
    p <- suppressWarnings(plot(bt, type = tp))
    expect_true(is_plot(p), info = paste("type =", tp))
  }
})

# target = "prem" support --------------------------------------------

test_that("backtest works with target = 'prem', premium_method = 'ed'", {
  bt <- backtest(sub, holdout = 6L, target = "prem",
                 premium_method = "ed")
  expect_s3_class(bt, "Backtest")
  expect_true("expected" %in% names(bt$ae_err))
  expect_true(any(is.finite(bt$ae_err$ae_err)))
})

# segment_wise integration ---------------------------------------------

test_that("backtest accepts segment_wise Regime via loss_regime", {
  bt <- backtest(
    sub, holdout = 6L, target = "lr",
    loss_regime = regime_at(change    = c("2024-01-01", "2024-07-01"),
                            treatment = "segment_wise")
  )
  expect_s3_class(bt, "Backtest")
  expect_s3_class(bt$fit, "LRFit")
  # segment_wise treatment carries through to the resolved regime
  expect_equal(bt$fit$loss_regime$treatment, "segment_wise")
  # Backtest still produces ae_err rows
  expect_gt(nrow(bt$ae_err), 0L)
})

test_that("fit_lr accepts segment_wise Regime via loss_regime", {
  fit <- fit_lr(
    sub,
    loss_regime = regime_at(change    = c("2024-01-01", "2024-07-01"),
                            treatment = "segment_wise")
  )
  expect_s3_class(fit, "LRFit")
  expect_equal(fit$loss_regime$treatment, "segment_wise")
  # $full / $proj still populated
  expect_true(!is.null(fit$full))
  expect_gt(nrow(fit$full), 0L)
})

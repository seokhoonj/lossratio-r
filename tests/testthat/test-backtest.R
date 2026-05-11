# Setup
data(experience)
exp <- experience
tri <- build_triangle(exp, group_var = coverage)
sub <- build_triangle(exp[coverage == "SUR"], group_var = coverage)

test_that("backtest returns class 'Backtest'", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 metric = "loss", method = "mack")
  expect_s3_class(bt, "Backtest")
})

test_that("Backtest has expected list elements", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 metric = "loss", method = "mack")
  for (nm in c("call", "data", "masked", "fit",
               "ae_err", "col_summary", "diag_summary",
               "metric", "holdout", "fit_fn_name",
               "group_var", "cohort_var", "dev_var")) {
    expect_true(nm %in% names(bt), info = paste("missing", nm))
  }
})

test_that("ae_err has expected columns", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 metric = "loss", method = "mack")
  for (nm in c("coverage", "cohort", "dev", "value_actual", "value_pred",
               "ae_err", "calendar_idx")) {
    expect_true(nm %in% names(bt$ae_err), info = paste("missing", nm))
  }
})

test_that("ae_err = actual / pred - 1 (cell-wise, A/E convention)", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 metric = "loss", method = "mack")
  ok <- with(bt$ae_err, is.finite(value_pred) & value_pred != 0 &
                     is.finite(value_actual))
  expect_equal(bt$ae_err$ae_err[ok],
               (bt$ae_err$value_actual[ok] / bt$ae_err$value_pred[ok]) - 1,
               tolerance = 1e-8)
})

test_that("col_summary and diag_summary keyed correctly", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 metric = "loss", method = "mack")
  expect_true(all(c("coverage", "dev", "n", "ae_err_mean",
                    "ae_err_med", "ae_err_wt") %in% names(bt$col_summary)))
  expect_true(all(c("coverage", "calendar_idx", "n", "ae_err_mean",
                    "ae_err_med", "ae_err_wt") %in% names(bt$diag_summary)))
})

test_that("masked triangle has fewer rows than original", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 metric = "loss", method = "mack")
  expect_lt(nrow(bt$masked), nrow(sub))
  expect_s3_class(bt$masked, "Triangle")
})

test_that("backtest works with method = 'basic'", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 metric = "loss", method = "basic")
  expect_s3_class(bt, "Backtest")
})

test_that("backtest preserves multi-group structure", {
  bt <- backtest(tri, holdout = 6L, fit_fn = fit_cl,
                 metric = "loss", method = "mack")
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

test_that("backtest errors on missing metric (fit_cl)", {
  expect_error(
    backtest(sub, holdout = 6L, fit_fn = fit_cl, metric = "nonexistent"),
    regexp = "metric.*nonexistent.*not found"
  )
})

test_that("summary.Backtest returns class 'summary.Backtest'", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 metric = "loss", method = "mack")
  s <- summary(bt)
  expect_s3_class(s, "summary.Backtest")
})

test_that("print methods don't error", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 metric = "loss", method = "mack")
  expect_no_error(capture.output(print(bt)))
  expect_no_error(capture.output(print(summary(bt))))
})

# Plot dispatch ---------------------------------------------------------

is_plot <- function(x) inherits(x, "ggplot") || inherits(x, "gtable")

test_that("plot.Backtest dispatches across types", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 metric = "loss", method = "mack")
  for (tp in c("col", "diag", "cell")) {
    p <- suppressWarnings(plot(bt, type = tp))
    expect_true(is_plot(p), info = paste("type =", tp))
  }
})

test_that("plot_triangle.Backtest dispatches", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 metric = "loss", method = "mack")
  expect_true(is_plot(suppressWarnings(plot_triangle(bt))))
})

# fit_lr support --------------------------------------------------------

test_that("backtest works with fit_lr method = 'sa'", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_lr,
                 method = "sa", metric = "lr")
  expect_s3_class(bt, "Backtest")
  expect_s3_class(bt$fit, "LRFit")
  expect_true("value_pred" %in% names(bt$ae_err))
  expect_true(any(is.finite(bt$ae_err$ae_err)))
})

test_that("backtest works with fit_lr method = 'ed'", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_lr,
                 method = "ed", metric = "lr")
  expect_s3_class(bt, "Backtest")
  expect_s3_class(bt$fit, "LRFit")
  expect_true(any(is.finite(bt$ae_err$ae_err)))
})

test_that("backtest works with fit_lr method = 'cl'", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_lr,
                 method = "cl", metric = "lr")
  expect_s3_class(bt, "Backtest")
  expect_s3_class(bt$fit, "LRFit")
  expect_true(any(is.finite(bt$ae_err$ae_err)))
})

test_that("backtest fit_lr metric = 'lr' uses lr_proj", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_lr,
                 method = "sa", metric = "lr")
  cell <- bt$ae_err[is.finite(bt$ae_err$value_pred), ][1L, ]
  full <- bt$fit$full
  match_row <- full[full$cohort == cell$cohort & full$dev == cell$dev, ]
  expect_equal(nrow(match_row), 1L)
  expect_equal(cell$value_pred, match_row$lr_proj, tolerance = 1e-8)
})

test_that("backtest rejects metric != 'lr' for ratio-fits", {
  # fit_lr / fit_ed only support metric = "lr"; loss / premium /
  # loss_prop are not valid scoring lanes for a ratio-fit (use fit_cl
  # directly for those).
  expect_error(
    backtest(sub, holdout = 6L, fit_fn = fit_lr,
             method = "sa", metric = "premium"),
    regexp = "ratio-fit"
  )
  expect_error(
    backtest(sub, holdout = 6L, fit_fn = fit_lr,
             method = "sa", metric = "loss_prop"),
    regexp = "ratio-fit"
  )
  expect_error(
    backtest(sub, holdout = 6L, fit_fn = fit_ed, metric = "loss"),
    regexp = "ratio-fit"
  )
})

test_that("backtest preserves multi-group structure with fit_lr", {
  bt <- backtest(tri, holdout = 6L, fit_fn = fit_lr,
                 method = "cl", metric = "lr")
  expect_gt(length(unique(bt$ae_err$coverage)), 1L)
})

test_that("plot.Backtest dispatches for fit_lr backtests", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_lr,
                 method = "sa", metric = "lr")
  for (tp in c("col", "diag", "cell")) {
    p <- suppressWarnings(plot(bt, type = tp))
    expect_true(is_plot(p), info = paste("type =", tp))
  }
})

# fit_ed support --------------------------------------------------------

test_that("backtest works with fit_ed (metric = 'lr')", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_ed, metric = "lr")
  expect_s3_class(bt, "Backtest")
  expect_s3_class(bt$fit, "EDFit")
  expect_true("value_pred" %in% names(bt$ae_err))
  expect_true(any(is.finite(bt$ae_err$ae_err)))
})

test_that("backtest fit_ed metric = 'lr' uses lr_proj", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_ed, metric = "lr")
  cell <- bt$ae_err[is.finite(bt$ae_err$value_pred), ][1L, ]
  full <- bt$fit$full
  match_row <- full[full$cohort == cell$cohort & full$dev == cell$dev, ]
  expect_equal(nrow(match_row), 1L)
  expect_equal(cell$value_pred, match_row$lr_proj, tolerance = 1e-8)
})

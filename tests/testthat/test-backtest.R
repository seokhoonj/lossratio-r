# Setup
data(experience)
exp <- as_experience(experience)
tri <- build_triangle(exp, group_var = cv_nm)
sub <- build_triangle(exp[cv_nm == "SUR"], group_var = cv_nm)

test_that("backtest returns class 'Backtest'", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 loss_var = "loss", method = "mack")
  expect_s3_class(bt, "Backtest")
})

test_that("Backtest has expected list elements", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 loss_var = "loss", method = "mack")
  for (nm in c("call", "data", "masked", "fit",
               "aeg", "col_summary", "diag_summary",
               "loss_var", "holdout", "fit_fn_name",
               "group_var", "cohort_var", "dev_var")) {
    expect_true(nm %in% names(bt), info = paste("missing", nm))
  }
})

test_that("aeg has expected columns", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 loss_var = "loss", method = "mack")
  for (nm in c("cv_nm", "cohort", "dev", "value_actual", "value_pred",
               "aeg", "calendar_idx")) {
    expect_true(nm %in% names(bt$aeg), info = paste("missing", nm))
  }
})

test_that("aeg = actual / pred - 1 (cell-wise, A/E convention)", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 loss_var = "loss", method = "mack")
  ok <- with(bt$aeg, is.finite(value_pred) & value_pred != 0 &
                     is.finite(value_actual))
  expect_equal(bt$aeg$aeg[ok],
               (bt$aeg$value_actual[ok] / bt$aeg$value_pred[ok]) - 1,
               tolerance = 1e-8)
})

test_that("col_summary and diag_summary keyed correctly", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 loss_var = "loss", method = "mack")
  expect_true(all(c("cv_nm", "dev", "n", "aeg_mean",
                    "aeg_med", "aeg_wt") %in% names(bt$col_summary)))
  expect_true(all(c("cv_nm", "calendar_idx", "n", "aeg_mean",
                    "aeg_med", "aeg_wt") %in% names(bt$diag_summary)))
})

test_that("masked triangle has fewer rows than original", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 loss_var = "loss", method = "mack")
  expect_lt(nrow(bt$masked), nrow(sub))
  expect_s3_class(bt$masked, "Triangle")
})

test_that("backtest works with method = 'basic'", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 loss_var = "loss", method = "basic")
  expect_s3_class(bt, "Backtest")
})

test_that("backtest preserves multi-group structure", {
  bt <- backtest(tri, holdout = 6L, fit_fn = fit_cl,
                 loss_var = "loss", method = "mack")
  expect_true("cv_nm" %in% names(bt$aeg))
  expect_gt(length(unique(bt$aeg$cv_nm)), 1L)
})

test_that("backtest errors on invalid holdout", {
  expect_error(backtest(sub, holdout = 0),
               regexp = "holdout.*positive integer")
  expect_error(backtest(sub, holdout = -3),
               regexp = "holdout.*positive integer")
  expect_error(backtest(sub, holdout = 9999),
               regexp = "no observations remain")
})

test_that("backtest errors on missing loss_var", {
  expect_error(backtest(sub, holdout = 6L, loss_var = "nonexistent"),
               regexp = "loss_var.*nonexistent.*not found")
})

test_that("summary.Backtest returns class 'summary.Backtest'", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 loss_var = "loss", method = "mack")
  s <- summary(bt)
  expect_s3_class(s, "summary.Backtest")
})

test_that("print methods don't error", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 loss_var = "loss", method = "mack")
  expect_no_error(capture.output(print(bt)))
  expect_no_error(capture.output(print(summary(bt))))
})

# Plot dispatch ---------------------------------------------------------

is_plot <- function(x) inherits(x, "ggplot") || inherits(x, "gtable")

test_that("plot.Backtest dispatches across types", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 loss_var = "loss", method = "mack")
  for (tp in c("col", "diag", "cell")) {
    p <- suppressWarnings(plot(bt, type = tp))
    expect_true(is_plot(p), info = paste("type =", tp))
  }
})

test_that("plot_triangle.Backtest dispatches", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_cl,
                 loss_var = "loss", method = "mack")
  expect_true(is_plot(suppressWarnings(plot_triangle(bt))))
})

# fit_lr support --------------------------------------------------------

test_that("backtest works with fit_lr method = 'sa'", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_lr,
                 method = "sa", loss_var = "loss")
  expect_s3_class(bt, "Backtest")
  expect_s3_class(bt$fit, "LRFit")
  expect_true("value_pred" %in% names(bt$aeg))
  expect_true(any(is.finite(bt$aeg$aeg)))
})

test_that("backtest works with fit_lr method = 'ed'", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_lr,
                 method = "ed", loss_var = "loss")
  expect_s3_class(bt, "Backtest")
  expect_s3_class(bt$fit, "LRFit")
  expect_true(any(is.finite(bt$aeg$aeg)))
})

test_that("backtest works with fit_lr method = 'cl'", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_lr,
                 method = "cl", loss_var = "loss")
  expect_s3_class(bt, "Backtest")
  expect_s3_class(bt$fit, "LRFit")
  expect_true(any(is.finite(bt$aeg$aeg)))
})

test_that("backtest fit_lr loss_var = 'lr' uses lr_proj", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_lr,
                 method = "sa", loss_var = "lr")
  cell <- bt$aeg[is.finite(bt$aeg$value_pred), ][1L, ]
  full <- bt$fit$full
  match_row <- full[full$cohort == cell$cohort & full$dev == cell$dev, ]
  expect_equal(nrow(match_row), 1L)
  expect_equal(cell$value_pred, match_row$lr_proj, tolerance = 1e-8)
})

test_that("backtest fit_lr loss_var = 'premium' uses premium_proj", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_lr,
                 method = "sa", loss_var = "premium")
  cell <- bt$aeg[is.finite(bt$aeg$value_pred), ][1L, ]
  full <- bt$fit$full
  match_row <- full[full$cohort == cell$cohort & full$dev == cell$dev, ]
  expect_equal(nrow(match_row), 1L)
  expect_equal(cell$value_pred, match_row$premium_proj, tolerance = 1e-8)
})

test_that("backtest errors when fit_lr loss_var is unsupported", {
  expect_error(backtest(sub, holdout = 6L, fit_fn = fit_lr,
                        method = "sa", loss_var = "loss_prop"))
})

test_that("backtest preserves multi-group structure with fit_lr", {
  bt <- backtest(tri, holdout = 6L, fit_fn = fit_lr,
                 method = "cl", loss_var = "loss")
  expect_gt(length(unique(bt$aeg$cv_nm)), 1L)
})

test_that("plot.Backtest dispatches for fit_lr backtests", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_lr,
                 method = "sa", loss_var = "loss")
  for (tp in c("col", "diag", "cell")) {
    p <- suppressWarnings(plot(bt, type = tp))
    expect_true(is_plot(p), info = paste("type =", tp))
  }
})

# fit_ed support --------------------------------------------------------

test_that("backtest works with fit_ed", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_ed,
                 loss_var = "loss")
  expect_s3_class(bt, "Backtest")
  expect_s3_class(bt$fit, "EDFit")
  expect_true("value_pred" %in% names(bt$aeg))
  expect_true(any(is.finite(bt$aeg$aeg)))
})

test_that("backtest fit_ed loss_var = 'loss' uses loss_proj", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_ed,
                 loss_var = "loss")
  cell <- bt$aeg[is.finite(bt$aeg$value_pred), ][1L, ]
  full <- bt$fit$full
  match_row <- full[full$cohort == cell$cohort & full$dev == cell$dev, ]
  expect_equal(nrow(match_row), 1L)
  expect_equal(cell$value_pred, match_row$loss_proj, tolerance = 1e-8)
})

test_that("backtest fit_ed loss_var = 'lr' uses lr_proj", {
  bt <- backtest(sub, holdout = 6L, fit_fn = fit_ed,
                 loss_var = "lr")
  cell <- bt$aeg[is.finite(bt$aeg$value_pred), ][1L, ]
  full <- bt$fit$full
  match_row <- full[full$cohort == cell$cohort & full$dev == cell$dev, ]
  expect_equal(nrow(match_row), 1L)
  expect_equal(cell$value_pred, match_row$lr_proj, tolerance = 1e-8)
})

test_that("backtest errors when fit_ed loss_var is unsupported", {
  expect_error(backtest(sub, holdout = 6L, fit_fn = fit_ed,
                        loss_var = "loss_prop"))
})

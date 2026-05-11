# Setup — use a single-group subset to keep test fast
data(experience)
exp <- experience
sub <- build_triangle(exp[coverage == "SUR"], group_var = coverage)

test_that("detect_regime returns class 'Regime' (e_divisive default)", {
  r <- detect_regime(sub, K = 12, method = "e_divisive")
  expect_s3_class(r, "Regime")
  expect_equal(r$method, "e_divisive")
  expect_equal(r$K, 12)
})

test_that("Regime has expected list elements", {
  r <- detect_regime(sub, K = 12, method = "e_divisive")
  for (nm in c("method", "loss_var", "K", "cohort_var", "dev_var",
               "group_var", "labels", "breakpoints", "n_regimes",
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

test_that("loss_var = 'lr' runs", {
  expect_s3_class(detect_regime(sub, K = 12, method = "e_divisive", loss_var = "lr"),
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

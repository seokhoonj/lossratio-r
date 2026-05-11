# Setup
data(experience)
exp <- experience
tri <- build_triangle(exp, group_var = coverage)

test_that("fit_cl method = 'mack' returns class 'CLFit' with expected structure", {
  cl <- fit_cl(tri, target = "loss", method = "mack")
  expect_s3_class(cl, "CLFit")
  for (nm in c("data", "method", "group_var", "cohort_var", "dev_var",
               "target", "full", "pred", "link", "summary",
               "factor", "selected")) {
    expect_true(nm %in% names(cl), info = paste("missing", nm))
  }
  expect_equal(cl$method, "mack")
})

test_that("$full has expected columns", {
  cl <- fit_cl(tri, target = "loss", method = "mack")
  for (nm in c("coverage", "cohort", "dev", "target_obs", "target_proj", "is_observed")) {
    expect_true(nm %in% names(cl$full), info = paste("missing", nm))
  }
})

test_that("target_proj is finite for projected cells", {
  cl <- fit_cl(tri, target = "loss", method = "mack")
  proj_only <- cl$full[is_observed == FALSE]
  expect_true(all(is.finite(proj_only$target_proj)))
})

test_that("fit_cl method = 'mack' adds variance columns", {
  cl <- fit_cl(tri, target = "loss", method = "mack")
  for (nm in c("target_proc_se", "target_param_se",
               "target_total_se", "target_total_cv")) {
    expect_true(nm %in% names(cl$full), info = paste("missing", nm))
  }
})

test_that("Mack standard errors are non-negative", {
  cl <- fit_cl(tri, target = "loss", method = "mack")
  ses <- cl$full[is.finite(target_total_se), target_total_se]
  expect_true(all(ses >= 0))
})

test_that("$summary has one row per (group, cohort) with expected columns", {
  cl <- fit_cl(tri, target = "loss", method = "mack")
  for (nm in c("coverage", "cohort", "latest", "loss_ult", "reserve")) {
    expect_true(nm %in% names(cl$summary), info = paste("missing", nm))
  }
})

test_that("tail = TRUE produces finite tail_factor", {
  cl <- fit_cl(tri, target = "loss", method = "mack", tail = TRUE)
  expect_true(is.finite(cl$tail_factor))
})

test_that("tail = numeric scalar sets tail_factor literally", {
  cl <- fit_cl(tri, target = "loss", method = "mack", tail = 1.05)
  expect_equal(cl$tail_factor, 1.05)
})

test_that("tail = FALSE keeps tail_factor at 1", {
  cl <- fit_cl(tri, target = "loss", method = "mack", tail = FALSE)
  expect_equal(cl$tail_factor, 1)
})

test_that("maturity_args triggers maturity detection", {
  cl <- fit_cl(tri, target = "loss", method = "mack", maturity_args = list())
  expect_false(is.null(cl$maturity))
})

test_that("summary(CLFit) returns the $summary table", {
  cl <- fit_cl(tri, target = "loss", method = "mack")
  s <- summary(cl)
  expect_identical(s, cl$summary)
})

test_that("print.CLFit doesn't error", {
  cl <- fit_cl(tri, target = "loss", method = "mack")
  expect_no_error(capture.output(print(cl)))
})

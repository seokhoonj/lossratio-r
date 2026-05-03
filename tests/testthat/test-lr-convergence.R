# Setup
data(experience)
exp <- as_experience(experience)
sub <- build_triangle(exp[cv_nm == "SUR"], group_var = cv_nm)
tri <- build_triangle(exp, group_var = cv_nm)

test_that("find_lr_convergence returns class 'LRConvergence' with required fields", {
  res <- find_lr_convergence(sub)
  expect_s3_class(res, "LRConvergence")
  for (nm in c("k_conv", "R_v", "SE_param_v", "D_v", "pass_v",
               "k_star", "c", "tau", "M")) {
    expect_true(nm %in% names(res), info = paste("missing", nm))
  }
  for (a in c("group_var", "value_var", "fit_fn_name")) {
    expect_false(is.null(attr(res, a)), info = paste("missing attr", a))
  }
})

test_that("k_conv is >= k_star when non-NA", {
  res <- find_lr_convergence(sub)
  if (!is.na(res$k_conv)) {
    expect_gte(res$k_conv, res$k_star)
  } else {
    succeed()
  }
})

test_that("insufficient history yields k_conv == NA", {
  k_star_guess <- 6L
  short_exp <- exp[cv_nm == "SUR" & elap_m <= k_star_guess + 2L]
  short_tri <- build_triangle(short_exp, group_var = cv_nm)
  res <- find_lr_convergence(short_tri, k_star = k_star_guess, M = 3L)
  expect_true(is.na(res$k_conv))
})

test_that("tighter c yields a later k_conv (or NA)", {
  loose <- find_lr_convergence(sub, c = 1.0)
  tight <- find_lr_convergence(sub, c = 0.1)
  if (!is.na(loose$k_conv) && !is.na(tight$k_conv)) {
    expect_gte(tight$k_conv, loose$k_conv)
  } else if (!is.na(loose$k_conv) && is.na(tight$k_conv)) {
    succeed()
  } else {
    succeed()
  }
})

test_that("tighter tau yields a later k_conv (or NA)", {
  loose <- find_lr_convergence(sub, tau = 0.5)
  tight <- find_lr_convergence(sub, tau = 0.05)
  if (!is.na(loose$k_conv) && !is.na(tight$k_conv)) {
    expect_gte(tight$k_conv, loose$k_conv)
  } else if (!is.na(loose$k_conv) && is.na(tight$k_conv)) {
    succeed()
  } else {
    succeed()
  }
})

test_that("min_n_cohorts guard yields NA D_v and pass_v == FALSE", {
  res <- find_lr_convergence(sub, min_n_cohorts = 1000L)
  expect_true(any(is.na(res$D_v)) || all(is.na(res$D_v)))
  expect_false(any(isTRUE(unname(res$pass_v))))
})

test_that("explicit k_star overrides find_ata_maturity()", {
  res <- find_lr_convergence(sub, k_star = 6L)
  expect_equal(res$k_star, 6L)
  if (!is.na(res$k_conv)) {
    expect_gte(res$k_conv, 6L)
  } else {
    succeed()
  }
})

test_that("fit_fn argument is honored (fit_cl vs fit_lr both run)", {
  res_cl <- find_lr_convergence(sub, fit_fn = fit_cl)
  res_lr <- find_lr_convergence(sub, fit_fn = fit_lr)
  expect_s3_class(res_cl, "LRConvergence")
  expect_s3_class(res_lr, "LRConvergence")
  expect_equal(attr(res_cl, "fit_fn_name"), "fit_cl")
  expect_equal(attr(res_lr, "fit_fn_name"), "fit_lr")
})

test_that("print and summary methods execute and return non-NULL", {
  res <- find_lr_convergence(sub)
  expect_no_error(out <- capture.output(print(res)))
  expect_true(length(out) > 0L)
  s <- summary(res)
  expect_false(is.null(s))
})

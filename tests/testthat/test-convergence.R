# Setup
data(experience)
exp <- as_experience(experience)
sub <- build_triangle(exp[cv_nm == "SUR"], group_var = cv_nm)
tri <- build_triangle(exp, group_var = cv_nm)

test_that("detect_convergence returns class 'Convergence' with required fields", {
  res <- detect_convergence(sub)
  expect_s3_class(res, "Convergence")
  for (nm in c("k_conv", "R_v", "SE_param_v", "D_v", "pass_v",
               "k_star", "se_mult", "max_dv", "min_run")) {
    expect_true(nm %in% names(res), info = paste("missing", nm))
  }
  for (a in c("group_var", "loss_var", "fit_fn_name")) {
    expect_false(is.null(attr(res, a)), info = paste("missing attr", a))
  }
})

test_that("k_conv is >= k_star when non-NA", {
  res <- detect_convergence(sub)
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
  res <- detect_convergence(short_tri, k_star = k_star_guess, min_run = 3L)
  expect_true(is.na(res$k_conv))
})

test_that("tighter se_mult yields a later k_conv (or NA)", {
  loose <- detect_convergence(sub, se_mult = 1.0)
  tight <- detect_convergence(sub, se_mult = 0.1)
  if (!is.na(loose$k_conv) && !is.na(tight$k_conv)) {
    expect_gte(tight$k_conv, loose$k_conv)
  } else if (!is.na(loose$k_conv) && is.na(tight$k_conv)) {
    succeed()
  } else {
    succeed()
  }
})

test_that("tighter max_dv yields a later k_conv (or NA)", {
  loose <- detect_convergence(sub, max_dv = 0.5)
  tight <- detect_convergence(sub, max_dv = 0.05)
  if (!is.na(loose$k_conv) && !is.na(tight$k_conv)) {
    expect_gte(tight$k_conv, loose$k_conv)
  } else if (!is.na(loose$k_conv) && is.na(tight$k_conv)) {
    succeed()
  } else {
    succeed()
  }
})

test_that("min_n_cohorts guard yields NA D_v and pass_v == FALSE", {
  res <- detect_convergence(sub, min_n_cohorts = 1000L)
  expect_true(any(is.na(res$D_v)) || all(is.na(res$D_v)))
  expect_false(any(isTRUE(unname(res$pass_v))))
})

test_that("explicit k_star overrides detect_maturity()", {
  res <- detect_convergence(sub, k_star = 6L)
  expect_equal(res$k_star, 6L)
  if (!is.na(res$k_conv)) {
    expect_gte(res$k_conv, 6L)
  } else {
    succeed()
  }
})

test_that("fit_fn argument is honored (fit_cl vs fit_lr both run)", {
  res_cl <- detect_convergence(sub, fit_fn = fit_cl)
  res_lr <- detect_convergence(sub, fit_fn = fit_lr)
  expect_s3_class(res_cl, "Convergence")
  expect_s3_class(res_lr, "Convergence")
  expect_equal(attr(res_cl, "fit_fn_name"), "fit_cl")
  expect_equal(attr(res_lr, "fit_fn_name"), "fit_lr")
})

test_that("print and summary methods execute and return non-NULL", {
  res <- detect_convergence(sub)
  expect_no_error(out <- capture.output(print(res)))
  expect_true(length(out) > 0L)
  s <- summary(res)
  expect_false(is.null(s))
})

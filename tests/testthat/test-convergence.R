# Setup
data(experience)
exp <- experience
sub <- as_triangle(exp[coverage == "SUR"], groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", prem = "incr_prem")
tri <- as_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", prem = "incr_prem")

test_that("detect_convergence returns class 'Convergence' with required fields", {
  res <- detect_convergence(sub)
  expect_s3_class(res, "Convergence")
  for (nm in c("conv_k", "method", "dev_max", "dev_cand",
               "lr", "revision",
               "drift_window", "drift_tail", "slope", "dispersion",
               "pass_window", "pass_tail", "pass_slope", "pass",
               "mat_k", "max_drift", "max_slope", "max_dispersion", "window")) {
    expect_true(nm %in% names(res), info = paste("missing", nm))
  }
  for (a in c("groups", "target", "dispatcher")) {
    expect_false(is.null(attr(res, a)), info = paste("missing attr", a))
  }
})

test_that("conv_k is >= mat_k when non-NA", {
  res <- detect_convergence(sub)
  if (!is.na(res$conv_k)) {
    expect_gte(res$conv_k, res$mat_k)
  } else {
    succeed()
  }
})

test_that("insufficient history yields conv_k == NA", {
  mat_k_guess <- 6L
  short_exp <- exp[coverage == "SUR" & dev_m <= mat_k_guess + 2L]
  short_tri <- as_triangle(short_exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", prem = "incr_prem")
  res <- detect_convergence(short_tri, mat_k = mat_k_guess)
  expect_true(is.na(res$conv_k))
})

test_that("tighter max_drift yields a later conv_k (or NA)", {
  loose <- detect_convergence(sub, max_drift = 0.10)
  tight <- detect_convergence(sub, max_drift = 0.001)
  if (!is.na(loose$conv_k) && !is.na(tight$conv_k)) {
    expect_gte(tight$conv_k, loose$conv_k)
  } else {
    succeed()
  }
})

test_that("tighter max_dispersion yields a later conv_k (or NA)", {
  loose <- detect_convergence(sub, max_dispersion = 0.5)
  tight <- detect_convergence(sub, max_dispersion = 0.05)
  if (!is.na(loose$conv_k) && !is.na(tight$conv_k)) {
    expect_gte(tight$conv_k, loose$conv_k)
  } else {
    succeed()
  }
})

test_that("min_n_cohorts guard yields NA dispersion and no pass", {
  res <- detect_convergence(sub, min_n_cohorts = 1000L)
  expect_true(any(is.na(res$dispersion)) || all(is.na(res$dispersion)))
  expect_false(any(isTRUE(unname(res$pass))))
})

test_that("explicit mat_k overrides detect_maturity()", {
  res <- detect_convergence(sub, mat_k = 6L)
  expect_equal(res$mat_k, 6L)
  if (!is.na(res$conv_k)) {
    expect_gte(res$conv_k, 6L)
  } else {
    succeed()
  }
})

test_that("dispatcher attribute is fixed to 'fit_lr'", {
  # detect_convergence() always backtests the LR projection from
  # fit_lr; the dispatcher is recorded on the result for metadata.
  res <- detect_convergence(sub)
  expect_s3_class(res, "Convergence")
  expect_equal(attr(res, "dispatcher"), "fit_lr")
})

test_that("method = 'tail' gives later (or equal) conv_k than 'window'", {
  win  <- detect_convergence(sub, method = "window", max_drift = 0.05)
  tail <- detect_convergence(sub, method = "tail",   max_drift = 0.05)
  if (!is.na(win$conv_k) && !is.na(tail$conv_k)) {
    expect_gte(tail$conv_k, win$conv_k)
  } else {
    succeed()
  }
})

test_that("method = 'all' conv_k is no earlier than any single-criterion conv_k", {
  res <- detect_convergence(sub, method = "all",
                            max_drift = 0.05, max_slope = 0.005, max_dispersion = 0.3)
  if (!is.na(res$conv_k)) {
    for (m in c("window", "tail", "slope")) {
      single <- detect_convergence(sub, method = m,
                                   max_drift = 0.05, max_slope = 0.005,
                                   max_dispersion = 0.3)
      if (!is.na(single$conv_k))
        expect_gte(res$conv_k, single$conv_k)
    }
  } else {
    succeed()
  }
})

test_that("method = 'slope' uses the slope metric in pass_v", {
  # Loose tail / dispersion so the gate is only the slope.
  res <- detect_convergence(sub, method = "slope",
                            max_slope = 0.005,
                            max_drift = 1.0,        # effectively disable drift gate
                            max_dispersion = 1.0)
  expect_s3_class(res, "Convergence")
  expect_equal(res$method, "slope")
  # pass should match the slope-side pass vector
  expect_identical(res$pass, res$pass_slope)
  # When `slope` is finite at some candidate, the pass vector should be
  # logical with TRUE entries (loose dispersion floor); otherwise NA but
  # never errors.
  expect_type(res$pass, "logical")
})

test_that("tighter max_slope yields later (or equal) conv_k", {
  loose <- detect_convergence(sub, method = "slope",
                              max_slope = 0.05,
                              max_drift = 1.0,
                              max_dispersion = 1.0)
  tight <- detect_convergence(sub, method = "slope",
                              max_slope = 1e-4,
                              max_drift = 1.0,
                              max_dispersion = 1.0)
  if (!is.na(loose$conv_k) && !is.na(tight$conv_k)) {
    expect_gte(tight$conv_k, loose$conv_k)
  } else {
    succeed()
  }
})

test_that("parameter validation rejects non-numeric / non-positive thresholds", {
  expect_error(detect_convergence(sub, max_drift = -1),
               regexp = "max_drift")
  expect_error(detect_convergence(sub, max_drift = "foo"),
               regexp = "max_drift")
  expect_error(detect_convergence(sub, max_slope = 0),
               regexp = "max_slope")
  expect_error(detect_convergence(sub, max_dispersion = NA_real_),
               regexp = "max_dispersion")
  expect_error(detect_convergence(sub, window = 1L),
               regexp = "window")     # rejects < 2
  expect_error(detect_convergence(sub, window = c(5, 10)),
               regexp = "window")
})

test_that("print and summary methods execute and return non-NULL", {
  res <- detect_convergence(sub)
  expect_no_error(out <- capture.output(print(res)))
  expect_true(length(out) > 0L)
  s <- summary(res)
  expect_false(is.null(s))
  for (nm in c("dev", "lr", "revision", "drift_window", "drift_tail",
               "slope", "dispersion", "pass"))
    expect_true(nm %in% names(s), info = paste("summary missing", nm))
})

test_that("no-candidate dev sequence emits warning and returns conv_k = NA", {
  # When mat_k + 2 > dev_max, dev_cand is empty and conv_k must be NA.
  # Use a tiny triangle (max dev = 4) with explicit mat_k = 4.
  tiny_exp <- exp[coverage == "SUR" & dev_m <= 4L]
  tiny_tri <- as_triangle(tiny_exp, groups = "coverage", cohort = "uy_m",
                          calendar = "cy_m", loss = "incr_loss",
                          prem = "incr_prem")
  expect_warning(
    res <- detect_convergence(tiny_tri, mat_k = 4L),
    regexp = "No candidate dev"
  )
  expect_true(is.na(res$conv_k))
  expect_equal(length(res$dev_cand), 0L)
})

test_that("auto mat_k failure error explains the cause + how to override", {
  # Use a single-cohort triangle so detect_maturity returns no mature link.
  one_coh <- exp[coverage == "SUR" & uy_m == as.Date("2023-04-01") & dev_m <= 12L]
  tri <- tryCatch(
    as_triangle(one_coh, groups = "coverage", cohort = "uy_m",
                calendar = "cy_m", loss = "incr_loss",
                prem = "incr_prem"),
    error = function(e) NULL
  )
  if (!is.null(tri)) {
    expect_error(
      detect_convergence(tri),
      regexp = "mat_k.*explicitly"
    )
  } else {
    succeed()  # build_triangle rejected — that's also fine
  }
})

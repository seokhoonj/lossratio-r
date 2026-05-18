# Setup
data(experience)
sub <- as_triangle(experience[coverage == "surgery"],
                   groups   = "coverage",
                   cohort   = "uy_m",
                   calendar = "cy_m",
                   loss     = "incr_loss",
                   exposure = "incr_exposure")


test_that("fit_bf returns class 'BFFit' with scalar prior", {
  fit <- fit_bf(sub, prior = 0.7)
  expect_s3_class(fit, "BFFit")
  expect_equal(fit$method, "bf")
  expect_true(all(fit$prior$elr == 0.7))
})

test_that("fit_bf $summary carries cohort-level BF reserve", {
  fit <- fit_bf(sub, prior = 0.7)
  needed <- c("cohort", "latest", "loss_ult", "reserve", "elr", "q")
  for (nm in needed) expect_true(nm %in% names(fit$summary))
  # ult >= latest (positive reserve when q < 1) for all cohorts
  expect_true(all(fit$summary$loss_ult >= fit$summary$latest -
                    1e-6 * abs(fit$summary$latest)))
  # reserve = (1 - q) * elr * exposure_ult on the BF formula
  # (sanity: reserve > 0 when q < 1)
  with_dev <- fit$summary[fit$summary$q < 1, ]
  expect_true(all(with_dev$reserve > 0))
})

test_that("fit_bf accepts a data.frame prior with per-cohort ELR", {
  cohorts <- unique(sub$cohort)
  set.seed(1)
  prior_tbl <- data.frame(
    cohort = cohorts,
    elr    = runif(length(cohorts), 0.5, 1.5)
  )
  fit <- fit_bf(sub, prior = prior_tbl)
  expect_s3_class(fit, "BFFit")
  # resolved prior matches input order (after re-key)
  setkey_dt <- data.table::as.data.table(prior_tbl)
  setkey_fit <- data.table::as.data.table(fit$prior)
  data.table::setkey(setkey_dt,  cohort)
  data.table::setkey(setkey_fit, cohort)
  expect_equal(setkey_fit$elr, setkey_dt$elr)
})

test_that("fit_bf errors when prior is missing", {
  expect_error(fit_bf(sub), regexp = "`prior` is required")
})

test_that("fit_bf errors on incomplete prior data.frame", {
  cohorts <- unique(sub$cohort)
  partial <- data.frame(cohort = cohorts[1:3], elr = 0.7)
  expect_error(fit_bf(sub, prior = partial),
               regexp = "missing ELR")
})

test_that("fit_bf $full has cell-level BF projection columns", {
  fit <- fit_bf(sub, prior = 0.7)
  for (nm in c("loss_obs", "loss_proj", "exposure_proj",
               "is_observed", "incr_loss_proj")) {
    expect_true(nm %in% names(fit$full), info = paste("missing", nm))
  }
})

test_that("fit_bf $proj NA's out observed cells", {
  fit <- fit_bf(sub, prior = 0.7)
  n_full_na <- sum(is.na(fit$full$loss_proj))
  n_proj_na <- sum(is.na(fit$proj$loss_proj))
  expect_gt(n_proj_na, n_full_na)
})

test_that("fit_bf with q = 1 cohort produces zero reserve", {
  fit <- fit_bf(sub, prior = 0.7)
  fully_emerged <- fit$summary[fit$summary$q == 1, ]
  if (nrow(fully_emerged) > 0L) {
    expect_true(all(abs(fully_emerged$reserve) < 1e-3))
  } else {
    succeed()  # no q == 1 cohort to test
  }
})

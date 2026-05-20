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

test_that("fit_bf accepts a per-group data.frame prior (no cohort column)", {
  multi <- as_triangle(experience[coverage %in% c("surgery", "ci")],
                       groups   = "coverage",
                       cohort   = "uy_m",
                       calendar = "cy_m",
                       loss     = "incr_loss",
                       exposure = "incr_exposure")
  prior_grp <- data.frame(
    coverage = c("surgery", "ci"),
    elr      = c(0.70, 0.85)
  )
  fit <- fit_bf(multi, prior = prior_grp)
  expect_s3_class(fit, "BFFit")
  # each group's ELR broadcast to every cohort in that group
  resolved <- data.table::as.data.table(fit$prior)
  expect_equal(unique(resolved[coverage == "surgery"]$elr), 0.70)
  expect_equal(unique(resolved[coverage == "ci"]$elr), 0.85)
  expect_true(nrow(resolved) > 2L)
})

test_that("fit_bf errors on a per-group prior missing a group", {
  multi <- as_triangle(experience[coverage %in% c("surgery", "ci")],
                       groups   = "coverage",
                       cohort   = "uy_m",
                       calendar = "cy_m",
                       loss     = "incr_loss",
                       exposure = "incr_exposure")
  prior_grp <- data.frame(coverage = "surgery", elr = 0.70)
  expect_error(fit_bf(multi, prior = prior_grp), regexp = "missing ELR")
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

test_that("fit_bf accepts a distribution prior (elr_se column)", {
  cohorts <- unique(sub$cohort)
  prior_dist <- data.frame(cohort = cohorts, elr = 0.8, elr_se = 0.1)
  fit <- fit_bf(sub, prior = prior_dist)
  expect_s3_class(fit, "BFFit")
  expect_true("elr_se" %in% names(fit$prior))
  expect_true(all(fit$prior$elr_se == 0.1))
})

test_that("fit_bf $prior carries NA elr_se for a deterministic prior", {
  fit <- fit_bf(sub, prior = 0.7)
  expect_true("elr_se" %in% names(fit$prior))
  expect_true(all(is.na(fit$prior$elr_se)))
})

test_that("fit_bf rejects a negative elr_se", {
  cohorts <- unique(sub$cohort)
  bad <- data.frame(cohort = cohorts, elr = 0.8, elr_se = -0.1)
  expect_error(fit_bf(sub, prior = bad), regexp = "non-negative")
})

test_that("distribution prior widens bootstrap SE vs deterministic prior", {
  cohorts <- unique(sub$cohort)
  prior_det  <- data.frame(cohort = cohorts, elr = 0.8)
  prior_dist <- data.frame(cohort = cohorts, elr = 0.8, elr_se = 0.15)
  fit_det  <- fit_bf(sub, prior = prior_det,  bootstrap = "auto",
                     B = 200, seed = 1)
  fit_dist <- fit_bf(sub, prior = prior_dist, bootstrap = "auto",
                     B = 200, seed = 1)
  # the per-replicate ELR draw injects extra variance into the ultimate
  se_det  <- sum(fit_det$summary$loss_total_se,  na.rm = TRUE)
  se_dist <- sum(fit_dist$summary$loss_total_se, na.rm = TRUE)
  expect_gt(se_dist, se_det)
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


# Phase 3a -- peer worker arg propagation -----------------------------------

test_that("fit_bf forwards alpha to the inner fit_cl", {
  fit_a1 <- fit_bf(sub, prior = 0.7, alpha = 1)
  fit_a0 <- fit_bf(sub, prior = 0.7, alpha = 0.5)
  expect_false(isTRUE(all.equal(fit_a1$cl_fit$selected$f_sel,
                                fit_a0$cl_fit$selected$f_sel)))
})

test_that("fit_bf forwards recent to the inner fit_cl", {
  fit_all    <- fit_bf(sub, prior = 0.7)
  fit_recent <- fit_bf(sub, prior = 0.7, recent = 6L)
  # recent narrows the calendar wedge -- some factor rows estimate from
  # fewer cohorts.
  any_smaller <- any(fit_recent$cl_fit$selected$n_cohorts <
                     fit_all$cl_fit$selected$n_cohorts[match(
                       fit_recent$cl_fit$selected$ata_from,
                       fit_all$cl_fit$selected$ata_from)],
                     na.rm = TRUE)
  expect_true(any_smaller)
})

test_that("fit_bf forwards regime to the inner fit_cl", {
  reg <- regime_at(change = as.Date("2024-07-01"))
  fit <- fit_bf(sub, prior = 0.7, regime = reg)
  expect_s3_class(fit$regime, "Regime")
})

test_that("fit_bf maturity = 'auto' is stored on $maturity", {
  fit <- fit_bf(sub, prior = 0.7, maturity = "auto")
  expect_true(!is.null(fit$maturity))
})

test_that("fit_bf $full schema intersects LossFit", {
  bf <- fit_bf(sub, prior = 0.7)
  lf <- fit_loss(sub)
  common <- intersect(names(bf$full), names(lf$full))
  for (nm in c("cohort", "dev", "loss_obs", "loss_proj", "is_observed"))
    expect_true(nm %in% common)
})

test_that("fit_bf supports multi-group $summary", {
  tri_mg <- as_triangle(experience, groups = "coverage",
                       cohort = "uy_m", calendar = "cy_m",
                       loss = "incr_loss", exposure = "incr_exposure")
  fit <- fit_bf(tri_mg, prior = 0.7)
  expect_true("coverage" %in% names(fit$summary))
  expect_gte(length(unique(fit$summary$coverage)), 2L)
})


# Phase 3b -- bootstrap composition ----------------------------------------

test_that("fit_bf bootstrap = TRUE produces ci_type = 'bootstrap'", {
  fit <- fit_bf(sub, prior = 0.7, bootstrap = TRUE, B = 30, seed = 1)
  expect_equal(fit$ci_type, "bootstrap")
  expect_s3_class(fit$bootstrap, "BFBootstrap")
  expect_equal(fit$bootstrap$B, 30L)
})

test_that("fit_bf bootstrap populates SE/CI on projected cells", {
  fit <- fit_bf(sub, prior = 0.7, bootstrap = TRUE, B = 30, seed = 1)
  for (nm in c("loss_total_se", "loss_total_cv",
               "loss_ci_lo", "loss_ci_hi"))
    expect_true(nm %in% names(fit$full), info = nm)
  proj_cells <- fit$full[is_observed == FALSE]
  expect_true(any(is.finite(proj_cells$loss_total_se)))
  expect_true(all(proj_cells$loss_total_se >= 0, na.rm = TRUE))
})

test_that("fit_bf bootstrap with same seed is reproducible", {
  f1 <- fit_bf(sub, prior = 0.7, bootstrap = TRUE, B = 30, seed = 42)
  f2 <- fit_bf(sub, prior = 0.7, bootstrap = TRUE, B = 30, seed = 42)
  expect_equal(f1$summary$loss_total_se, f2$summary$loss_total_se)
  expect_equal(f1$summary$loss_ci_lo, f2$summary$loss_ci_lo)
})

test_that("fit_bf bootstrap type = 'nonparametric' works", {
  fit <- fit_bf(sub, prior = 0.7, bootstrap = TRUE, B = 30, seed = 1,
                type = "nonparametric", residual = "cell")
  expect_equal(fit$ci_type, "bootstrap")
  expect_true(any(is.finite(fit$summary$loss_total_se)))
})

test_that("fit_bf bootstrap type = 'analytical' errors", {
  expect_error(
    fit_bf(sub, prior = 0.7, bootstrap = TRUE, B = 30,
           type = "analytical"),
    regexp = "not yet implemented"
  )
})

test_that("fit_bf accepts a pre-built bootstrap pair", {
  bt_loss <- bootstrap(sub, type = "parametric", method = "cl",
                       target = "loss", B = 25, seed = 7,
                       keep_pseudo = TRUE)
  bt_exp <- bootstrap(sub, type = "parametric", method = "cl",
                      target = "exposure", B = 25, seed = 7,
                      keep_pseudo = TRUE)
  fit <- fit_bf(sub, prior = 0.7,
                bootstrap = list(loss = bt_loss, exposure = bt_exp))
  expect_equal(fit$ci_type, "bootstrap")
  expect_equal(fit$bootstrap$B, 25L)
  # wrong target rejected
  expect_error(
    fit_bf(sub, prior = 0.7,
           bootstrap = list(loss = bt_exp, exposure = bt_exp)),
    regexp = "target"
  )
})

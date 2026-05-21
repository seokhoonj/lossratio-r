# Setup
data(experience)
sub <- as_triangle(experience[coverage == "surgery"],
                   groups   = "coverage",
                   cohort   = "uy_m",
                   calendar = "cy_m",
                   loss     = "incr_loss",
                   premium  = "incr_premium")


test_that("fit_cc returns class 'CCFit'", {
  fit <- fit_cc(sub)
  expect_s3_class(fit, "CCFit")
  expect_equal(fit$method, "cc")
})

test_that("fit_cc classical (credibility = NULL) has no credibility slot", {
  fit <- fit_cc(sub)
  expect_null(fit$credibility)
})

test_that("fit_cc credibility = 'bs' returns per-cohort Z weights", {
  fit <- fit_cc(sub, credibility = list(method = "bs"))
  expect_false(is.null(fit$credibility))
  expect_equal(fit$credibility$method, "bs")
  w <- fit$credibility$weights
  expect_true(all(c("Z", "K") %in% names(w)))
  expect_true(all(w$Z >= 0 & w$Z <= 1, na.rm = TRUE))
  expect_equal(fit$ci_type, "analytical")
})

test_that("fit_cc credibility: Z rises with cohort maturity", {
  fit <- fit_cc(sub, credibility = list(method = "bs"))
  w <- fit$credibility$weights[order(fit$credibility$weights$cohort), ]
  expect_gt(mean(utils::head(w$Z, 5)), mean(utils::tail(w$Z, 5)))
})

test_that("fit_cc type='analytical' fills SE / CI + pooled-ELR columns", {
  fit <- fit_cc(sub, type = "analytical")
  expect_equal(fit$ci_type, "analytical")
  for (nm in c("loss_total_se", "loss_total_cv", "loss_ci_lo", "loss_ci_hi",
               "elr_cc_se", "elr_cc_cv", "elr_cc_ci_lo", "elr_cc_ci_hi"))
    expect_true(nm %in% names(fit$summary))
  expect_true(all(fit$summary$loss_total_se >= 0, na.rm = TRUE))
  # one pooled ELR -> one elr_cc_se shared across the group's cohorts
  expect_equal(length(unique(fit$summary$elr_cc_se)), 1L)
})

test_that("fit_cc analytical works with multiple groups", {
  multi <- as_triangle(experience[coverage %in% c("surgery", "ci")],
                       groups   = "coverage",
                       cohort   = "uy_m",
                       calendar = "cy_m",
                       loss     = "incr_loss",
                       premium  = "incr_premium")
  fit <- fit_cc(multi, type = "analytical")
  expect_equal(fit$ci_type, "analytical")
  expect_true(all(c("loss_total_se", "elr_cc_se") %in% names(fit$summary)))
  # each group carries its own pooled-ELR SE
  expect_equal(length(unique(fit$summary$elr_cc_se)), 2L)
})

test_that("fit_cc produces a single pooled ELR per group", {
  fit <- fit_cc(sub)
  expect_true("elr_cc" %in% names(fit$elr_cc))
  expect_equal(nrow(fit$elr_cc), 1L)   # single group
  expect_gt(fit$elr_cc$elr_cc, 0)
})

test_that("fit_cc $summary uses the pooled ELR for every cohort", {
  fit <- fit_cc(sub)
  elr_cc <- fit$elr_cc$elr_cc[1L]
  expect_true(all(abs(fit$summary$elr - elr_cc) < 1e-10))
})

test_that("fit_cc reserve is non-negative for non-fully-emerged cohorts", {
  fit <- fit_cc(sub)
  with_dev <- fit$summary[fit$summary$q < 1, ]
  expect_true(all(with_dev$reserve >= 0))
})

test_that("fit_cc $full and $proj match the BFFit cell layout", {
  fit <- fit_cc(sub)
  for (nm in c("loss_obs", "loss_proj", "premium_proj",
               "is_observed", "incr_loss_proj")) {
    expect_true(nm %in% names(fit$full), info = paste("missing", nm))
  }
  n_full_na <- sum(is.na(fit$full$loss_proj))
  n_proj_na <- sum(is.na(fit$proj$loss_proj))
  expect_gt(n_proj_na, n_full_na)
})

test_that("fit_cc pooled ELR matches the Stanard 1985 closed form", {
  fit <- fit_cc(sub)
  # Reproduce the Cape Cod ELR directly from the underlying CL and
  # premium fits to make sure the formula is implemented as documented.
  cl_fit  <- fit$cl_fit
  exp_fit <- fit$premium_fit
  by_cols <- c(fit$groups, "cohort")

  loss_latest <- cl_fit$full[is_observed == TRUE,
                              .SD[.N, .(L = loss_obs)],
                              by = by_cols]
  loss_ult_cl <- cl_fit$full[, .SD[.N, .(L_ult = loss_proj)],
                              by = by_cols]
  q_dt <- loss_latest[loss_ult_cl, on = by_cols]
  q_dt[, q := L / L_ult]
  exp_ult <- exp_fit$full[, .SD[.N, .(E = premium_proj)],
                          by = by_cols]
  q_dt <- exp_ult[q_dt, on = by_cols]

  expected_elr <- sum(q_dt$L, na.rm = TRUE) /
                  sum(q_dt$E * q_dt$q, na.rm = TRUE)
  expect_equal(fit$elr_cc$elr_cc[1L], expected_elr, tolerance = 1e-10)
})


# Phase 3a -- peer worker arg propagation -----------------------------------

test_that("fit_cc forwards alpha to the inner fit_cl", {
  f1 <- fit_cc(sub, alpha = 1)
  f0 <- fit_cc(sub, alpha = 0.5)
  expect_false(isTRUE(all.equal(f1$cl_fit$selected$f_sel,
                                f0$cl_fit$selected$f_sel)))
})

test_that("fit_cc forwards recent to the inner fit_cl", {
  fit_all    <- fit_cc(sub)
  fit_recent <- fit_cc(sub, recent = 6L)
  any_smaller <- any(fit_recent$cl_fit$selected$n_cohorts <
                     fit_all$cl_fit$selected$n_cohorts[match(
                       fit_recent$cl_fit$selected$ata_from,
                       fit_all$cl_fit$selected$ata_from)],
                     na.rm = TRUE)
  expect_true(any_smaller)
})

test_that("fit_cc forwards regime to the inner fit_cl", {
  reg <- regime_at(change = as.Date("2024-07-01"))
  fit <- fit_cc(sub, regime = reg)
  expect_s3_class(fit$regime, "Regime")
})

test_that("fit_cc $full schema intersects LossFit", {
  cc <- fit_cc(sub)
  lf <- fit_loss(sub)
  common <- intersect(names(cc$full), names(lf$full))
  for (nm in c("cohort", "dev", "loss_obs", "loss_proj", "is_observed"))
    expect_true(nm %in% common)
})

test_that("fit_cc supports multi-group $summary", {
  tri_mg <- as_triangle(experience, groups = "coverage",
                       cohort = "uy_m", calendar = "cy_m",
                       loss = "incr_loss", premium = "incr_premium")
  fit <- fit_cc(tri_mg)
  expect_true("coverage" %in% names(fit$summary))
  expect_gte(length(unique(fit$summary$coverage)), 2L)
  expect_equal(nrow(fit$elr_cc), length(unique(fit$summary$coverage)))
})


# Phase 3b -- bootstrap composition ----------------------------------------

test_that("fit_cc bootstrap = TRUE produces ci_type = 'bootstrap'", {
  fit <- fit_cc(sub, bootstrap = TRUE, B = 30, seed = 1)
  expect_equal(fit$ci_type, "bootstrap")
  expect_s3_class(fit$bootstrap, "CCBootstrap")
  expect_equal(fit$bootstrap$B, 30L)
  expect_true("elr_cc_replicates" %in% names(fit$bootstrap))
})

test_that("fit_cc bootstrap populates SE/CI on cells + ELR", {
  fit <- fit_cc(sub, bootstrap = TRUE, B = 30, seed = 1)
  for (nm in c("loss_total_se", "loss_total_cv",
               "loss_ci_lo", "loss_ci_hi"))
    expect_true(nm %in% names(fit$full), info = nm)
  for (nm in c("elr_cc_se", "elr_cc_cv",
               "elr_cc_ci_lo", "elr_cc_ci_hi"))
    expect_true(nm %in% names(fit$summary), info = nm)
  expect_true(all(fit$summary$elr_cc_se >= 0, na.rm = TRUE))
})

test_that("fit_cc bootstrap with same seed is reproducible", {
  f1 <- fit_cc(sub, bootstrap = TRUE, B = 30, seed = 42)
  f2 <- fit_cc(sub, bootstrap = TRUE, B = 30, seed = 42)
  expect_equal(f1$summary$loss_total_se, f2$summary$loss_total_se)
  expect_equal(f1$summary$elr_cc_se, f2$summary$elr_cc_se)
})

test_that("fit_cc bootstrap type = 'nonparametric' works", {
  fit <- fit_cc(sub, bootstrap = TRUE, B = 30, seed = 1,
                     type = "nonparametric", residual = "cell")
  expect_equal(fit$ci_type, "bootstrap")
  expect_true(any(is.finite(fit$summary$loss_total_se)))
})

test_that("fit_cc type = 'analytical' takes precedence over bootstrap", {
  # `type = "analytical"` forces the closed-form path even when a
  # bootstrap is requested.
  fit <- fit_cc(sub, bootstrap = TRUE, B = 30, type = "analytical")
  expect_equal(fit$ci_type, "analytical")
  expect_null(fit$bootstrap)
})

test_that("fit_cc accepts a pre-built bootstrap pair", {
  bt_loss <- bootstrap(sub, type = "parametric", method = "cl",
                       target = "loss", B = 25, seed = 7,
                       keep_pseudo = TRUE)
  bt_exp <- bootstrap(sub, type = "parametric", method = "cl",
                      target = "premium", B = 25, seed = 7,
                      keep_pseudo = TRUE)
  fit <- fit_cc(sub,
                     bootstrap = list(loss = bt_loss, premium = bt_exp))
  expect_equal(fit$ci_type, "bootstrap")
  expect_equal(fit$bootstrap$B, 25L)
  expect_error(
    fit_cc(sub,
                bootstrap = list(loss = bt_exp, premium = bt_exp)),
    regexp = "target"
  )
})

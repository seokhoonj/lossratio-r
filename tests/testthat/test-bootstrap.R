# Tests for the new Triangle-level bootstrap worker (Phase 1).
#
# Scope:
#   - bootstrap() S3 generic + bootstrap.Triangle() method
#   - print.BootstrapTriangle()
#   - Legacy .cl_bootstrap / .ed_bootstrap / .sa_bootstrap helpers are
#     intentionally NOT covered here -- they remain in use by
#     fit_lr/fit_loss/fit_premium/backtest until Phase 2 migration.

# ---------------------------------------------------------------------------
# Basic structure
# ---------------------------------------------------------------------------

test_that("bootstrap.Triangle returns BootstrapTriangle with expected slots", {
  tri <- make_sub_tri("SUR")
  b <- bootstrap(tri, method = "residual", mode = "dev", B = 20, seed = 1)

  expect_s3_class(b, "BootstrapTriangle")
  for (nm in c("alt_triangles", "residual_pool", "f_anchor",
               "sigma2_anchor", "meta")) {
    expect_true(nm %in% names(b), info = paste("missing", nm))
  }
})

test_that("meta records all configured arguments", {
  tri <- make_sub_tri("SUR")
  b <- bootstrap(tri, method = "residual", mode = "pooled",
                  process = "gamma", B = 17L, seed = 42, alpha = 1)
  m <- b$meta
  expect_identical(m$method,  "residual")
  expect_identical(m$mode,    "pooled")
  expect_identical(m$process, "gamma")
  expect_identical(m$B,       17L)
  expect_identical(m$seed,    42)
  expect_identical(m$alpha,   1)
  expect_identical(m$target,  "loss")
})


# ---------------------------------------------------------------------------
# alt_triangles long-format shape
# ---------------------------------------------------------------------------

test_that("alt_triangles has [cohort × dev × B] rows per group", {
  tri <- make_sub_tri("SUR")
  n_coh <- length(unique(tri$cohort))
  n_dev <- length(unique(tri$dev))
  B     <- 20L

  b <- bootstrap(tri, method = "residual", B = B, seed = 1)
  expect_equal(nrow(b$alt_triangles), n_coh * n_dev * B)
  expect_true(all(c("coverage", "cohort", "dev", "rep", "loss") %in%
                    names(b$alt_triangles)))
  expect_equal(sort(unique(b$alt_triangles$rep)), seq_len(B))
})

test_that("alt_triangles multi-group splits evenly per group", {
  tri <- make_tri()
  B <- 10L
  b <- bootstrap(tri, method = "residual", B = B, seed = 1)
  counts <- b$alt_triangles[, .N, by = coverage]
  expect_true(all(counts$N == counts$N[1L]))
})


# ---------------------------------------------------------------------------
# Seed reproducibility
# ---------------------------------------------------------------------------

test_that("same seed reproduces identical alt_triangles (residual)", {
  tri <- make_sub_tri("SUR")
  a <- bootstrap(tri, method = "residual", B = 30, seed = 7)$alt_triangles$loss
  b <- bootstrap(tri, method = "residual", B = 30, seed = 7)$alt_triangles$loss
  expect_identical(a, b)
})

test_that("different seeds give different draws (residual)", {
  tri <- make_sub_tri("SUR")
  a <- bootstrap(tri, method = "residual", B = 30, seed = 7)$alt_triangles$loss
  b <- bootstrap(tri, method = "residual", B = 30, seed = 8)$alt_triangles$loss
  expect_false(identical(a, b))
})

test_that("same seed reproduces identical alt_triangles (parametric)", {
  tri <- make_sub_tri("SUR")
  a <- bootstrap(tri, method = "parametric", B = 30, seed = 7)$alt_triangles$loss
  b <- bootstrap(tri, method = "parametric", B = 30, seed = 7)$alt_triangles$loss
  expect_identical(a, b)
})


# ---------------------------------------------------------------------------
# method = "parametric" preserves observed cells
# ---------------------------------------------------------------------------

test_that("parametric method preserves observed cells across replicates", {
  tri <- make_sub_tri("SUR")
  b <- bootstrap(tri, method = "parametric", B = 30, seed = 1)
  obs <- tri[1L]
  matched <- b$alt_triangles[
    cohort == obs$cohort & dev == obs$dev, loss
  ]
  expect_length(unique(matched), 1L)
  expect_equal(matched[1L], obs$loss)
})


# ---------------------------------------------------------------------------
# mode-specific pool structure
# ---------------------------------------------------------------------------

test_that("mode = 'dev' gives one pool per (group, ata_to)", {
  tri <- make_sub_tri("SUR")
  b <- bootstrap(tri, method = "residual", mode = "dev", B = 5, seed = 1)
  n_links <- nrow(b$f_anchor)
  expect_equal(length(unique(b$residual_pool$pool_id)), n_links)
})

test_that("mode = 'pooled' single-group gives one pool", {
  tri <- make_sub_tri("SUR")
  b <- bootstrap(tri, method = "residual", mode = "pooled", B = 5, seed = 1)
  expect_equal(length(unique(b$residual_pool$pool_id)), 1L)
})

test_that("mode = 'pooled' multi-group gives one pool per group", {
  tri <- make_tri()
  b <- bootstrap(tri, method = "residual", mode = "pooled", B = 5, seed = 1)
  expect_equal(length(unique(b$residual_pool$pool_id)),
               length(unique(tri$coverage)))
})

test_that("mode = 'dev_maturity' requires non-null maturity", {
  tri <- make_sub_tri("SUR")
  expect_error(
    bootstrap(tri, method = "residual", mode = "dev_maturity",
              maturity = NULL, B = 5, seed = 1),
    "maturity"
  )
})

test_that("mode = 'dev_maturity' with 'auto' produces POST + per-dev pools", {
  tri <- make_sub_tri("SUR")
  b <- bootstrap(tri, method = "residual", mode = "dev_maturity",
                  maturity = "auto", B = 5, seed = 1)
  pool_ids <- unique(b$residual_pool$pool_id)
  # Expect at least one POST bucket and at least one per-dev bucket
  expect_true(any(grepl("POST$", pool_ids)))
  expect_true(any(!grepl("POST$", pool_ids)))
})


# ---------------------------------------------------------------------------
# Bootstrap-induced variability for projected cells
# ---------------------------------------------------------------------------

test_that("residual bootstrap induces variability in projected cells", {
  tri <- make_sub_tri("SUR")
  b <- bootstrap(tri, method = "residual", B = 200, seed = 1)
  cohorts <- sort(unique(b$alt_triangles$cohort))
  last_coh <- cohorts[length(cohorts)]
  devs <- sort(unique(b$alt_triangles$dev))
  late_dev <- devs[length(devs) - 1L]
  vals <- b$alt_triangles[cohort == last_coh & dev == late_dev, loss]
  expect_true(is.finite(stats::sd(vals)))
  expect_gt(stats::sd(vals), 0)
})

test_that("parametric bootstrap induces variability in projected cells", {
  tri <- make_sub_tri("SUR")
  b <- bootstrap(tri, method = "parametric", B = 200, seed = 1)
  cohorts <- sort(unique(b$alt_triangles$cohort))
  last_coh <- cohorts[length(cohorts)]
  devs <- sort(unique(b$alt_triangles$dev))
  late_dev <- devs[length(devs) - 1L]
  vals <- b$alt_triangles[cohort == last_coh & dev == late_dev, loss]
  expect_true(is.finite(stats::sd(vals)))
  expect_gt(stats::sd(vals), 0)
})


# ---------------------------------------------------------------------------
# f_anchor / sigma2_anchor structure
# ---------------------------------------------------------------------------

test_that("f_anchor has expected columns and one row per link", {
  tri <- make_sub_tri("SUR")
  b <- bootstrap(tri, method = "residual", B = 5, seed = 1)
  for (nm in c("coverage", "ata_from", "ata_to", "f_hat", "n_cohorts")) {
    expect_true(nm %in% names(b$f_anchor), info = paste("missing", nm))
  }
  expect_true(all(is.finite(b$f_anchor$f_hat)))
  expect_true(all(b$f_anchor$n_cohorts >= 1L))
})

test_that("sigma2_anchor has expected columns and non-negative sigma2", {
  tri <- make_sub_tri("SUR")
  b <- bootstrap(tri, method = "residual", B = 5, seed = 1)
  for (nm in c("coverage", "ata_from", "ata_to", "sigma2", "f_var")) {
    expect_true(nm %in% names(b$sigma2_anchor), info = paste("missing", nm))
  }
  expect_true(all(b$sigma2_anchor$sigma2 >= 0 |
                    is.na(b$sigma2_anchor$sigma2)))
})


# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

test_that("invalid B raises an error", {
  tri <- make_sub_tri("SUR")
  expect_error(bootstrap(tri, B = 0),    "B")
  expect_error(bootstrap(tri, B = -1),   "B")
  expect_error(bootstrap(tri, B = NA),   "B")
  expect_error(bootstrap(tri, B = "10"), "B")
})

test_that("invalid alpha raises an error", {
  tri <- make_sub_tri("SUR")
  expect_error(bootstrap(tri, alpha = NA),    "alpha")
  expect_error(bootstrap(tri, alpha = "1"),   "alpha")
})

test_that("invalid seed raises an error", {
  tri <- make_sub_tri("SUR")
  expect_error(bootstrap(tri, seed = "x"),  "seed")
  expect_error(bootstrap(tri, seed = c(1, 2)), "seed")
})

test_that("invalid method/mode/process raise match.arg errors", {
  tri <- make_sub_tri("SUR")
  expect_error(bootstrap(tri, method  = "wrong"))
  expect_error(bootstrap(tri, mode    = "wrong"))
  expect_error(bootstrap(tri, process = "wrong"))
})


# ---------------------------------------------------------------------------
# print method
# ---------------------------------------------------------------------------

test_that("print.BootstrapTriangle prints all configured fields", {
  tri <- make_sub_tri("SUR")
  b <- bootstrap(tri, method = "residual", mode = "dev",
                  process = "gamma", B = 5, seed = 1)
  out <- utils::capture.output(print(b))
  expect_true(any(grepl("BootstrapTriangle", out)))
  expect_true(any(grepl("method", out)))
  expect_true(any(grepl("residual", out)))
  expect_true(any(grepl("dev", out)))
  expect_true(any(grepl("gamma", out)))
  expect_true(any(grepl("5 replicates", out)))
})


# ---------------------------------------------------------------------------
# Phase 2a consumer helpers
# ---------------------------------------------------------------------------

test_that(".resolve_bootstrap dispatches NULL / FALSE / TRUE / 'auto' / obj / fn", {
  tri <- make_sub_tri("SUR")

  expect_null(.resolve_bootstrap(NULL,  tri, B = 5, seed = 1))
  expect_null(.resolve_bootstrap(FALSE, tri, B = 5, seed = 1))

  b1 <- .resolve_bootstrap(TRUE,   tri, B = 5, seed = 1)
  b2 <- .resolve_bootstrap("auto", tri, B = 5, seed = 1)
  expect_s3_class(b1, "BootstrapTriangle")
  expect_s3_class(b2, "BootstrapTriangle")
  expect_identical(b1$meta$B, 5L)

  b_obj <- bootstrap(tri, B = 5, seed = 1)
  expect_identical(.resolve_bootstrap(b_obj, tri), b_obj)

  fn <- function(t) bootstrap(t, B = 3, seed = 1, method = "residual")
  b_fn <- .resolve_bootstrap(fn, tri)
  expect_identical(b_fn$meta$B, 3L)
  expect_identical(b_fn$meta$method, "residual")
})

test_that(".resolve_bootstrap rejects bad input", {
  tri <- make_sub_tri("SUR")
  expect_error(.resolve_bootstrap("garbage", tri), "must be NULL")
  expect_error(.resolve_bootstrap(function(t) 42, tri), "BootstrapTriangle")
})


test_that(".boot_refit returns same shape for all methods", {
  tri <- make_sub_tri("SUR")
  boots <- bootstrap(tri, B = 30, seed = 1)
  mat   <- detect_maturity(tri)

  r_cl <- .boot_refit(tri, boots, method = "cl", alpha = 1)
  r_ed <- .boot_refit(tri, boots, method = "ed", alpha = 1)
  r_sa <- .boot_refit(tri, boots, method = "sa", alpha = 1, maturity = mat)

  for (rdt in list(r_cl, r_ed, r_sa)) {
    expect_true(all(c("coverage", "cohort", "dev", "rep",
                      "cell_mean", "cell_proc_var") %in% names(rdt)))
    expect_equal(nrow(rdt), length(unique(tri$cohort)) *
                              length(unique(tri$dev)) * 30L)
    expect_true(all(rdt$cell_proc_var >= 0 | is.na(rdt$cell_proc_var)))
  }
})

test_that(".boot_refit(method='cl') observed cells have cell_proc_var = 0", {
  tri <- make_sub_tri("SUR")
  boots <- bootstrap(tri, B = 10, seed = 1)
  r_cl  <- .boot_refit(tri, boots, method = "cl", alpha = 1)

  # Pick an obviously-observed cell: cohort 2023-01-01 dev 1.
  cells <- r_cl[cohort == as.Date("2023-01-01") & dev == 1L]
  expect_equal(unique(cells$cell_proc_var), 0)
})

test_that(".boot_refit(method='cl') projected cells have positive cell_proc_var", {
  tri <- make_sub_tri("SUR")
  boots <- bootstrap(tri, B = 30, seed = 1)
  r_cl  <- .boot_refit(tri, boots, method = "cl", alpha = 1)

  # Pick a clearly-projected cell: latest cohort, dev near the tail.
  cells <- r_cl[cohort == as.Date("2025-12-01") & dev == 10L]
  expect_true(all(cells$cell_proc_var > 0 | !is.finite(cells$cell_mean)))
})


test_that(".boot_add_process_noise leaves observed cells untouched", {
  tri <- make_sub_tri("SUR")
  boots <- bootstrap(tri, B = 10, seed = 1)
  r_cl  <- .boot_refit(tri, boots, method = "cl", alpha = 1)

  withn <- .boot_add_process_noise(r_cl, "normal")
  obs_rows <- withn[cell_proc_var == 0]
  expect_equal(obs_rows$cell_real, obs_rows$cell_mean)
})

test_that(".boot_add_process_noise normal vs gamma both finite", {
  tri <- make_sub_tri("SUR")
  boots <- bootstrap(tri, B = 30, seed = 1)
  r_cl  <- .boot_refit(tri, boots, method = "cl", alpha = 1)

  set.seed(1)
  wn_norm  <- .boot_add_process_noise(r_cl, "normal")
  set.seed(1)
  wn_gamma <- .boot_add_process_noise(r_cl, "gamma")
  set.seed(1)
  wn_odp   <- .boot_add_process_noise(r_cl, "odp")

  # All produce finite cell_real where cell_mean is finite
  for (wn in list(wn_norm, wn_gamma, wn_odp)) {
    ok <- is.finite(wn$cell_mean) & wn$cell_proc_var > 0
    expect_true(all(is.finite(wn$cell_real[ok])))
  }

  # Gamma / ODP produce non-negative cell_real for positive-mean projected cells
  pos_gamma <- wn_gamma[is.finite(cell_mean) & cell_mean > 0 & cell_proc_var > 0]
  expect_true(all(pos_gamma$cell_real >= 0))
  pos_odp <- wn_odp[is.finite(cell_mean) & cell_mean > 0 & cell_proc_var > 0]
  expect_true(all(pos_odp$cell_real >= 0))
})


test_that(".boot_summarize_se produces expected columns and SE decomposition", {
  tri <- make_sub_tri("SUR")
  boots <- bootstrap(tri, B = 50, seed = 1)
  r_cl  <- .boot_refit(tri, boots, method = "cl", alpha = 1)
  wn    <- .boot_add_process_noise(r_cl, "normal")
  se    <- .boot_summarize_se(wn, grp = "coverage")

  expect_true(all(c("coverage", "cohort", "dev",
                    "target_proj", "target_proc_se", "target_param_se",
                    "target_total_se", "target_total_cv",
                    "target_ci_lo", "target_ci_hi") %in% names(se)))

  expect_equal(nrow(se),
               length(unique(tri$cohort)) * length(unique(tri$dev)))

  # SE decomposition: total^2 = proc^2 + param^2 (exact by construction
  # of proc_se = sqrt(max(total^2 - param^2, 0))). Use relative tolerance
  # because squared SE values can be huge (losses in tens of millions).
  proj <- se[target_proc_se > 0]
  if (nrow(proj) > 0L) {
    decomp <- proj$target_proc_se^2 + proj$target_param_se^2
    rel_err <- abs(proj$target_total_se^2 - decomp) /
               pmax(proj$target_total_se^2, 1e-12)
    expect_true(all(rel_err < 1e-9))
  }

  # Observed cells: SE = 0 for parametric (data unchanged); SE = param_se
  # for residual (data perturbed). At minimum, target_proc_se should be 0.
  obs_dev1 <- se[dev == 1L]
  expect_true(all(obs_dev1$target_proc_se == 0))
})


test_that("full Phase 2a pipeline runs end-to-end on multi-group Triangle", {
  tri <- make_tri()
  boots <- bootstrap(tri, method = "residual", mode = "dev",
                      process = "gamma", B = 20, seed = 1)

  for (method in c("cl", "ed", "sa")) {
    refit <- .boot_refit(tri, boots, method = method, alpha = 1,
                          maturity = if (method == "sa") detect_maturity(tri)
                                     else NULL)
    wn <- .boot_add_process_noise(refit, boots$meta$process)
    se <- .boot_summarize_se(wn, grp = "coverage")
    expect_true(nrow(se) > 0L, info = method)
    expect_true(all(is.finite(se$target_proj) | is.na(se$target_proj)),
                info = method)
  }
})


# ---------------------------------------------------------------------------
# bootstrap.Triangle target arg + unified .boot_refit
# ---------------------------------------------------------------------------

test_that("bootstrap.Triangle accepts target = 'prem'", {
  tri <- make_sub_tri("SUR")
  b <- bootstrap(tri, target = "prem", B = 10, seed = 1)
  expect_identical(b$meta$target, "prem")
  expect_true("prem" %in% names(b$alt_triangles))
  expect_false("loss" %in% names(b$alt_triangles))
})

test_that(".boot_refit rejects ed/sa on premium target", {
  tri   <- make_sub_tri("SUR")
  b_prem <- bootstrap(tri, target = "prem", B = 5, seed = 1)
  expect_error(.boot_refit(tri, b_prem, method = "ed"),
               "ed.*supports.*loss")
  expect_error(.boot_refit(tri, b_prem, method = "sa",
                            maturity = detect_maturity(tri)),
               "sa.*supports.*loss")
})

test_that(".boot_refit method = sa requires maturity", {
  tri   <- make_sub_tri("SUR")
  boots <- bootstrap(tri, B = 5, seed = 1)
  expect_error(.boot_refit(tri, boots, method = "sa"),
               "Maturity")
})

test_that(".resolve_bootstrap target mismatch is rejected", {
  tri <- make_sub_tri("SUR")
  b_loss <- bootstrap(tri, target = "loss", B = 5, seed = 1)
  b_prem <- bootstrap(tri, target = "prem", B = 5, seed = 1)

  expect_error(.resolve_bootstrap(b_loss, tri, target = "prem"),
               "expects target")
  expect_error(.resolve_bootstrap(b_prem, tri, target = "loss"),
               "expects target")
  expect_identical(.resolve_bootstrap(b_prem, tri, target = "prem"), b_prem)
})


# ---------------------------------------------------------------------------
# Phase 2b: fit_premium migration to new bootstrap pipeline
# ---------------------------------------------------------------------------

test_that("fit_premium default (method=ed) uses bootstrap", {
  tri <- make_sub_tri("SUR")
  pf <- fit_premium(tri, seed = 1, B = 50)
  expect_identical(pf$ci_type, "bootstrap")
  expect_true(!is.null(pf$bootstrap))
})

test_that("fit_premium method=cl bootstrap=FALSE uses analytical", {
  tri <- make_sub_tri("SUR")
  pf <- fit_premium(tri, method = "cl", bootstrap = FALSE)
  expect_identical(pf$ci_type, "analytical")
  expect_null(pf$bootstrap)
})

test_that("fit_premium method=cl bootstrap=TRUE uses bootstrap", {
  tri <- make_sub_tri("SUR")
  pf <- fit_premium(tri, method = "cl", bootstrap = TRUE, seed = 1, B = 50)
  expect_identical(pf$ci_type, "bootstrap")
})

test_that("fit_premium accepts a pre-built BootstrapTriangle", {
  tri <- make_sub_tri("SUR")
  b <- bootstrap(tri, target = "prem", B = 50, seed = 1)
  pf <- fit_premium(tri, method = "ed", bootstrap = b)
  expect_identical(pf$ci_type, "bootstrap")
  expect_identical(pf$bootstrap$B, 50L)
})

test_that("fit_premium accepts a bootstrap function (lazy spec)", {
  tri <- make_sub_tri("SUR")
  fn <- function(t) bootstrap(t, target = "prem", B = 30, seed = 1)
  pf <- fit_premium(tri, bootstrap = fn)
  expect_identical(pf$ci_type, "bootstrap")
  expect_identical(pf$bootstrap$B, 30L)
})

test_that("fit_premium rejects a BootstrapTriangle built on the wrong target", {
  tri <- make_sub_tri("SUR")
  b_loss <- bootstrap(tri, target = "loss", B = 30, seed = 1)
  expect_error(fit_premium(tri, bootstrap = b_loss),
               "expects target")
})

test_that("fit_premium projected cells have finite SE/CI under bootstrap", {
  tri <- make_sub_tri("SUR")
  pf <- fit_premium(tri, seed = 1, B = 100)
  proj <- pf$full[is_observed == FALSE]
  expect_true(all(is.finite(proj$prem_proj)))
  expect_true(all(is.finite(proj$prem_total_se)))
  expect_true(all(is.finite(proj$prem_ci_lo)))
  expect_true(all(is.finite(proj$prem_ci_hi)))
  expect_true(all(proj$prem_ci_lo <= proj$prem_ci_hi))
})


# ---------------------------------------------------------------------------
# Phase 2c: fit_loss migration to new bootstrap pipeline
# ---------------------------------------------------------------------------

test_that("fit_loss default (method=sa) uses bootstrap", {
  tri <- make_sub_tri("SUR")
  lf <- fit_loss(tri, seed = 1, B = 50)
  expect_identical(lf$ci_type, "bootstrap")
  expect_true(!is.null(lf$bootstrap))
})

test_that("fit_loss method=ed uses bootstrap by default", {
  tri <- make_sub_tri("SUR")
  lf <- fit_loss(tri, method = "ed", seed = 1, B = 50)
  expect_identical(lf$ci_type, "bootstrap")
})

test_that("fit_loss method=cl bootstrap=FALSE uses analytical", {
  tri <- make_sub_tri("SUR")
  lf <- fit_loss(tri, method = "cl", bootstrap = FALSE)
  expect_identical(lf$ci_type, "analytical")
  expect_null(lf$bootstrap)
})

test_that("fit_loss method=cl bootstrap=TRUE uses bootstrap", {
  tri <- make_sub_tri("SUR")
  lf <- fit_loss(tri, method = "cl", bootstrap = TRUE, seed = 1, B = 50)
  expect_identical(lf$ci_type, "bootstrap")
})

test_that("fit_loss accepts a pre-built BootstrapTriangle", {
  tri <- make_sub_tri("SUR")
  b <- bootstrap(tri, target = "loss", B = 50, seed = 1)
  lf <- fit_loss(tri, method = "sa", bootstrap = b)
  expect_identical(lf$ci_type, "bootstrap")
  expect_identical(lf$bootstrap$B, 50L)
})

test_that("fit_loss accepts a bootstrap function (lazy spec)", {
  tri <- make_sub_tri("SUR")
  fn <- function(t) bootstrap(t, target = "loss", B = 30, seed = 1)
  lf <- fit_loss(tri, method = "ed", bootstrap = fn)
  expect_identical(lf$ci_type, "bootstrap")
  expect_identical(lf$bootstrap$B, 30L)
})

test_that("fit_loss rejects a BootstrapTriangle on the wrong target", {
  tri <- make_sub_tri("SUR")
  b_prem <- bootstrap(tri, target = "prem", B = 30, seed = 1)
  expect_error(fit_loss(tri, bootstrap = b_prem),
               "expects target")
})

test_that("fit_loss projected cells have finite SE/CI where loss_proj is defined", {
  tri <- make_sub_tri("SUR")
  for (method in c("sa", "ed", "cl")) {
    lf <- fit_loss(tri, method = method, bootstrap = TRUE,
                    seed = 1, B = 50)
    # Some method=cl projected cells can have NA loss_proj (analytical
    # projection requires sufficient prior-dev data). Only test cells
    # where the analytical projection itself produced a finite value.
    proj <- lf$full[is_observed == FALSE & is.finite(loss_proj)]
    expect_true(all(is.finite(proj$loss_total_se)), info = method)
    expect_true(all(is.finite(proj$loss_ci_lo)),    info = method)
    expect_true(all(is.finite(proj$loss_ci_hi)),    info = method)
    expect_true(all(proj$loss_ci_lo <= proj$loss_ci_hi), info = method)
  }
})

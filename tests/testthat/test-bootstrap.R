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
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "nonparametric", residual = "link",
                  method = "separated", B = 20, seed = 1)

  expect_s3_class(b, "BootstrapTriangle")
  for (nm in c("alt_triangles", "residual_pool", "f_anchor",
               "sigma2_anchor", "meta")) {
    expect_true(nm %in% names(b), info = paste("missing", nm))
  }
})

test_that("meta records all configured arguments", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "nonparametric", residual = "link",
                  method = "pooled", process = "gamma",
                  B = 17L, seed = 42, alpha = 1)
  m <- b$meta
  expect_identical(m$type,     "nonparametric")
  expect_identical(m$residual, "link")
  expect_identical(m$method,   "pooled")
  expect_identical(m$process,  "gamma")
  expect_identical(m$B,        17L)
  expect_identical(m$seed,     42)
  expect_identical(m$alpha,    1)
  expect_identical(m$target,   "loss")
})


# ---------------------------------------------------------------------------
# alt_triangles long-format shape
# ---------------------------------------------------------------------------

test_that("alt_triangles has [cohort × dev × B] rows per group", {
  tri <- make_sub_tri("surgery")
  n_coh <- length(unique(tri$cohort))
  n_dev <- length(unique(tri$dev))
  B     <- 20L

  b <- bootstrap(tri, type = "nonparametric", residual = "link", B = B, seed = 1)
  expect_equal(nrow(b$alt_triangles), n_coh * n_dev * B)
  expect_true(all(c("coverage", "cohort", "dev", "rep", "loss") %in%
                    names(b$alt_triangles)))
  expect_equal(sort(unique(b$alt_triangles$rep)), seq_len(B))
})

test_that("alt_triangles multi-group splits evenly per group", {
  tri <- make_tri()
  B <- 10L
  b <- bootstrap(tri, type = "nonparametric", residual = "link", B = B, seed = 1)
  counts <- b$alt_triangles[, .N, by = coverage]
  expect_true(all(counts$N == counts$N[1L]))
})


# ---------------------------------------------------------------------------
# Seed reproducibility
# ---------------------------------------------------------------------------

test_that("same seed reproduces identical alt_triangles (nonparametric link)", {
  tri <- make_sub_tri("surgery")
  a <- bootstrap(tri, type = "nonparametric", residual = "link",
                  B = 30, seed = 7)$alt_triangles$loss
  b <- bootstrap(tri, type = "nonparametric", residual = "link",
                  B = 30, seed = 7)$alt_triangles$loss
  expect_identical(a, b)
})

test_that("different seeds give different draws (nonparametric link)", {
  tri <- make_sub_tri("surgery")
  a <- bootstrap(tri, type = "nonparametric", residual = "link",
                  B = 30, seed = 7)$alt_triangles$loss
  b <- bootstrap(tri, type = "nonparametric", residual = "link",
                  B = 30, seed = 8)$alt_triangles$loss
  expect_false(identical(a, b))
})

test_that("same seed reproduces identical alt_triangles (parametric)", {
  tri <- make_sub_tri("surgery")
  a <- bootstrap(tri, type = "parametric", B = 30, seed = 7)$alt_triangles$loss
  b <- bootstrap(tri, type = "parametric", B = 30, seed = 7)$alt_triangles$loss
  expect_identical(a, b)
})


# ---------------------------------------------------------------------------
# type = "parametric" preserves observed cells
# ---------------------------------------------------------------------------

test_that("parametric type preserves observed cells across replicates", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "parametric", B = 30, seed = 1)
  obs <- tri[1L]
  matched <- b$alt_triangles[
    cohort == obs$cohort & dev == obs$dev, loss
  ]
  expect_length(unique(matched), 1L)
  expect_equal(matched[1L], obs$loss)
})


# ---------------------------------------------------------------------------
# method-specific pool structure
# ---------------------------------------------------------------------------

test_that("method = 'separated' gives one pool per (group, ata_to)", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "nonparametric", residual = "link",
                  method = "separated", B = 5, seed = 1)
  n_links <- nrow(b$f_anchor)
  expect_equal(length(unique(b$residual_pool$pool_id)), n_links)
})

test_that("method = 'pooled' single-group gives one pool", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "nonparametric", residual = "link",
                  method = "pooled", B = 5, seed = 1)
  expect_equal(length(unique(b$residual_pool$pool_id)), 1L)
})

test_that("method = 'pooled' multi-group gives one pool per group", {
  tri <- make_tri()
  b <- bootstrap(tri, type = "nonparametric", residual = "link",
                  method = "pooled", B = 5, seed = 1)
  expect_equal(length(unique(b$residual_pool$pool_id)),
               length(unique(tri$coverage)))
})

test_that("method = 'tail_pooled', tail = 'maturity' requires non-null maturity", {
  tri <- make_sub_tri("surgery")
  expect_error(
    bootstrap(tri, type = "nonparametric", residual = "link",
              method = "tail_pooled", tail = "maturity",
              maturity = NULL, B = 5, seed = 1),
    "maturity"
  )
})

test_that("method = 'tail_pooled', tail = 'maturity', maturity = 'auto' produces POST + per-dev pools", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "nonparametric", residual = "link",
                  method = "tail_pooled", tail = "maturity",
                  maturity = "auto", B = 5, seed = 1)
  pool_ids <- unique(b$residual_pool$pool_id)
  # Expect at least one POST bucket and at least one per-dev bucket
  expect_true(any(grepl("POST$", pool_ids)))
  expect_true(any(!grepl("POST$", pool_ids)))
})

test_that("method = 'tail_pooled', tail = 'auto' cuts when residual count < min_pool", {
  tri <- make_sub_tri("surgery")
  # The 30-month dev triangle has shrinking residual counts deep in the
  # tail: late ata_to has 1-2 cohorts. With min_pool = 5 the cut should
  # land somewhere in the late dev range and produce a POST bucket.
  b <- bootstrap(tri, type = "nonparametric", residual = "link",
                  method = "tail_pooled", tail = "auto",
                  min_pool = 5L, B = 5, seed = 1)
  pool_ids <- unique(b$residual_pool$pool_id)
  expect_true(any(grepl("POST$", pool_ids)))
  expect_true(any(!grepl("POST$", pool_ids)))
  expect_identical(b$meta$tail,     "auto")
  expect_identical(b$meta$min_pool, 5L)
})

test_that("method = 'tail_pooled', tail = 'auto' is fully separated when all pools meet min_pool", {
  tri <- make_sub_tri("surgery")
  # min_pool = 1 lets every per-dev pool keep its own bucket -- no POST.
  b <- bootstrap(tri, type = "nonparametric", residual = "link",
                  method = "tail_pooled", tail = "auto",
                  min_pool = 1L, B = 5, seed = 1)
  pool_ids <- unique(b$residual_pool$pool_id)
  expect_false(any(grepl("POST$", pool_ids)))
})


# ---------------------------------------------------------------------------
# Bootstrap-induced variability for projected cells
# ---------------------------------------------------------------------------

test_that("residual bootstrap induces variability in projected cells", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "nonparametric", residual = "link",
                  B = 200, seed = 1)
  cohorts <- sort(unique(b$alt_triangles$cohort))
  last_coh <- cohorts[length(cohorts)]
  devs <- sort(unique(b$alt_triangles$dev))
  late_dev <- devs[length(devs) - 1L]
  vals <- b$alt_triangles[cohort == last_coh & dev == late_dev, loss]
  expect_true(is.finite(stats::sd(vals)))
  expect_gt(stats::sd(vals), 0)
})

test_that("parametric bootstrap induces variability in projected cells", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "parametric", B = 200, seed = 1)
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
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "nonparametric", residual = "link",
                  B = 5, seed = 1)
  for (nm in c("coverage", "ata_from", "ata_to", "f_hat", "n_cohorts")) {
    expect_true(nm %in% names(b$f_anchor), info = paste("missing", nm))
  }
  expect_true(all(is.finite(b$f_anchor$f_hat)))
  expect_true(all(b$f_anchor$n_cohorts >= 1L))
})

test_that("sigma2_anchor has expected columns and non-negative sigma2", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "nonparametric", residual = "link",
                  B = 5, seed = 1)
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
  tri <- make_sub_tri("surgery")
  expect_error(bootstrap(tri, B = 0),    "B")
  expect_error(bootstrap(tri, B = -1),   "B")
  expect_error(bootstrap(tri, B = NA),   "B")
  expect_error(bootstrap(tri, B = "10"), "B")
})

test_that("invalid alpha raises an error", {
  tri <- make_sub_tri("surgery")
  expect_error(bootstrap(tri, alpha = NA),    "alpha")
  expect_error(bootstrap(tri, alpha = "1"),   "alpha")
})

test_that("invalid seed raises an error", {
  tri <- make_sub_tri("surgery")
  expect_error(bootstrap(tri, seed = "x"),  "seed")
  expect_error(bootstrap(tri, seed = c(1, 2)), "seed")
})

test_that("invalid type/residual/method/tail/process raise match.arg errors", {
  tri <- make_sub_tri("surgery")
  expect_error(bootstrap(tri, type     = "wrong"))
  expect_error(bootstrap(tri, residual = "wrong"))
  expect_error(bootstrap(tri, method   = "wrong"))
  expect_error(bootstrap(tri, tail     = "wrong"))
  expect_error(bootstrap(tri, process  = "wrong"))
})


# ---------------------------------------------------------------------------
# Validator (.validate_bootstrap_args)
# ---------------------------------------------------------------------------

test_that("type = 'parametric' with non-normal process errors", {
  tri <- make_sub_tri("surgery")
  expect_error(
    bootstrap(tri, type = "parametric", process = "gamma", B = 5, seed = 1),
    "parametric.*requires process"
  )
  expect_error(
    bootstrap(tri, type = "parametric", process = "od_pois", B = 5, seed = 1),
    "parametric.*requires process"
  )
})

test_that("residual = 'cell' with normal process errors (positivity)", {
  tri <- make_sub_tri("surgery")
  expect_error(
    bootstrap(tri, type = "nonparametric", residual = "cell",
              process = "normal", B = 5, seed = 1),
    "ODP.*positivity|positivity"
  )
})

test_that("process = 'lognormal' errors with 'not yet implemented'", {
  tri <- make_sub_tri("surgery")
  expect_error(
    bootstrap(tri, type = "nonparametric", residual = "link",
              process = "lognormal", B = 5, seed = 1),
    "lognormal.*not yet implemented"
  )
})

test_that("residual = 'link' with hat_adj = TRUE warns and ignores", {
  tri <- make_sub_tri("surgery")
  expect_warning(
    bootstrap(tri, type = "nonparametric", residual = "link",
              hat_adj = TRUE, B = 5, seed = 1),
    "hat_adj.*deferred|hat_adj.*Ignored|hat_adj.*ignored"
  )
})

test_that("type = 'parametric' warns when method/tail/min_pool explicitly set", {
  tri <- make_sub_tri("surgery")
  expect_warning(
    bootstrap(tri, type = "parametric", method = "separated",
              B = 5, seed = 1),
    "method.*ignored"
  )
  expect_warning(
    bootstrap(tri, type = "parametric", min_pool = 10L, B = 5, seed = 1),
    "min_pool.*ignored"
  )
})

test_that("method != 'tail_pooled' warns when tail/min_pool explicitly set", {
  tri <- make_sub_tri("surgery")
  expect_warning(
    bootstrap(tri, type = "nonparametric", residual = "link",
              method = "separated", tail = "auto", B = 5, seed = 1),
    "tail.*ignored"
  )
  expect_warning(
    bootstrap(tri, type = "nonparametric", residual = "link",
              method = "separated", min_pool = 10L, B = 5, seed = 1),
    "min_pool.*ignored"
  )
})

test_that("invalid min_pool errors", {
  tri <- make_sub_tri("surgery")
  expect_error(
    bootstrap(tri, type = "nonparametric", residual = "link",
              method = "tail_pooled", tail = "auto", min_pool = 0L,
              B = 5, seed = 1),
    "min_pool"
  )
  expect_error(
    bootstrap(tri, type = "nonparametric", residual = "link",
              method = "tail_pooled", tail = "auto", min_pool = -1L,
              B = 5, seed = 1),
    "min_pool"
  )
})


# ---------------------------------------------------------------------------
# Cell residual + hat_adj (Phase 5b.2)
# ---------------------------------------------------------------------------

test_that("residual = 'cell' returns a BootstrapTriangle with cell pool schema", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "nonparametric", residual = "cell",
                 hat_adj = TRUE, process = "gamma", B = 10, seed = 1)
  expect_s3_class(b, "BootstrapTriangle")
  # Cell pool keys by dev (not ata_to/ata_from)
  expect_true("dev" %in% names(b$residual_pool))
  expect_false("ata_from" %in% names(b$residual_pool))
  expect_true("pool_id" %in% names(b$residual_pool))
  # alt_triangles shape preserved across modes
  n_coh <- length(unique(tri$cohort))
  n_dev <- length(unique(tri$dev))
  expect_equal(nrow(b$alt_triangles), n_coh * n_dev * 10L)
})

test_that("residual = 'cell' default hat_adj is TRUE (chainladder-py parity)", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "nonparametric", residual = "cell",
                 process = "gamma", B = 5, seed = 1)
  expect_true(isTRUE(b$meta$hat_adj))
})

test_that("residual default is 'cell' (chainladder-py parity)", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "nonparametric", process = "gamma",
                 B = 5, seed = 1)
  expect_identical(b$meta$residual, "cell")
})

test_that("cell residual with hat_adj = FALSE applies DF correction", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "nonparametric", residual = "cell",
                 hat_adj = FALSE, process = "gamma", B = 10, seed = 1)
  expect_s3_class(b, "BootstrapTriangle")
  expect_false(isTRUE(b$meta$hat_adj))
  # Pool residuals are finite and centred at zero per pool
  expect_true(all(is.finite(b$residual_pool$residual)))
  expect_lt(abs(mean(b$residual_pool$residual)), 1e-9)
})

test_that("cell residual + hat_adj = TRUE drops corner cells (h_ii = 1)", {
  tri <- make_sub_tri("surgery")
  b_hat <- bootstrap(tri, type = "nonparametric", residual = "cell",
                     hat_adj = TRUE, process = "gamma", B = 5, seed = 1)
  b_nohat <- bootstrap(tri, type = "nonparametric", residual = "cell",
                       hat_adj = FALSE, process = "gamma", B = 5, seed = 1)
  # hat_adj drops the two corner cells where h_ii = 1; pool size strictly
  # smaller than DF-corrected pool (which uses every observed cell with
  # finite μ̂).
  expect_lt(nrow(b_hat$residual_pool), nrow(b_nohat$residual_pool))
})

test_that("cell residual same seed reproduces identical alt_triangles", {
  tri <- make_sub_tri("surgery")
  b1 <- bootstrap(tri, type = "nonparametric", residual = "cell",
                  hat_adj = TRUE, process = "gamma", B = 20, seed = 7)
  b2 <- bootstrap(tri, type = "nonparametric", residual = "cell",
                  hat_adj = TRUE, process = "gamma", B = 20, seed = 7)
  expect_identical(b1$alt_triangles, b2$alt_triangles)
})

test_that("cell residual induces variability in projected cells", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "nonparametric", residual = "cell",
                 hat_adj = TRUE, process = "gamma", B = 200, seed = 1)
  # Pick one projected cell (cohort with shortest history -> most projection)
  alt <- b$alt_triangles
  by_cell <- alt[, list(sd_v = stats::sd(loss)),
                   by = c("cohort", "dev")]
  # At least some cells should show variability (std > 0)
  expect_gt(max(by_cell$sd_v, na.rm = TRUE), 0)
})

test_that("cell residual + method = 'separated' gives one pool per dev", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "nonparametric", residual = "cell",
                 hat_adj = FALSE, process = "gamma",
                 method = "separated", B = 5, seed = 1)
  pool <- b$residual_pool
  # pool_id should encode dev, so unique pool_ids == unique observed devs
  # (subject to all-NaN dev filtering)
  n_pools <- length(unique(pool$pool_id))
  n_devs  <- length(unique(pool$dev))
  expect_equal(n_pools, n_devs)
})

test_that("cell residual + method = 'pooled' gives one pool", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "nonparametric", residual = "cell",
                 hat_adj = FALSE, process = "gamma",
                 method = "pooled", B = 5, seed = 1)
  expect_equal(length(unique(b$residual_pool$pool_id)), 1L)
})


# ---------------------------------------------------------------------------
# print method
# ---------------------------------------------------------------------------

test_that("print.BootstrapTriangle prints all configured fields", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, type = "nonparametric", residual = "link",
                  method = "separated", process = "gamma",
                  B = 5, seed = 1)
  out <- utils::capture.output(print(b))
  expect_true(any(grepl("BootstrapTriangle", out)))
  expect_true(any(grepl("type",     out)))
  expect_true(any(grepl("nonparametric", out)))
  expect_true(any(grepl("residual", out)))
  expect_true(any(grepl("method",   out)))
  expect_true(any(grepl("separated", out)))
  expect_true(any(grepl("gamma",    out)))
  expect_true(any(grepl("5 replicates", out)))
})


# ---------------------------------------------------------------------------
# Phase 2a consumer helpers
# ---------------------------------------------------------------------------

test_that(".resolve_bootstrap dispatches NULL / FALSE / TRUE / 'auto' / obj / fn", {
  tri <- make_sub_tri("surgery")

  expect_null(.resolve_bootstrap(NULL,  tri, B = 5, seed = 1))
  expect_null(.resolve_bootstrap(FALSE, tri, B = 5, seed = 1))

  b1 <- .resolve_bootstrap(TRUE,   tri, B = 5, seed = 1)
  b2 <- .resolve_bootstrap("auto", tri, B = 5, seed = 1)
  expect_s3_class(b1, "BootstrapTriangle")
  expect_s3_class(b2, "BootstrapTriangle")
  expect_identical(b1$meta$B, 5L)

  b_obj <- bootstrap(tri, B = 5, seed = 1)
  expect_identical(.resolve_bootstrap(b_obj, tri), b_obj)

  fn <- function(t) bootstrap(t, B = 3, seed = 1, type = "nonparametric",
                                residual = "link")
  b_fn <- .resolve_bootstrap(fn, tri)
  expect_identical(b_fn$meta$B,    3L)
  expect_identical(b_fn$meta$type, "nonparametric")
})

test_that(".resolve_bootstrap rejects bad input", {
  tri <- make_sub_tri("surgery")
  expect_error(.resolve_bootstrap("garbage", tri), "must be NULL")
  expect_error(.resolve_bootstrap(function(t) 42, tri), "BootstrapTriangle")
})


test_that(".boot_refit returns same shape for all methods", {
  tri <- make_sub_tri("surgery")
  boots <- bootstrap(tri, B = 30, seed = 1)
  mat   <- detect_maturity(tri)

  r_cl <- .boot_refit(tri, boots, method = "cl", alpha = 1)
  r_ed <- .boot_refit(tri, boots, method = "ed", alpha = 1)
  r_sa <- .boot_refit(tri, boots, method = "sa", alpha = 1, maturity = mat)

  for (rdt in list(r_cl, r_ed, r_sa)) {
    expect_true(all(c("coverage", "cohort", "dev", "rep",
                      "cell_mean", "cell_real") %in% names(rdt)))
    expect_equal(nrow(rdt), length(unique(tri$cohort)) *
                              length(unique(tri$dev)) * 30L)
  }
})

test_that(".boot_refit(method='cl') observed cells share value across reps", {
  tri <- make_sub_tri("surgery")
  boots <- bootstrap(tri, B = 10, seed = 1)
  r_cl  <- .boot_refit(tri, boots, method = "cl", alpha = 1)

  # Observed cell: cell_real should equal the original observed value
  # across all replicates (no chain noise on the observed region).
  cells <- r_cl[cohort == as.Date("2023-01-01") & dev == 1L]
  expect_length(unique(cells$cell_real), 1L)
})

test_that(".boot_refit(method='cl') projected cells vary across reps", {
  tri <- make_sub_tri("surgery")
  boots <- bootstrap(tri, B = 30, seed = 1)
  r_cl  <- .boot_refit(tri, boots, method = "cl", alpha = 1)

  # A clearly-projected cell: latest cohort, mid-tail dev. cell_real
  # should vary across replicates due to chain-propagated process noise.
  cells <- r_cl[cohort == as.Date("2025-12-01") & dev == 10L]
  expect_true(stats::sd(cells$cell_real, na.rm = TRUE) > 0 ||
              all(!is.finite(cells$cell_mean)))
})


test_that(".boot_summarize_se produces expected columns and SE decomposition", {
  tri <- make_sub_tri("surgery")
  boots <- bootstrap(tri, B = 50, seed = 1)
  refit <- .boot_refit(tri, boots, method = "cl", alpha = 1)
  se    <- .boot_summarize_se(refit, grp = "coverage")

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
  boots <- bootstrap(tri, type = "nonparametric", residual = "link",
                      method = "separated", process = "gamma",
                      B = 20, seed = 1)

  for (method in c("cl", "ed", "sa")) {
    refit <- .boot_refit(tri, boots, method = method, alpha = 1,
                          maturity = if (method == "sa") detect_maturity(tri)
                                     else NULL)
    se <- .boot_summarize_se(refit, grp = "coverage")
    expect_true(nrow(se) > 0L, info = method)
    expect_true(all(is.finite(se$target_proj) | is.na(se$target_proj)),
                info = method)
  }
})


# ---------------------------------------------------------------------------
# bootstrap.Triangle target arg + unified .boot_refit
# ---------------------------------------------------------------------------

test_that("bootstrap.Triangle accepts target = 'prem'", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, target = "prem", B = 10, seed = 1)
  expect_identical(b$meta$target, "prem")
  expect_true("prem" %in% names(b$alt_triangles))
  expect_false("loss" %in% names(b$alt_triangles))
})

test_that(".boot_refit rejects ed/sa on premium target", {
  tri   <- make_sub_tri("surgery")
  b_prem <- bootstrap(tri, target = "prem", B = 5, seed = 1)
  expect_error(.boot_refit(tri, b_prem, method = "ed"),
               "ed.*supports.*loss")
  expect_error(.boot_refit(tri, b_prem, method = "sa",
                            maturity = detect_maturity(tri)),
               "sa.*supports.*loss")
})

test_that(".boot_refit method = sa requires maturity", {
  tri   <- make_sub_tri("surgery")
  boots <- bootstrap(tri, B = 5, seed = 1)
  expect_error(.boot_refit(tri, boots, method = "sa"),
               "Maturity")
})

test_that(".resolve_bootstrap target mismatch is rejected", {
  tri <- make_sub_tri("surgery")
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
  tri <- make_sub_tri("surgery")
  pf <- fit_premium(tri, seed = 1, B = 50)
  expect_identical(pf$ci_type, "bootstrap")
  expect_true(!is.null(pf$bootstrap))
})

test_that("fit_premium method=cl bootstrap=FALSE uses analytical", {
  tri <- make_sub_tri("surgery")
  pf <- fit_premium(tri, method = "cl", bootstrap = FALSE)
  expect_identical(pf$ci_type, "analytical")
  expect_null(pf$bootstrap)
})

test_that("fit_premium method=cl bootstrap=TRUE uses bootstrap", {
  tri <- make_sub_tri("surgery")
  pf <- fit_premium(tri, method = "cl", bootstrap = TRUE, seed = 1, B = 50)
  expect_identical(pf$ci_type, "bootstrap")
})

test_that("fit_premium accepts a pre-built BootstrapTriangle", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, target = "prem", B = 50, seed = 1)
  pf <- fit_premium(tri, method = "ed", bootstrap = b)
  expect_identical(pf$ci_type, "bootstrap")
  expect_identical(pf$bootstrap$B, 50L)
})

test_that("fit_premium accepts a bootstrap function (lazy spec)", {
  tri <- make_sub_tri("surgery")
  fn <- function(t) bootstrap(t, target = "prem", B = 30, seed = 1)
  pf <- fit_premium(tri, bootstrap = fn)
  expect_identical(pf$ci_type, "bootstrap")
  expect_identical(pf$bootstrap$B, 30L)
})

test_that("fit_premium rejects a BootstrapTriangle built on the wrong target", {
  tri <- make_sub_tri("surgery")
  b_loss <- bootstrap(tri, target = "loss", B = 30, seed = 1)
  expect_error(fit_premium(tri, bootstrap = b_loss),
               "expects target")
})

test_that("fit_premium projected cells have finite SE/CI under bootstrap", {
  tri <- make_sub_tri("surgery")
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
  tri <- make_sub_tri("surgery")
  lf <- fit_loss(tri, seed = 1, B = 50)
  expect_identical(lf$ci_type, "bootstrap")
  expect_true(!is.null(lf$bootstrap))
})

test_that("fit_loss method=ed uses bootstrap by default", {
  tri <- make_sub_tri("surgery")
  lf <- fit_loss(tri, method = "ed", seed = 1, B = 50)
  expect_identical(lf$ci_type, "bootstrap")
})

test_that("fit_loss method=cl bootstrap=FALSE uses analytical", {
  tri <- make_sub_tri("surgery")
  lf <- fit_loss(tri, method = "cl", bootstrap = FALSE)
  expect_identical(lf$ci_type, "analytical")
  expect_null(lf$bootstrap)
})

test_that("fit_loss method=cl bootstrap=TRUE uses bootstrap", {
  tri <- make_sub_tri("surgery")
  lf <- fit_loss(tri, method = "cl", bootstrap = TRUE, seed = 1, B = 50)
  expect_identical(lf$ci_type, "bootstrap")
})

test_that("fit_loss accepts a pre-built BootstrapTriangle", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, target = "loss", B = 50, seed = 1)
  lf <- fit_loss(tri, method = "sa", bootstrap = b)
  expect_identical(lf$ci_type, "bootstrap")
  expect_identical(lf$bootstrap$B, 50L)
})

test_that("fit_loss accepts a bootstrap function (lazy spec)", {
  tri <- make_sub_tri("surgery")
  fn <- function(t) bootstrap(t, target = "loss", B = 30, seed = 1)
  lf <- fit_loss(tri, method = "ed", bootstrap = fn)
  expect_identical(lf$ci_type, "bootstrap")
  expect_identical(lf$bootstrap$B, 30L)
})

test_that("fit_loss rejects a BootstrapTriangle on the wrong target", {
  tri <- make_sub_tri("surgery")
  b_prem <- bootstrap(tri, target = "prem", B = 30, seed = 1)
  expect_error(fit_loss(tri, bootstrap = b_prem),
               "expects target")
})

test_that("fit_loss projected cells have finite SE/CI where loss_proj is defined", {
  tri <- make_sub_tri("surgery")
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


# ---------------------------------------------------------------------------
# Phase 2d: fit_lr migration to new bootstrap pipeline
# ---------------------------------------------------------------------------

test_that("fit_lr default (method=sa) uses bootstrap", {
  tri <- make_sub_tri("surgery")
  lf <- fit_lr(tri, seed = 1, B = 50)
  expect_identical(lf$ci_type, "bootstrap")
  expect_true(!is.null(lf$bootstrap))
})

test_that("fit_lr method=cl bootstrap=FALSE uses analytical", {
  tri <- make_sub_tri("surgery")
  lf <- fit_lr(tri, method = "cl", bootstrap = FALSE)
  expect_identical(lf$ci_type, "analytical")
  expect_null(lf$bootstrap)
})

test_that("fit_lr method=cl bootstrap=TRUE uses bootstrap", {
  tri <- make_sub_tri("surgery")
  lf <- fit_lr(tri, method = "cl", bootstrap = TRUE, seed = 1, B = 50)
  expect_identical(lf$ci_type, "bootstrap")
})

test_that("fit_lr accepts a pre-built BootstrapTriangle", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, target = "loss", B = 50, seed = 1)
  lf <- fit_lr(tri, method = "sa", bootstrap = b)
  expect_identical(lf$ci_type, "bootstrap")
  expect_identical(lf$bootstrap$B, 50L)
})

test_that("fit_lr accepts a bootstrap function (lazy spec)", {
  tri <- make_sub_tri("surgery")
  fn <- function(t) bootstrap(t, target = "loss", B = 30, seed = 1)
  lf <- fit_lr(tri, method = "ed", bootstrap = fn)
  expect_identical(lf$ci_type, "bootstrap")
  expect_identical(lf$bootstrap$B, 30L)
})

test_that("fit_lr rejects a BootstrapTriangle on the wrong target", {
  tri <- make_sub_tri("surgery")
  b_prem <- bootstrap(tri, target = "prem", B = 30, seed = 1)
  expect_error(fit_lr(tri, bootstrap = b_prem),
               "expects target")
})

test_that("fit_lr se_method='delta' incorporates premium SE", {
  tri <- make_sub_tri("surgery")
  lf_fixed <- fit_lr(tri, method = "sa", se_method = "fixed",
                     seed = 1, B = 50)
  lf_delta <- fit_lr(tri, method = "sa", se_method = "delta",
                     seed = 1, B = 50)
  # `delta` typically gives smaller lr_se than `fixed` because rho > 0
  # cancels part of the loss/premium variance (the strong positive
  # correlation between cumulative loss and premium projection).
  proj_fixed <- lf_fixed$full[is_observed == FALSE & is.finite(lr_proj)]
  proj_delta <- lf_delta$full[is_observed == FALSE & is.finite(lr_proj)]
  expect_true(all(is.finite(proj_delta$lr_se)))
  expect_true(all(is.finite(proj_delta$prem_total_se)))
  expect_true(mean(proj_delta$lr_se) < mean(proj_fixed$lr_se))
})

test_that("fit_lr bootstrap projected cells have finite LR SE/CI", {
  tri <- make_sub_tri("surgery")
  for (method in c("sa", "ed", "cl")) {
    lf <- fit_lr(tri, method = method, bootstrap = TRUE,
                 seed = 1, B = 50)
    proj <- lf$full[is_observed == FALSE & is.finite(lr_proj)]
    expect_true(all(is.finite(proj$lr_se)),    info = method)
    expect_true(all(is.finite(proj$lr_ci_lo)), info = method)
    expect_true(all(is.finite(proj$lr_ci_hi)), info = method)
    expect_true(all(proj$lr_ci_lo <= proj$lr_ci_hi), info = method)
  }
})


# ---------------------------------------------------------------------------
# Phase 2e: backtest pass-through of new bootstrap arg
# ---------------------------------------------------------------------------

test_that("backtest target='lr' default uses bootstrap (SA -> bootstrap)", {
  tri <- make_sub_tri("surgery")
  bt <- backtest(tri, holdout = 6L, target = "lr", seed = 1, B = 50)
  expect_identical(bt$fit$ci_type, "bootstrap")
  expect_true(!is.null(bt$fit$bootstrap))
})

test_that("backtest target='loss' bootstrap=FALSE uses analytical", {
  tri <- make_sub_tri("surgery")
  bt <- backtest(tri, holdout = 6L, target = "loss",
                  loss_method = "cl", bootstrap = FALSE)
  expect_identical(bt$fit$ci_type, "analytical")
  expect_null(bt$fit$bootstrap)
})

test_that("backtest target='premium' bootstrap=TRUE uses bootstrap", {
  tri <- make_sub_tri("surgery")
  bt <- backtest(tri, holdout = 6L, target = "premium",
                  bootstrap = TRUE, seed = 1, B = 50)
  expect_identical(bt$fit$ci_type, "bootstrap")
})

test_that("backtest accepts function-based bootstrap (leakage-safe path)", {
  tri <- make_sub_tri("surgery")
  fn <- function(t) bootstrap(t, target = "loss", B = 30, seed = 1)
  bt <- backtest(tri, holdout = 6L, target = "lr", bootstrap = fn)
  expect_identical(bt$fit$ci_type, "bootstrap")
  expect_identical(bt$fit$bootstrap$B, 30L)
})

test_that("backtest function-based bootstrap targets the masked triangle", {
  # Probe: the bootstrap function receives the *masked* triangle (not the
  # original). Verify by counting cohorts in the triangle the function
  # actually sees -- masked has fewer observed cells than original.
  tri <- make_sub_tri("surgery")
  seen_rows <- integer(0)
  probe <- function(t) {
    seen_rows <<- c(seen_rows, nrow(t))
    bootstrap(t, target = "loss", B = 5, seed = 1)
  }
  invisible(backtest(tri, holdout = 6L, target = "lr", bootstrap = probe))
  expect_true(length(seen_rows) > 0L)
  # The masked triangle has fewer rows than the unmasked one (held-out
  # cells removed for the upper-triangle structure).
  expect_lt(seen_rows[1L], nrow(tri))
})

test_that("backtest rejects a BootstrapTriangle on the wrong target", {
  tri <- make_sub_tri("surgery")
  b_prem <- bootstrap(tri, target = "prem", B = 30, seed = 1)
  expect_error(
    backtest(tri, holdout = 6L, target = "loss", bootstrap = b_prem),
    "expects target"
  )
})

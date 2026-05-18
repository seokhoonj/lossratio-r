# Tests for the Triangle-level bootstrap worker.
#
# Scope:
#   - bootstrap() S3 generic + bootstrap.Triangle() method
#   - print.BootstrapTriangle()
#   - Per-cohort x dev $summary slot (Pythagorean SE decomposition)
#   - keep_pseudo toggle (pseudo_triangles long-format build skip)
#   - .resolve_bootstrap 4-type arg dispatch

# ---------------------------------------------------------------------------
# Basic structure
# ---------------------------------------------------------------------------

test_that("bootstrap.Triangle returns BootstrapTriangle with expected slots", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
                  pooling = "separated", B = 20, seed = 1)

  expect_s3_class(b, "BootstrapTriangle")
  for (nm in c("pseudo_triangles", "residual_pool", "f_anchor",
               "sigma2_anchor", "meta")) {
    expect_true(nm %in% names(b), info = paste("missing", nm))
  }
})

test_that("meta records all configured arguments", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
                  method = "cl", pooling = "pooled", process = "gamma",
                  B = 17L, seed = 42, alpha = 1)
  m <- b$meta
  expect_identical(m$type,     "nonparametric")
  expect_identical(m$residual, "link")
  expect_identical(m$method,   "cl")
  expect_identical(m$pooling,  "pooled")
  expect_identical(m$process,  "gamma")
  expect_identical(m$B,        17L)
  expect_identical(m$seed,     42)
  expect_identical(m$alpha,    1)
  expect_identical(m$target,   "loss")
})


# ---------------------------------------------------------------------------
# pseudo_triangles long-format shape
# ---------------------------------------------------------------------------

test_that("pseudo_triangles has [cohort x dev x B] rows per group", {
  tri <- make_sub_tri("surgery")
  n_coh <- length(unique(tri$cohort))
  n_dev <- length(unique(tri$dev))
  B     <- 20L

  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link", B = B, seed = 1)
  expect_equal(nrow(b$pseudo_triangles), n_coh * n_dev * B)
  expect_true(all(c("coverage", "cohort", "dev", "rep",
                     "loss_mean", "loss_sampled") %in%
                    names(b$pseudo_triangles)))
  expect_equal(sort(unique(b$pseudo_triangles$rep)), seq_len(B))
})

test_that("pseudo_triangles multi-group splits evenly per group", {
  tri <- make_tri()
  B <- 10L
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link", B = B, seed = 1)
  counts <- b$pseudo_triangles[, .N, by = coverage]
  expect_true(all(counts$N == counts$N[1L]))
})


# ---------------------------------------------------------------------------
# Seed reproducibility
# ---------------------------------------------------------------------------

test_that("same seed reproduces identical pseudo_triangles (nonparametric link)", {
  tri <- make_sub_tri("surgery")
  a <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
                  B = 30, seed = 7)$pseudo_triangles$loss_mean
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
                  B = 30, seed = 7)$pseudo_triangles$loss_mean
  expect_identical(a, b)
})

test_that("different seeds give different draws (nonparametric link)", {
  tri <- make_sub_tri("surgery")
  a <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
                  B = 30, seed = 7)$pseudo_triangles$loss_mean
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
                  B = 30, seed = 8)$pseudo_triangles$loss_mean
  expect_false(identical(a, b))
})

test_that("same seed reproduces identical pseudo_triangles (parametric)", {
  tri <- make_sub_tri("surgery")
  a <- bootstrap(tri, keep_pseudo = TRUE, type = "parametric", B = 30, seed = 7)$pseudo_triangles$loss_mean
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "parametric", B = 30, seed = 7)$pseudo_triangles$loss_mean
  expect_identical(a, b)
})


# ---------------------------------------------------------------------------
# type = "parametric" preserves observed cells
# ---------------------------------------------------------------------------

test_that("parametric type preserves observed cells across replicates", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "parametric", B = 30, seed = 1)
  obs <- tri[1L]
  # Parametric preserves observed cells across replicates (both columns
  # agree on the upper triangle -- loss_mean is the observed value, and
  # loss_sampled has no Stage 2 noise added there).
  matched <- b$pseudo_triangles[
    cohort == obs$cohort & dev == obs$dev, loss_mean
  ]
  expect_length(unique(matched), 1L)
  expect_equal(matched[1L], obs$loss)
})


# ---------------------------------------------------------------------------
# pooling-specific pool structure
# ---------------------------------------------------------------------------

test_that("pooling = 'separated' gives one pool per (group, ata_to)", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
                  pooling = "separated", B = 5, seed = 1)
  n_links <- nrow(b$f_anchor)
  expect_equal(length(unique(b$residual_pool$pool_id)), n_links)
})

test_that("pooling = 'pooled' single-group gives one pool", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
                  pooling = "pooled", B = 5, seed = 1)
  expect_equal(length(unique(b$residual_pool$pool_id)), 1L)
})

test_that("pooling = 'pooled' multi-group gives one pool per group", {
  tri <- make_tri()
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
                  pooling = "pooled", B = 5, seed = 1)
  expect_equal(length(unique(b$residual_pool$pool_id)),
               length(unique(tri$coverage)))
})

test_that("pooling = 'tail_pooled', tail = 'maturity' requires non-null maturity", {
  tri <- make_sub_tri("surgery")
  expect_error(
    bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
              pooling = "tail_pooled", tail = "maturity",
              maturity = NULL, B = 5, seed = 1),
    "maturity"
  )
})

test_that("pooling = 'tail_pooled', tail = 'maturity', maturity = 'auto' produces POST + per-dev pools", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
                  pooling = "tail_pooled", tail = "maturity",
                  maturity = "auto", B = 5, seed = 1)
  pool_ids <- unique(b$residual_pool$pool_id)
  # Expect at least one POST bucket and at least one per-dev bucket
  expect_true(any(grepl("POST$", pool_ids)))
  expect_true(any(!grepl("POST$", pool_ids)))
})

test_that("pooling = 'tail_pooled', tail = 'auto' cuts when residual count < min_pool", {
  tri <- make_sub_tri("surgery")
  # The 30-month dev triangle has shrinking residual counts deep in the
  # tail: late ata_to has 1-2 cohorts. With min_pool = 5 the cut should
  # land somewhere in the late dev range and produce a POST bucket.
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
                  pooling = "tail_pooled", tail = "auto",
                  min_pool = 5L, B = 5, seed = 1)
  pool_ids <- unique(b$residual_pool$pool_id)
  expect_true(any(grepl("POST$", pool_ids)))
  expect_true(any(!grepl("POST$", pool_ids)))
  expect_identical(b$meta$tail,     "auto")
  expect_identical(b$meta$min_pool, 5L)
})

test_that("pooling = 'tail_pooled', tail = 'auto' is fully separated when all pools meet min_pool", {
  tri <- make_sub_tri("surgery")
  # min_pool = 1 lets every per-dev pool keep its own bucket -- no POST.
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
                  pooling = "tail_pooled", tail = "auto",
                  min_pool = 1L, B = 5, seed = 1)
  pool_ids <- unique(b$residual_pool$pool_id)
  expect_false(any(grepl("POST$", pool_ids)))
})


# ---------------------------------------------------------------------------
# Bootstrap-induced variability for projected cells
# ---------------------------------------------------------------------------

test_that("residual bootstrap induces variability in projected cells", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
                  B = 200, seed = 1)
  cohorts <- sort(unique(b$pseudo_triangles$cohort))
  last_coh <- cohorts[length(cohorts)]
  devs <- sort(unique(b$pseudo_triangles$dev))
  late_dev <- devs[length(devs) - 1L]
  vals <- b$pseudo_triangles[cohort == last_coh & dev == late_dev, loss_mean]
  expect_true(is.finite(stats::sd(vals)))
  expect_gt(stats::sd(vals), 0)
})

test_that("parametric bootstrap induces variability in projected cells", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "parametric", B = 200, seed = 1)
  cohorts <- sort(unique(b$pseudo_triangles$cohort))
  last_coh <- cohorts[length(cohorts)]
  devs <- sort(unique(b$pseudo_triangles$dev))
  late_dev <- devs[length(devs) - 1L]
  vals <- b$pseudo_triangles[cohort == last_coh & dev == late_dev, loss_mean]
  expect_true(is.finite(stats::sd(vals)))
  expect_gt(stats::sd(vals), 0)
})


# ---------------------------------------------------------------------------
# f_anchor / sigma2_anchor structure
# ---------------------------------------------------------------------------

test_that("f_anchor has expected columns and one row per link", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
                  B = 5, seed = 1)
  for (nm in c("coverage", "ata_from", "ata_to", "f_hat", "n_cohorts")) {
    expect_true(nm %in% names(b$f_anchor), info = paste("missing", nm))
  }
  expect_true(all(is.finite(b$f_anchor$f_hat)))
  expect_true(all(b$f_anchor$n_cohorts >= 1L))
})

test_that("sigma2_anchor has expected columns and non-negative sigma2", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
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
  expect_error(bootstrap(tri, keep_pseudo = TRUE, B = 0),    "B")
  expect_error(bootstrap(tri, keep_pseudo = TRUE, B = -1),   "B")
  expect_error(bootstrap(tri, keep_pseudo = TRUE, B = NA),   "B")
  expect_error(bootstrap(tri, keep_pseudo = TRUE, B = "10"), "B")
})

test_that("invalid alpha raises an error", {
  tri <- make_sub_tri("surgery")
  expect_error(bootstrap(tri, keep_pseudo = TRUE, alpha = NA),    "alpha")
  expect_error(bootstrap(tri, keep_pseudo = TRUE, alpha = "1"),   "alpha")
})

test_that("invalid seed raises an error", {
  tri <- make_sub_tri("surgery")
  expect_error(bootstrap(tri, keep_pseudo = TRUE, seed = "x"),  "seed")
  expect_error(bootstrap(tri, keep_pseudo = TRUE, seed = c(1, 2)), "seed")
})

test_that("invalid type/residual/method/pooling/tail/process raise match.arg errors", {
  tri <- make_sub_tri("surgery")
  expect_error(bootstrap(tri, keep_pseudo = TRUE, type     = "wrong"))
  expect_error(bootstrap(tri, keep_pseudo = TRUE, residual = "wrong"))
  expect_error(bootstrap(tri, keep_pseudo = TRUE, method   = "wrong"))
  expect_error(bootstrap(tri, keep_pseudo = TRUE, pooling  = "wrong"))
  expect_error(bootstrap(tri, keep_pseudo = TRUE, tail     = "wrong"))
  expect_error(bootstrap(tri, keep_pseudo = TRUE, process  = "wrong"))
})


# ---------------------------------------------------------------------------
# Validator (.validate_bootstrap_args)
# ---------------------------------------------------------------------------

test_that("type = 'parametric' with non-normal process errors", {
  tri <- make_sub_tri("surgery")
  expect_error(
    bootstrap(tri, keep_pseudo = TRUE, type = "parametric", process = "gamma", B = 5, seed = 1),
    "parametric.*requires process"
  )
  expect_error(
    bootstrap(tri, keep_pseudo = TRUE, type = "parametric", process = "od_pois", B = 5, seed = 1),
    "parametric.*requires process"
  )
})

test_that("residual = 'cell' with normal process errors (positivity)", {
  tri <- make_sub_tri("surgery")
  expect_error(
    bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "cell",
              process = "normal", B = 5, seed = 1),
    "ODP.*positivity|positivity"
  )
})

test_that("process = 'lognormal' errors with 'not yet implemented'", {
  tri <- make_sub_tri("surgery")
  expect_error(
    bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
              process = "lognormal", B = 5, seed = 1),
    "lognormal.*not yet implemented"
  )
})

test_that("residual = 'link' with hat_adj = TRUE warns and ignores", {
  tri <- make_sub_tri("surgery")
  expect_warning(
    bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
              hat_adj = TRUE, B = 5, seed = 1),
    "hat_adj.*deferred|hat_adj.*Ignored|hat_adj.*ignored"
  )
})

test_that("type = 'parametric' warns when pooling/tail/min_pool explicitly set", {
  tri <- make_sub_tri("surgery")
  expect_warning(
    bootstrap(tri, keep_pseudo = TRUE, type = "parametric", pooling = "separated",
              B = 5, seed = 1),
    "pooling.*ignored"
  )
  expect_warning(
    bootstrap(tri, keep_pseudo = TRUE, type = "parametric", min_pool = 10L, B = 5, seed = 1),
    "min_pool.*ignored"
  )
})

test_that("pooling != 'tail_pooled' warns when tail/min_pool explicitly set", {
  tri <- make_sub_tri("surgery")
  expect_warning(
    bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
              pooling = "separated", tail = "auto", B = 5, seed = 1),
    "tail.*ignored"
  )
  expect_warning(
    bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
              pooling = "separated", min_pool = 10L, B = 5, seed = 1),
    "min_pool.*ignored"
  )
})

test_that("invalid min_pool errors", {
  tri <- make_sub_tri("surgery")
  expect_error(
    bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
              pooling = "tail_pooled", tail = "auto", min_pool = 0L,
              B = 5, seed = 1),
    "min_pool"
  )
  expect_error(
    bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
              pooling = "tail_pooled", tail = "auto", min_pool = -1L,
              B = 5, seed = 1),
    "min_pool"
  )
})


# ---------------------------------------------------------------------------
# Cell residual + hat_adj (Phase 5b.2)
# ---------------------------------------------------------------------------

test_that("residual = 'cell' returns a BootstrapTriangle with cell pool schema", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "cell",
                 hat_adj = TRUE, process = "gamma", B = 10, seed = 1)
  expect_s3_class(b, "BootstrapTriangle")
  # Cell pool keys by dev (not ata_to/ata_from)
  expect_true("dev" %in% names(b$residual_pool))
  expect_false("ata_from" %in% names(b$residual_pool))
  expect_true("pool_id" %in% names(b$residual_pool))
  # pseudo_triangles shape preserved across modes
  n_coh <- length(unique(tri$cohort))
  n_dev <- length(unique(tri$dev))
  expect_equal(nrow(b$pseudo_triangles), n_coh * n_dev * 10L)
})

test_that("residual = 'cell' default hat_adj is TRUE (chainladder-py parity)", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "cell",
                 process = "gamma", B = 5, seed = 1)
  expect_true(isTRUE(b$meta$hat_adj))
})

test_that("residual default is 'cell' (chainladder-py parity)", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", process = "gamma",
                 B = 5, seed = 1)
  expect_identical(b$meta$residual, "cell")
})

test_that("cell residual with hat_adj = FALSE applies DF correction", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "cell",
                 hat_adj = FALSE, process = "gamma", B = 10, seed = 1)
  expect_s3_class(b, "BootstrapTriangle")
  expect_false(isTRUE(b$meta$hat_adj))
  # Pool residuals are finite and centred at zero per pool
  expect_true(all(is.finite(b$residual_pool$residual)))
  expect_lt(abs(mean(b$residual_pool$residual)), 1e-9)
})

test_that("cell residual + hat_adj = TRUE produces different residual magnitudes", {
  tri <- make_sub_tri("surgery")
  # hat_adj is a CL-paradigm leverage correction (England-Verrall 2002
  # Addendum); ED residuals use a different design matrix and skip
  # hat_adj. Pin method = "cl" to keep this an apples-to-apples CL test.
  b_hat <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "cell",
                     method = "cl",
                     hat_adj = TRUE, process = "gamma", B = 5, seed = 1)
  b_nohat <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "cell",
                       method = "cl",
                       hat_adj = FALSE, process = "gamma", B = 5, seed = 1)
  # Both pools drop zero residuals (latest-observed diagonal cells). The
  # observable difference between hat=T / hat=F is in residual magnitudes:
  # hat=T inflates each retained residual by 1/sqrt(1 - h_ii); hat=F applies
  # a uniform sqrt(n/(n-p)) DF factor. Pool sizes can coincide after the
  # zero-drop, so test the residual scale instead.
  sd_hat   <- stats::sd(b_hat$residual_pool$residual,   na.rm = TRUE)
  sd_nohat <- stats::sd(b_nohat$residual_pool$residual, na.rm = TRUE)
  expect_false(isTRUE(all.equal(sd_hat, sd_nohat, tolerance = 1e-3)))
})

test_that("cell residual same seed reproduces identical pseudo_triangles", {
  tri <- make_sub_tri("surgery")
  b1 <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "cell",
                  hat_adj = TRUE, process = "gamma", B = 20, seed = 7)
  b2 <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "cell",
                  hat_adj = TRUE, process = "gamma", B = 20, seed = 7)
  expect_identical(b1$pseudo_triangles, b2$pseudo_triangles)
})

test_that("cell residual induces variability in projected cells", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "cell",
                 hat_adj = TRUE, process = "gamma", B = 200, seed = 1)
  # Pick one projected cell (cohort with shortest history -> most projection)
  alt <- b$pseudo_triangles
  by_cell <- alt[, list(sd_v = stats::sd(loss_mean)),
                   by = c("cohort", "dev")]
  # At least some cells should show variability (std > 0)
  expect_gt(max(by_cell$sd_v, na.rm = TRUE), 0)
})

test_that("cell residual + pooling = 'separated' gives one pool per dev", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "cell",
                 hat_adj = FALSE, process = "gamma",
                 pooling = "separated", B = 5, seed = 1)
  pool <- b$residual_pool
  # pool_id should encode dev, so unique pool_ids == unique observed devs
  # (subject to all-NaN dev filtering)
  n_pools <- length(unique(pool$pool_id))
  n_devs  <- length(unique(pool$dev))
  expect_equal(n_pools, n_devs)
})

test_that("cell residual + pooling = 'pooled' gives one pool", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "cell",
                 hat_adj = FALSE, process = "gamma",
                 pooling = "pooled", B = 5, seed = 1)
  expect_equal(length(unique(b$residual_pool$pool_id)), 1L)
})


# ---------------------------------------------------------------------------
# print method
# ---------------------------------------------------------------------------

test_that("print.BootstrapTriangle prints all configured fields", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, type = "nonparametric", residual = "link",
                  pooling = "separated", process = "gamma",
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

  b_obj <- bootstrap(tri, keep_pseudo = TRUE, B = 5, seed = 1)
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


# Legacy .boot_refit / .boot_summarize_se tests removed -- fit_* now read
# bt$summary directly (wrap-only), so those helpers and the tests that
# exercised them in isolation are obsolete. Bootstrap behaviour is now
# verified through the public fit_ratio / fit_loss / fit_exposure interface
# and the bt$summary structure tests above.


# ---------------------------------------------------------------------------
# bootstrap.Triangle target arg
# ---------------------------------------------------------------------------

test_that("bootstrap.Triangle accepts target = 'exposure'", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, target = "exposure", B = 10, seed = 1)
  expect_identical(b$meta$target, "exposure")
  expect_true("exposure_mean"    %in% names(b$pseudo_triangles))
  expect_true("exposure_sampled" %in% names(b$pseudo_triangles))
  expect_false("loss_mean" %in% names(b$pseudo_triangles))
})

test_that(".resolve_bootstrap target mismatch is rejected", {
  tri <- make_sub_tri("surgery")
  b_loss <- bootstrap(tri, keep_pseudo = TRUE, target = "loss", B = 5, seed = 1)
  b_exposure <- bootstrap(tri, keep_pseudo = TRUE, target = "exposure", B = 5, seed = 1)

  expect_error(.resolve_bootstrap(b_loss, tri, target = "exposure"),
               "expects target")
  expect_error(.resolve_bootstrap(b_exposure, tri, target = "loss"),
               "expects target")
  expect_identical(.resolve_bootstrap(b_exposure, tri, target = "exposure"), b_exposure)
})


# ---------------------------------------------------------------------------
# Phase 2b: fit_exposure migration to new bootstrap pipeline
# ---------------------------------------------------------------------------

test_that("fit_exposure default (method=ed) uses bootstrap", {
  tri <- make_sub_tri("surgery")
  pf <- fit_exposure(tri, seed = 1, B = 50)
  expect_identical(pf$ci_type, "bootstrap")
  expect_true(!is.null(pf$bootstrap))
})

test_that("fit_exposure method=cl bootstrap=FALSE uses analytical", {
  tri <- make_sub_tri("surgery")
  pf <- fit_exposure(tri, method = "cl", bootstrap = FALSE)
  expect_identical(pf$ci_type, "analytical")
  expect_null(pf$bootstrap)
})

test_that("fit_exposure method=cl bootstrap=TRUE uses bootstrap", {
  tri <- make_sub_tri("surgery")
  pf <- fit_exposure(tri, method = "cl", bootstrap = TRUE, seed = 1, B = 50)
  expect_identical(pf$ci_type, "bootstrap")
})

test_that("fit_exposure accepts a pre-built BootstrapTriangle", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, target = "exposure", B = 50, seed = 1)
  pf <- fit_exposure(tri, method = "ed", bootstrap = b)
  expect_identical(pf$ci_type, "bootstrap")
  expect_identical(pf$bootstrap$B, 50L)
})

test_that("fit_exposure accepts a bootstrap function (lazy spec)", {
  tri <- make_sub_tri("surgery")
  fn <- function(t) bootstrap(t, target = "exposure", B = 30, seed = 1)
  pf <- fit_exposure(tri, bootstrap = fn)
  expect_identical(pf$ci_type, "bootstrap")
  expect_identical(pf$bootstrap$B, 30L)
})

test_that("fit_exposure rejects a BootstrapTriangle built on the wrong target", {
  tri <- make_sub_tri("surgery")
  b_loss <- bootstrap(tri, keep_pseudo = TRUE, target = "loss", B = 30, seed = 1)
  expect_error(fit_exposure(tri, bootstrap = b_loss),
               "expects target")
})

test_that("fit_exposure projected cells have finite SE/CI under bootstrap", {
  tri <- make_sub_tri("surgery")
  pf <- fit_exposure(tri, seed = 1, B = 100)
  proj <- pf$full[is_observed == FALSE]
  expect_true(all(is.finite(proj$exposure_proj)))
  expect_true(all(is.finite(proj$exposure_total_se)))
  expect_true(all(is.finite(proj$exposure_ci_lo)))
  expect_true(all(is.finite(proj$exposure_ci_hi)))
  expect_true(all(proj$exposure_ci_lo <= proj$exposure_ci_hi))
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
  b <- bootstrap(tri, keep_pseudo = TRUE, target = "loss", B = 50, seed = 1)
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
  b_exposure <- bootstrap(tri, keep_pseudo = TRUE, target = "exposure", B = 30, seed = 1)
  expect_error(fit_loss(tri, bootstrap = b_exposure),
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
# Phase 2d: fit_ratio migration to new bootstrap pipeline
# ---------------------------------------------------------------------------

test_that("fit_ratio default (method=sa) uses bootstrap", {
  tri <- make_sub_tri("surgery")
  lf <- fit_ratio(tri, seed = 1, B = 50)
  expect_identical(lf$ci_type, "bootstrap")
  expect_true(!is.null(lf$bootstrap))
})

test_that("fit_ratio method=cl bootstrap=FALSE uses analytical", {
  tri <- make_sub_tri("surgery")
  lf <- fit_ratio(tri, method = "cl", bootstrap = FALSE)
  expect_identical(lf$ci_type, "analytical")
  expect_null(lf$bootstrap)
})

test_that("fit_ratio method=cl bootstrap=TRUE uses bootstrap", {
  tri <- make_sub_tri("surgery")
  lf <- fit_ratio(tri, method = "cl", bootstrap = TRUE, seed = 1, B = 50)
  expect_identical(lf$ci_type, "bootstrap")
})

test_that("fit_ratio accepts a pre-built BootstrapTriangle", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, target = "loss", B = 50, seed = 1)
  lf <- fit_ratio(tri, method = "sa", bootstrap = b)
  expect_identical(lf$ci_type, "bootstrap")
  expect_identical(lf$bootstrap$B, 50L)
})

test_that("fit_ratio accepts a bootstrap function (lazy spec)", {
  tri <- make_sub_tri("surgery")
  fn <- function(t) bootstrap(t, target = "loss", B = 30, seed = 1)
  lf <- fit_ratio(tri, method = "ed", bootstrap = fn)
  expect_identical(lf$ci_type, "bootstrap")
  expect_identical(lf$bootstrap$B, 30L)
})

test_that("fit_ratio rejects a BootstrapTriangle on the wrong target", {
  tri <- make_sub_tri("surgery")
  b_exposure <- bootstrap(tri, keep_pseudo = TRUE, target = "exposure", B = 30, seed = 1)
  expect_error(fit_ratio(tri, bootstrap = b_exposure),
               "expects target")
})

test_that("fit_ratio se_method='delta' incorporates exposure SE", {
  tri <- make_sub_tri("surgery")
  lf_fixed <- fit_ratio(tri, method = "sa", se_method = "fixed",
                     seed = 1, B = 50)
  lf_delta <- fit_ratio(tri, method = "sa", se_method = "delta",
                     seed = 1, B = 50)
  # `delta` typically gives smaller ratio_se than `fixed` because rho > 0
  # cancels part of the loss/exposure variance (the strong positive
  # correlation between cumulative loss and exposure projection).
  proj_fixed <- lf_fixed$full[is_observed == FALSE & is.finite(ratio_proj)]
  proj_delta <- lf_delta$full[is_observed == FALSE & is.finite(ratio_proj)]
  expect_true(all(is.finite(proj_delta$ratio_se)))
  expect_true(all(is.finite(proj_delta$exposure_total_se)))
  expect_true(mean(proj_delta$ratio_se) < mean(proj_fixed$ratio_se))
})

test_that("fit_ratio bootstrap projected cells have finite ratio SE/CI", {
  tri <- make_sub_tri("surgery")
  for (method in c("sa", "ed", "cl")) {
    lf <- fit_ratio(tri, method = method, bootstrap = TRUE,
                 seed = 1, B = 50)
    proj <- lf$full[is_observed == FALSE & is.finite(ratio_proj)]
    expect_true(all(is.finite(proj$ratio_se)),    info = method)
    expect_true(all(is.finite(proj$ratio_ci_lo)), info = method)
    expect_true(all(is.finite(proj$ratio_ci_hi)), info = method)
    expect_true(all(proj$ratio_ci_lo <= proj$ratio_ci_hi), info = method)
  }
})


# ---------------------------------------------------------------------------
# Phase 2e: backtest pass-through of new bootstrap arg
# ---------------------------------------------------------------------------

test_that("backtest target='ratio' default uses bootstrap (SA -> bootstrap)", {
  tri <- make_sub_tri("surgery")
  bt <- backtest(tri, holdout = 6L, target = "ratio", seed = 1, B = 50)
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

test_that("backtest target='exposure' bootstrap=TRUE uses bootstrap", {
  tri <- make_sub_tri("surgery")
  bt <- backtest(tri, holdout = 6L, target = "exposure",
                  bootstrap = TRUE, seed = 1, B = 50)
  expect_identical(bt$fit$ci_type, "bootstrap")
})

test_that("backtest accepts function-based bootstrap (leakage-safe path)", {
  tri <- make_sub_tri("surgery")
  fn <- function(t) bootstrap(t, target = "loss", B = 30, seed = 1)
  bt <- backtest(tri, holdout = 6L, target = "ratio", bootstrap = fn)
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
  invisible(backtest(tri, holdout = 6L, target = "ratio", bootstrap = probe))
  expect_true(length(seen_rows) > 0L)
  # The masked triangle has fewer rows than the unmasked one (held-out
  # cells removed for the upper-triangle structure).
  expect_lt(seen_rows[1L], nrow(tri))
})

test_that("backtest rejects a BootstrapTriangle on the wrong target", {
  tri <- make_sub_tri("surgery")
  b_exposure <- bootstrap(tri, keep_pseudo = TRUE, target = "exposure", B = 30, seed = 1)
  expect_error(
    backtest(tri, holdout = 6L, target = "loss", bootstrap = b_exposure),
    "expects target"
  )
})


# ---------------------------------------------------------------------------
# BootstrapTriangle$summary slot -- Pythagorean SE decomposition
# ---------------------------------------------------------------------------

test_that("$summary default schema (quantile_ci = FALSE) omits CI columns", {
  tri <- make_sub_tri("surgery")
  bt <- bootstrap(tri, keep_pseudo = TRUE, residual = "cell", method = "sa",
                  pooling = "tail_pooled", tail = "auto",
                  B = 50, seed = 1)
  expect_true(is.data.frame(bt$summary))
  expect_true(all(c("cohort", "dev",
                     "mean_proj", "param_se", "proc_se",
                     "total_se", "total_cv")
                   %in% names(bt$summary)))
  expect_false("ci_lo" %in% names(bt$summary))
  expect_false("ci_hi" %in% names(bt$summary))
})

test_that("$summary with quantile_ci = TRUE adds CI columns", {
  tri <- make_sub_tri("surgery")
  bt <- bootstrap(tri, keep_pseudo = TRUE, residual = "cell", method = "sa",
                  pooling = "tail_pooled", tail = "auto",
                  B = 50, seed = 1, quantile_ci = TRUE)
  expect_true(all(c("ci_lo", "ci_hi") %in% names(bt$summary)))
})

test_that("$summary SE decomposition satisfies Pythagorean (proc^2 = max(total^2-param^2, 0))", {
  tri <- make_sub_tri("surgery")
  bt <- bootstrap(tri, keep_pseudo = TRUE, residual = "cell", method = "sa",
                  pooling = "tail_pooled", tail = "auto",
                  B = 200, seed = 7)
  s <- bt$summary
  # When total >= param (most cells under finite-B): identity holds.
  # When total < param (finite-B noise): proc clamped to 0, identity
  # holds in the same form (proc^2 = 0).
  ok <- is.finite(s$param_se) & is.finite(s$total_se) & is.finite(s$proc_se)
  diff <- abs(s$proc_se[ok]^2 - pmax(s$total_se[ok]^2 - s$param_se[ok]^2, 0))
  expect_true(all(diff < 1e-6 + 1e-6 * (s$total_se[ok]^2 + 1)))
  expect_true(all(s$proc_se[ok] >= 0))
})

test_that("$summary mean_proj matches Stage 1 mean across replicates", {
  tri <- make_sub_tri("surgery")
  bt <- bootstrap(tri, keep_pseudo = TRUE, residual = "cell", method = "sa",
                  pooling = "tail_pooled", tail = "auto",
                  B = 100, seed = 13)
  by_cell <- bt$pseudo_triangles[, .(mp = mean(loss_mean, na.rm = TRUE)),
                               by = .(coverage, cohort, dev)]
  m <- merge(by_cell, bt$summary[, .(coverage, cohort, dev, mean_proj)],
             by = c("coverage", "cohort", "dev"))
  expect_equal(m$mp, m$mean_proj, tolerance = 1e-10)
})

test_that("$summary CI bounds bracket mean_proj on projected cells", {
  tri <- make_sub_tri("surgery")
  bt <- bootstrap(tri, keep_pseudo = TRUE, residual = "cell", method = "sa",
                  pooling = "tail_pooled", tail = "auto",
                  B = 100, seed = 21, quantile_ci = TRUE)
  proj <- bt$summary[is.finite(ci_lo) & is.finite(ci_hi) & is.finite(mean_proj)]
  expect_true(all(proj$ci_lo <= proj$ci_hi))
  expect_true(all(proj$ci_lo <= proj$mean_proj + 1e-6))
  expect_true(all(proj$ci_hi >= proj$mean_proj - 1e-6))
})

test_that("quantile_ci returns C-computed values matching stats::quantile(type=1)", {
  tri <- make_sub_tri("surgery")
  bt <- bootstrap(tri, type = "nonparametric", residual = "cell",
                  hat_adj = FALSE, process = "gamma",
                  B = 99L, seed = 42, quantile_ci = TRUE,
                  keep_pseudo = TRUE)
  sm <- bt$summary
  pl <- bt$pseudo_triangles
  grp <- attr(bt, "groups")
  if (is.null(grp)) grp <- intersect(names(sm), names(pl))
  grp <- setdiff(grp, c("cohort", "dev", "rep",
                        "mean_proj", "param_se", "proc_se",
                        "total_se", "total_cv", "ci_lo", "ci_hi",
                        "loss_mean", "loss_sampled"))
  by_cols <- c(grp, "cohort", "dev")

  # Compute R-level type=1 quantiles per cell with na.rm = TRUE.
  ref <- pl[, .(
    ci_lo_ref = stats::quantile(loss_sampled, 0.025, type = 1,
                                names = FALSE, na.rm = TRUE),
    ci_hi_ref = stats::quantile(loss_sampled, 0.975, type = 1,
                                names = FALSE, na.rm = TRUE),
    n_fin     = sum(is.finite(loss_sampled))
  ), by = by_cols]

  m <- merge(sm[, c(by_cols, "ci_lo", "ci_hi"), with = FALSE],
             ref, by = by_cols, sort = FALSE)

  # n_fin < 2 cells must produce NA on both sides.
  na_rows <- m$n_fin < 2L
  if (any(na_rows)) {
    expect_true(all(is.na(m$ci_lo[na_rows])))
    expect_true(all(is.na(m$ci_hi[na_rows])))
  }
  # n_fin >= 2 cells: C output must equal stats::quantile(type=1) exactly
  # (type=1 is ordinal selection of an existing sample -- no float math).
  ok <- !na_rows
  if (any(ok)) {
    expect_identical(m$ci_lo[ok], m$ci_lo_ref[ok])
    expect_identical(m$ci_hi[ok], m$ci_hi_ref[ok])
  }
})


# ---------------------------------------------------------------------------
# demean toggle (cell mode)
# ---------------------------------------------------------------------------

test_that("demean = TRUE produces zero-mean residual pool per group", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, residual = "cell", method = "sa",
                  pooling = "tail_pooled", tail = "auto",
                  demean = TRUE, B = 30, seed = 1)
  means <- b$residual_pool[, mean(residual), by = "coverage"]$V1
  # After mean-centering, each group's residual mean is numerically ~ 0
  expect_true(all(abs(means) < 1e-10))
})

test_that("demean = FALSE preserves raw residual pool mean (non-zero in general)", {
  tri <- make_sub_tri("surgery")
  b_off <- bootstrap(tri, keep_pseudo = TRUE, residual = "cell", method = "sa",
                      pooling = "tail_pooled", tail = "auto",
                      demean = FALSE, B = 30, seed = 1)
  b_on  <- bootstrap(tri, keep_pseudo = TRUE, residual = "cell", method = "sa",
                      pooling = "tail_pooled", tail = "auto",
                      demean = TRUE,  B = 30, seed = 1)
  # The two pools differ when the raw mean is non-zero (the typical case)
  expect_false(identical(b_off$residual_pool$residual,
                         b_on$residual_pool$residual))
})

test_that("demean default is TRUE and recorded in meta", {
  tri <- make_sub_tri("surgery")
  b <- bootstrap(tri, keep_pseudo = TRUE, residual = "cell", method = "sa",
                  pooling = "tail_pooled", tail = "auto",
                  B = 20, seed = 1)
  expect_identical(b$meta$demean, TRUE)
})

test_that("demean warns-and-ignores under residual = 'link'", {
  tri <- make_sub_tri("surgery")
  expect_warning(
    bootstrap(tri, keep_pseudo = TRUE, residual = "link", pooling = "separated",
              demean = FALSE, B = 5, seed = 1),
    "demean.*ignored"
  )
})

test_that("demean warns-and-ignores under type = 'parametric'", {
  tri <- make_sub_tri("surgery")
  expect_warning(
    bootstrap(tri, keep_pseudo = TRUE, type = "parametric",
              demean = FALSE, B = 5, seed = 1),
    "demean.*ignored"
  )
})


# ---------------------------------------------------------------------------
# keep_pseudo toggle (memory-lean mode)
# ---------------------------------------------------------------------------

test_that("keep_pseudo = FALSE drops pseudo_triangles and keeps $summary", {
  tri <- make_sub_tri("surgery")
  bt <- bootstrap(tri, residual = "cell", method = "sa",
                  pooling = "tail_pooled", tail = "auto",
                  B = 50, seed = 1, keep_pseudo = FALSE)
  expect_null(bt$pseudo_triangles)
  expect_true(is.data.frame(bt$summary))
  # core decomposition columns still present
  expect_true(all(c("mean_proj", "param_se", "proc_se",
                     "total_se", "total_cv") %in% names(bt$summary)))
})

test_that("keep_pseudo = TRUE preserves pseudo_triangles long-format (default)", {
  tri <- make_sub_tri("surgery")
  bt <- bootstrap(tri, keep_pseudo = TRUE, residual = "cell", method = "sa",
                  pooling = "tail_pooled", tail = "auto",
                  B = 30, seed = 1)
  expect_false(is.null(bt$pseudo_triangles))
  expect_true(all(c("cohort", "dev", "rep",
                     "loss_mean", "loss_sampled")
                   %in% names(bt$pseudo_triangles)))
})

test_that("keep_pseudo = FALSE $summary matches keep_pseudo = TRUE summary numerically", {
  tri <- make_sub_tri("surgery")
  set.seed(42)
  bt_full <- bootstrap(tri, keep_pseudo = TRUE, residual = "cell", method = "sa",
                        pooling = "tail_pooled", tail = "auto", B = 100)
  set.seed(42)
  bt_lean <- bootstrap(tri, residual = "cell", method = "sa",
                        pooling = "tail_pooled", tail = "auto", B = 100,
                        keep_pseudo = FALSE)
  # Same RNG state -> identical summary
  expect_equal(bt_full$summary, bt_lean$summary)
})


# ---------------------------------------------------------------------------
# ED bootstrap (Phase 1 -- fixed exposure, additive forward projection)
# ---------------------------------------------------------------------------

test_that("ED bootstrap (method = 'ed') returns expected BootstrapTriangle shape", {
  tri <- make_sub_tri("surgery")
  bt <- bootstrap(tri, type = "nonparametric", residual = "cell",
                  method = "ed", process = "gamma",
                  B = 30, seed = 1, keep_pseudo = TRUE)
  expect_s3_class(bt, "BootstrapTriangle")
  expect_identical(bt$meta$method,   "ed")
  expect_identical(bt$meta$residual, "cell")
  # Pseudo triangles have the canonical [cohort x dev x B] shape.
  n_coh <- length(unique(tri$cohort))
  n_dev <- length(unique(tri$dev))
  expect_equal(nrow(bt$pseudo_triangles), n_coh * n_dev * 30L)
  expect_true(all(c("coverage", "cohort", "dev", "rep",
                     "loss_mean", "loss_sampled") %in%
                    names(bt$pseudo_triangles)))
})

test_that("ED bootstrap requires residual = 'cell'", {
  tri <- make_sub_tri("surgery")
  expect_error(
    bootstrap(tri, type = "nonparametric", residual = "link",
              method = "ed", B = 5, seed = 1),
    "method = 'ed'.*residual = 'cell'"
  )
})

test_that("ED bootstrap default method is 'ed'", {
  tri <- make_sub_tri("surgery")
  bt <- bootstrap(tri, type = "nonparametric", residual = "cell",
                  process = "gamma", B = 5, seed = 1)
  expect_identical(bt$meta$method, "ed")
})

test_that("ED bootstrap same seed reproduces identical $summary", {
  tri <- make_sub_tri("surgery")
  a <- bootstrap(tri, type = "nonparametric", residual = "cell",
                 method = "ed", process = "gamma",
                 B = 30, seed = 7, keep_pseudo = TRUE)$pseudo_triangles$loss_mean
  b <- bootstrap(tri, type = "nonparametric", residual = "cell",
                 method = "ed", process = "gamma",
                 B = 30, seed = 7, keep_pseudo = TRUE)$pseudo_triangles$loss_mean
  expect_identical(a, b)
})

test_that("ED bootstrap induces variability in projected cells", {
  tri <- make_sub_tri("surgery")
  bt <- bootstrap(tri, type = "nonparametric", residual = "cell",
                  method = "ed", process = "gamma",
                  B = 200, seed = 1, keep_pseudo = TRUE)
  alt <- bt$pseudo_triangles
  by_cell <- alt[, list(sd_v = stats::sd(loss_mean)),
                   by = c("cohort", "dev")]
  expect_gt(max(by_cell$sd_v, na.rm = TRUE), 0)
})

test_that("ED bootstrap $summary slot has cell-level SE decomposition columns", {
  tri <- make_sub_tri("surgery")
  bt <- bootstrap(tri, type = "nonparametric", residual = "cell",
                  method = "ed", process = "gamma",
                  B = 50, seed = 1)
  expect_true(all(c("cohort", "dev", "mean_proj",
                     "param_se", "proc_se", "total_se", "total_cv") %in%
                    names(bt$summary)))
  # Projected cells should have finite, non-negative SE entries.
  ult <- bt$summary[dev == max(bt$summary$dev)]
  expect_true(any(is.finite(ult$total_se)))
  expect_true(all(ult$total_se[is.finite(ult$total_se)] >= 0))
})

test_that("ED bootstrap point estimate lands in the right order of magnitude", {
  tri <- make_sub_tri("surgery")
  bt <- bootstrap(tri, type = "nonparametric", residual = "cell",
                  method = "ed", process = "gamma",
                  B = 200, seed = 1)
  # Analytical ED on the same triangle (intensity-weighted refit).
  ed_fit <- fit_ed(tri, loss = "loss", exposure = "exposure")
  # Compare ultimate per cohort between bootstrap mean and analytical
  # projection.
  ult_dev <- max(bt$summary$dev)
  boot_ult <- bt$summary[dev == ult_dev,
                          .(cohort, boot_mean = mean_proj)]
  ana_ult  <- ed_fit$full[dev == ult_dev,
                           .(cohort, ana = loss_proj)]
  m <- merge(boot_ult, ana_ult, by = "cohort", all = FALSE)
  m <- m[is.finite(boot_mean) & is.finite(ana) & ana > 0]
  expect_gt(nrow(m), 0L)
  # With `.boot_fitted_grid_ed` chain-anchoring AND the fixed
  # `bootstrap_refit_ed_gstar` denominator coverage (same FINITE mask on
  # cum and exposure_proj together, matching analytical g_hat coverage),
  # the bootstrap aggregate ultimate matches the analytical aggregate
  # within ~0.5 percent on the 4 cv synthetic data. Tight 5% threshold.
  ratio <- sum(m$boot_mean) / sum(m$ana)
  expect_gt(ratio, 0.95)
  expect_lt(ratio, 1.05)
})

test_that("ED and CL bootstraps both run on the same triangle and give different SEs", {
  tri <- make_sub_tri("surgery")
  bt_ed <- bootstrap(tri, type = "nonparametric", residual = "cell",
                     method = "ed", process = "gamma",
                     B = 100, seed = 1)
  bt_cl <- bootstrap(tri, type = "nonparametric", residual = "cell",
                     method = "cl", process = "gamma",
                     B = 100, seed = 1)
  # Both should produce a finite $summary with the same row count.
  expect_identical(nrow(bt_ed$summary), nrow(bt_cl$summary))
  # SEs should differ on at least some projected cells (different
  # paradigms produce different stochastic structures).
  cmp <- merge(
    bt_ed$summary[, .SD, .SDcols = c("cohort", "dev", "total_se")],
    bt_cl$summary[, .SD, .SDcols = c("cohort", "dev", "total_se")],
    by = c("cohort", "dev"),
    suffixes = c("_ed", "_cl")
  )
  cmp <- cmp[is.finite(total_se_ed) & is.finite(total_se_cl)]
  if (nrow(cmp) > 0L) {
    expect_true(any(abs(cmp$total_se_ed - cmp$total_se_cl) > 1e-6))
  }
})

test_that("ED bootstrap respects method enum order c('ed', 'cl', 'sa')", {
  tri <- make_sub_tri("surgery")
  # Default with no method should resolve to 'ed' (first in enum).
  bt <- bootstrap(tri, type = "nonparametric", residual = "cell",
                  process = "gamma", B = 5, seed = 1)
  expect_identical(bt$meta$method, "ed")
})

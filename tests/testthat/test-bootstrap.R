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

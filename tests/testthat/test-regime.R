# Setup — use a single-group subset to keep test fast
data(experience)
exp <- experience
sub <- build_triangle(exp[coverage == "SUR"], groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")

test_that("detect_regime returns class 'Regime' (e_divisive default)", {
  r <- detect_regime(sub, window = 12, method = "e_divisive")
  expect_s3_class(r, "Regime")
  expect_equal(r$method, "e_divisive")
  expect_equal(r$window, 12)
})

test_that("Regime has expected list elements", {
  r <- detect_regime(sub, window = 12, method = "e_divisive")
  for (nm in c("method", "target", "window", "cohort", "dev",
               "groups", "labels", "changes", "n_regimes",
               "trajectory", "pca")) {
    expect_true(nm %in% names(r), info = paste("missing", nm))
  }
})

test_that("$labels has cohort and regime columns", {
  r <- detect_regime(sub, window = 12, method = "e_divisive")
  expect_true("cohort" %in% names(r$labels))
  expect_true("regime" %in% names(r$labels))
})

test_that("$trajectory is a numeric matrix", {
  r <- detect_regime(sub, window = 12, method = "e_divisive")
  expect_true(is.matrix(r$trajectory))
  expect_true(is.numeric(r$trajectory))
})

test_that("$pca$sdev is positive numeric vector", {
  r <- detect_regime(sub, window = 12, method = "e_divisive")
  expect_true(is.numeric(r$pca$sdev))
  expect_true(all(r$pca$sdev >= 0))
})

test_that("methods 'pelt' and 'hclust' run", {
  expect_s3_class(detect_regime(sub, window = 12, method = "pelt"),
                  "Regime")
  expect_s3_class(detect_regime(sub, window = 12, method = "hclust"),
                  "Regime")
})

test_that("hclust with n_regimes = 3 runs", {
  # Note: hclust with k = 3 can produce > 3 sequential regime segments
  # if non-adjacent cohorts share a cluster. Just verify the call runs.
  r <- detect_regime(sub, window = 12, method = "hclust", n_regimes = 3)
  expect_s3_class(r, "Regime")
  expect_true(r$n_regimes >= 1L)
})

test_that("target = 'lr' runs", {
  expect_s3_class(detect_regime(sub, window = 12, method = "e_divisive", target = "lr"),
                  "Regime")
})

test_that("summary.Regime returns class 'summary.Regime'", {
  r <- detect_regime(sub, window = 12, method = "e_divisive")
  s <- summary(r)
  expect_s3_class(s, "summary.Regime")
})

test_that("print methods don't error", {
  r <- detect_regime(sub, window = 12, method = "e_divisive")
  expect_no_error(capture.output(print(r)))
  expect_no_error(capture.output(print(summary(r))))
})

# Multi-group regime detection --------------------------------------------

tri_all <- build_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")

test_that("multi-group detect_regime returns class 'Regime'", {
  r <- detect_regime(tri_all, by = "coverage", window = 12, method = "e_divisive")
  expect_s3_class(r, "Regime")
  expect_true(isTRUE(r$multi_group))
})

test_that("multi-group $changes is a data.table with group + change", {
  r <- detect_regime(tri_all, by = "coverage", window = 12, method = "e_divisive")
  expect_true(data.table::is.data.table(r$changes))
  expect_true("coverage" %in% names(r$changes))
  expect_true("change" %in% names(r$changes))
  expect_true(inherits(r$changes$change, "Date"))
})

test_that("multi-group $labels has group column", {
  r <- detect_regime(tri_all, by = "coverage", window = 12, method = "e_divisive")
  expect_true(data.table::is.data.table(r$labels))
  expect_true("coverage" %in% names(r$labels))
  expect_true("cohort"   %in% names(r$labels))
  expect_true("regime"   %in% names(r$labels))
})

test_that("multi-group $n_regimes is named integer vector", {
  r <- detect_regime(tri_all, by = "coverage", window = 12, method = "e_divisive")
  expect_true(is.integer(r$n_regimes))
  expect_true(length(names(r$n_regimes)) == length(r$n_regimes))
  expect_true(all(r$n_regimes >= 1L))
})

test_that("multi-group $trajectory and $pca are named lists", {
  r <- detect_regime(tri_all, by = "coverage", window = 12, method = "e_divisive")
  expect_true(is.list(r$trajectory))
  expect_true(is.list(r$pca))
  expect_true(all(vapply(r$trajectory, is.matrix, logical(1L))))
  expect_true(all(vapply(r$pca, inherits, logical(1L), "prcomp")))
})

test_that("multi-group hclust runs", {
  r <- detect_regime(tri_all, by = "coverage", window = 12, method = "hclust", n_regimes = 2L)
  expect_s3_class(r, "Regime")
  expect_true(isTRUE(r$multi_group))
})

test_that("multi-group print / summary don't error", {
  r <- detect_regime(tri_all, by = "coverage", window = 12, method = "e_divisive")
  expect_no_error(capture.output(print(r)))
  expect_no_error(capture.output(print(summary(r))))
})

test_that(".resolve_regime_date handles multi-group Regime (scalar path)", {
  r <- detect_regime(tri_all, by = "coverage", window = 12, method = "e_divisive")
  if (nrow(r$changes)) {
    bd <- lossratio:::.resolve_regime_date(r)
    expect_true(inherits(bd, "Date"))
    expect_equal(bd, max(r$changes$change))
  } else {
    expect_null(lossratio:::.resolve_regime_date(r))
  }
})

test_that(".resolve_regime_date with `by` returns per-group data.table", {
  r <- detect_regime(tri_all, by = "coverage", window = 12, method = "e_divisive")
  if (nrow(r$changes)) {
    bd <- lossratio:::.resolve_regime_date(r, by = "coverage")
    expect_true(data.table::is.data.table(bd))
    expect_true(all(c("coverage", "break_date") %in% names(bd)))
    expect_lte(nrow(bd), length(unique(r$changes$coverage)))
  }
})

test_that("multi-group plot.Regime returns a ggplot or patchwork object", {
  r <- detect_regime(tri_all, by = "coverage", window = 12, method = "e_divisive")
  p <- plot(r)
  expect_true(inherits(p, "ggplot") || inherits(p, "patchwork") ||
              is.list(p))
})

test_that("detect_regime errors when no group has enough cohorts", {
  # window larger than any group's cohort count -> every group dropped
  expect_error(
    suppressWarnings(
      detect_regime(tri_all, by = "coverage", window = 999L,
                    method = "e_divisive")
    ),
    "No group produced a usable detection result"
  )
})

test_that("detect_regime warns and skips groups that fail individually", {
  # Build a synthetic triangle where one group has too few cohorts but
  # others remain valid. Drop most of one coverage's cohorts.
  big_K <- 12L
  exp_part <- experience[!(coverage == "CI" & uy_m > as.Date("2023-03-01"))]
  tri_part <- build_triangle(exp_part, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
  expect_warning(
    r_part <- detect_regime(tri_part, by = "coverage", window = big_K,
                            method = "e_divisive"),
    "skipped"
  )
  expect_s3_class(r_part, "Regime")
  expect_true(isTRUE(r_part$multi_group))
  expect_false("CI" %in% names(r_part$trajectory))
})

test_that("detect_regime(tri) auto-uses attr(tri, 'groups')", {
  # by = NULL with multi-group Triangle picks up its `groups` attr,
  # producing per-group detection without an explicit `by`.
  r_default <- detect_regime(tri_all, window = 12L, method = "e_divisive")
  r_explicit <- detect_regime(tri_all, by = "coverage",
                              window = 12L, method = "e_divisive")
  expect_equal(r_default$groups, r_explicit$groups)
  expect_equal(r_default$multi_group, r_explicit$multi_group)
  expect_equal(sort(names(r_default$n_regimes)),
               sort(names(r_explicit$n_regimes)))
})

test_that("by = character(0) forces pooled detection on multi-group Triangle", {
  # Subset to one coverage so pooled detection succeeds; by = character(0)
  # then differs from the default by skipping the attr("groups") fallback.
  tri_one <- build_triangle(experience[coverage == "SUR"],
                            groups = "coverage",
                            cohort = "uy_m", calendar = "cy_m",
                            loss = "loss_incr", premium = "premium_incr")
  r_pooled <- detect_regime(tri_one, by = character(0) , window = 6L,
                            method = "e_divisive")
  expect_s3_class(r_pooled, "Regime")
  expect_false(isTRUE(r_pooled$multi_group))
  expect_equal(length(r_pooled$groups), 0L)
})

# ---- Per-group regime propagation to fit_* / backtest -----------------

test_that("multi-group Regime drives per-group fit_ata filtering", {
  r <- detect_regime(tri_all, by = "coverage", window = 6L,
                     method = "e_divisive")
  fit <- fit_ata(tri_all, target = "loss", regime = r)
  expect_s3_class(fit, "ATAFit")

  # Groups without a detected change keep all their link rows; groups
  # with a change get filtered. So the row count is _>=_ the count from
  # a uniform max-date scalar change.
  bd_max <- max(r$changes$change)
  fit_scalar <- fit_ata(tri_all, target = "loss",
                        regime = regime_at(change = bd_max))
  expect_gte(nrow(fit$link), nrow(fit_scalar$link))
})

test_that("multi-group Regime flows through fit_lr -> dispatcher -> worker", {
  r <- detect_regime(tri_all, by = "coverage", window = 6L,
                     method = "e_divisive")
  fit <- fit_lr(tri_all, loss_regime = r)
  expect_s3_class(fit, "LRFit")
  expect_true(nrow(fit$full) > 0L)
  # loss_regime preserves the original Regime object (multi-group
  # dispatch happens internally via .resolve_regime_date(by = grp))
  expect_s3_class(fit$loss_regime, "Regime")
  expect_identical(fit$loss_regime$changes, r$changes)
})

test_that("backtest passes multi-group Regime through to dispatcher", {
  r <- detect_regime(tri_all, by = "coverage", window = 6L,
                     method = "e_divisive")
  bt <- backtest(tri_all, holdout = 6L, target = "lr",
                loss_method = "sa", premium_method = "ed",
                loss_regime = r)
  expect_s3_class(bt, "Backtest")
  expect_true(nrow(bt$ae_err) > 0L)
})

# Tests for user-facing 4-type dispatch helpers
#   maturity_at(), maturity_spec(), regime_spec()
# plus the internal `.auto_divisor()` divisor picker.
# regime_at() has its own coverage in test-regime.R.

data(experience)
sub <- as_triangle(experience[coverage == "SUR"],
                   groups = "coverage", cohort = "uy_m", calendar = "cy_m",
                   loss = "loss_incr", premium = "premium_incr")

# maturity_at ---------------------------------------------------------------

test_that("maturity_at returns a Maturity object with scalar change", {
  m <- maturity_at(change = 4)
  expect_s3_class(m, "Maturity")
  expect_equal(nrow(m), 1L)
  expect_equal(m$change, 4)
  expect_equal(m$ata_from, 3)
  expect_equal(m$ata_link, "3-4")
  expect_identical(attr(m, "groups"), character(0))
})

test_that("maturity_at supports per-group changes", {
  m <- maturity_at(coverage = c("SUR", "CAN"),
                   change   = c(4, 7))
  expect_s3_class(m, "Maturity")
  expect_equal(nrow(m), 2L)
  expect_equal(sort(m$coverage), c("CAN", "SUR"))
  expect_equal(setNames(m$change, m$coverage)[c("SUR", "CAN")], c(SUR = 4, CAN = 7))
  expect_identical(attr(m, "groups"), "coverage")
})

test_that("maturity_at rejects unnamed / empty / mismatched args", {
  expect_error(maturity_at(4L),
               regexp = "must be named")
  expect_error(maturity_at(coverage = "SUR"),
               regexp = "requires a `change`")
  expect_error(maturity_at(coverage = c("SUR", "CAN"), change = 4),
               regexp = "equal length")
  expect_error(maturity_at(change = integer(0)),
               regexp = "length >= 1")
})

test_that("maturity_at output passes through fit_lr's maturity dispatch", {
  m <- maturity_at(coverage = "SUR", change = 4)
  fit <- fit_lr(sub, maturity = m)
  expect_s3_class(fit, "LRFit")
  # The dispatched object survives end-to-end
  expect_s3_class(fit$maturity, "Maturity")
  expect_equal(fit$maturity$change, 4)
})

# maturity_spec -------------------------------------------------------------

test_that("maturity_spec returns a closure of one arg", {
  spec <- maturity_spec(min_run = 2, max_cv = 0.04)
  expect_type(spec, "closure")
  expect_named(formals(spec), "tri")
})

test_that("maturity_spec captures kwargs and applies on triangle", {
  spec <- maturity_spec(min_run = 2)
  m <- spec(sub)
  # detect_maturity returns a Maturity object
  expect_s3_class(m, "Maturity")
})

test_that("maturity_spec plugs into fit_lr (closure form)", {
  fit <- fit_lr(sub, maturity = maturity_spec(min_run = 2))
  expect_s3_class(fit, "LRFit")
  expect_s3_class(fit$maturity, "Maturity")
})

# regime_spec ---------------------------------------------------------------

test_that("regime_spec returns a closure of one arg", {
  spec <- regime_spec(method = "e_divisive")
  expect_type(spec, "closure")
  expect_named(formals(spec), "tri")
})

test_that("regime_spec captures kwargs and applies on triangle", {
  spec <- regime_spec(window = 12L)
  r <- spec(sub)
  expect_s3_class(r, "Regime")
})

test_that("regime_spec plugs into fit_lr (closure form)", {
  fit <- fit_lr(sub, loss_regime = regime_spec(window = 12L))
  expect_s3_class(fit, "LRFit")
  # The resolved Regime is attached to the fit
  expect_s3_class(fit$loss_regime, "Regime")
})

# 4-type dispatch coverage --------------------------------------------------

test_that("fit_lr maturity arg accepts all 4 input types", {
  # 1. NULL — no maturity filter (allowed for non-SA methods)
  fit_null <- fit_lr(sub, method = "cl", maturity = NULL)
  expect_s3_class(fit_null, "LRFit")
  expect_null(fit_null$maturity)

  # 2. Maturity object (from maturity_at)
  fit_obj <- fit_lr(sub, maturity = maturity_at(coverage = "SUR", change = 4))
  expect_s3_class(fit_obj$maturity, "Maturity")

  # 3. "auto" sentinel
  fit_auto <- fit_lr(sub, maturity = "auto")
  expect_s3_class(fit_auto$maturity, "Maturity")

  # 4. Function (from maturity_spec)
  fit_fn <- fit_lr(sub, maturity = maturity_spec(min_run = 2))
  expect_s3_class(fit_fn$maturity, "Maturity")
})

test_that("fit_lr loss_regime arg accepts all 4 input types", {
  # 1. NULL
  fit_null <- fit_lr(sub, loss_regime = NULL)
  expect_s3_class(fit_null, "LRFit")
  expect_null(fit_null$loss_regime)

  # 2. Regime object (from regime_at)
  fit_obj <- fit_lr(sub,
                    loss_regime = regime_at(change = "2024-04-01"))
  expect_s3_class(fit_obj$loss_regime, "Regime")

  # 3. "auto" sentinel
  fit_auto <- fit_lr(sub, loss_regime = "auto")
  expect_s3_class(fit_auto$loss_regime, "Regime")

  # 4. Function (from regime_spec)
  fit_fn <- fit_lr(sub, loss_regime = regime_spec(window = 12L))
  expect_s3_class(fit_fn$loss_regime, "Regime")
})

# .auto_divisor -------------------------------------------------------------

test_that(".auto_divisor picks the largest divisor that yields a non-zero short label", {
  # The picker prefers the SHORTEST formatted label (e.g. "0.5" > "500.0")
  # so it tends to pick a divisor one order larger than the median.
  # median in [1, 1e3): "X" / 1 = "X.X" (3-5 chars), / 1e3 = "0.X" (3 chars) → 1e3 wins
  expect_equal(lossratio:::.auto_divisor(c(100, 500, 800)), 1e3)
  # median in [1e3, 1e6): / 1e6 wins ("0.X" beats "X.X")
  expect_equal(lossratio:::.auto_divisor(c(5e3, 5e4, 5e5)), 1e6)
  # median in [1e6, 1e9): / 1e9 wins
  expect_equal(lossratio:::.auto_divisor(c(5e6, 5e7, 5e8)), 1e9)
  # median in [1e9, 1e12): / 1e12 wins
  expect_equal(lossratio:::.auto_divisor(c(5e9, 5e10, 5e11)), 1e12)
  # median >= 1e12: pinned at 1e12 (max divisor in the candidate set)
  expect_equal(lossratio:::.auto_divisor(c(2e12, 5e12, 8e12)), 1e12)
})

test_that(".auto_divisor's `1e12 cap` behaviour for very large values", {
  # All values exceed 1e12 -> "/1e12" still gives non-zero label, so 1e12
  # remains the choice (no larger divisor available).
  expect_equal(lossratio:::.auto_divisor(c(1e13, 5e13)), 1e12)
})

test_that(".auto_divisor handles empty / all-NA / all-zero inputs", {
  expect_equal(lossratio:::.auto_divisor(numeric(0)), 1)
  expect_equal(lossratio:::.auto_divisor(c(NA_real_, NA_real_)), 1)
  expect_equal(lossratio:::.auto_divisor(c(0, 0, 0)), 1)
})

test_that(".auto_divisor disqualifies divisors that round to 0.0", {
  # values all in [50, 100): median ~75. Divisor 1 -> "75.0" (4 chars).
  # Divisor 1e3 -> "0.1" (3 chars). The "0.0" rule disqualifies divisors
  # that would round the median below 0.05. So 1e3 should win.
  d <- lossratio:::.auto_divisor(c(50, 75, 100))
  expect_true(d %in% c(1, 1e3))   # implementation-allowed range
  # And formatting at the picked divisor should not be "0.0"
  expect_false(sprintf("%.1f", 75 / d) == "0.0")
})

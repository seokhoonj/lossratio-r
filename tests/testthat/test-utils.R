test_that(".apply_recent_filter with dev_min keeps early-dev cells", {
  dt <- data.table::data.table(
    cohort = rep(seq.Date(as.Date("2023-01-01"), by = "month",
                          length.out = 10), each = 5),
    dev    = rep(1:5, times = 10)
  )
  out_no_min <- lossratio:::.apply_recent_filter(
    dt, recent = 4L, coh = "cohort", dev = "dev"
  )
  out_with_min <- lossratio:::.apply_recent_filter(
    dt, recent = 4L, coh = "cohort", dev = "dev", dev_split = 3L
  )
  # all cells with dev <= 3 must be in out_with_min
  expect_true(all(dt[dev <= 3L]$cohort %in% out_with_min$cohort |
                   nrow(out_with_min[dev <= 3L]) == nrow(dt[dev <= 3L])))
  expect_lte(nrow(out_no_min), nrow(out_with_min))
})

test_that(".apply_regime_filter with single Date drops pre-break cohorts", {
  dt <- data.table::data.table(
    cohort = rep(seq.Date(as.Date("2023-01-01"), by = "month",
                          length.out = 10), each = 5),
    dev    = rep(1:5, times = 10)
  )
  out <- lossratio:::.apply_regime_filter(
    dt, regime_break = "2023-06-01",
    coh = "cohort", dev = "dev"
  )
  expect_true(all(out$cohort >= as.Date("2023-06-01")))
})

test_that(".apply_regime_filter with Regime extracts last breakpoint", {
  reg <- structure(
    list(breakpoints = as.Date(c("2023-03-01", "2023-08-01"))),
    class = "Regime"
  )
  dt <- data.table::data.table(
    cohort = rep(seq.Date(as.Date("2023-01-01"), by = "month",
                          length.out = 10), each = 5),
    dev    = rep(1:5, times = 10)
  )
  out <- lossratio:::.apply_regime_filter(
    dt, regime_break = reg, coh = "cohort", dev = "dev"
  )
  expect_true(all(out$cohort >= as.Date("2023-08-01")))
})

test_that(".apply_regime_filter with dev_split keeps CL-region cells", {
  dt <- data.table::data.table(
    cohort = rep(seq.Date(as.Date("2023-01-01"), by = "month",
                          length.out = 10), each = 5),
    dev    = rep(1:5, times = 10)
  )
  # dev_split = 4: ED region is dev < 4 (dev = 1, 2, 3); CL region is
  # dev >= 4 (dev = 4, 5). Cohort filter applies only to ED region.
  out <- lossratio:::.apply_regime_filter(
    dt, regime_break = "2023-06-01",
    coh = "cohort", dev = "dev", dev_split = 4L
  )
  # CL region (dev >= 4) must include pre-break cohorts (kept regardless).
  expect_true(any(out$cohort < as.Date("2023-06-01") & out$dev >= 4L))
  # ED region (dev < 4) must NOT include pre-break cohorts (filtered).
  expect_false(any(out$cohort < as.Date("2023-06-01") & out$dev < 4L))
})

test_that(".apply_regime_filter with NULL/empty returns unchanged", {
  dt <- data.table::data.table(cohort = as.Date("2023-01-01"), dev = 1L)
  expect_equal(nrow(lossratio:::.apply_regime_filter(dt, NULL,
                      coh = "cohort", dev = "dev")), 1L)
  reg_empty <- structure(list(breakpoints = as.Date(character(0))),
                         class = "Regime")
  expect_equal(nrow(lossratio:::.apply_regime_filter(dt, reg_empty,
                      coh = "cohort", dev = "dev")), 1L)
})

test_that(".apply_regime_filter with vector uses latest date", {
  dt <- data.table::data.table(
    cohort = rep(seq.Date(as.Date("2023-01-01"), by = "month",
                          length.out = 10), each = 5),
    dev    = rep(1:5, times = 10)
  )
  out <- lossratio:::.apply_regime_filter(
    dt, regime_break = c("2023-03-01", "2023-08-01"),
    coh = "cohort", dev = "dev"
  )
  expect_true(all(out$cohort >= as.Date("2023-08-01")))
})

test_that(".apply_regime_filter with multi-group Regime dispatches per group", {
  # Two groups, distinct breakpoints
  bp <- data.table::data.table(
    coverage   = c("A", "B"),
    breakpoint = as.Date(c("2023-04-01", "2023-08-01")),
    regime_id  = c(2L, 2L),
    pre_value  = c(0.5, 0.6),
    post_value = c(0.7, 0.8),
    magnitude  = c(0.2, 0.2)
  )
  reg <- structure(
    list(breakpoints = bp,
         multi_group = TRUE,
         groups      = "coverage"),
    class = "Regime"
  )

  dt <- data.table::data.table(
    coverage = rep(c("A", "B"), each = 50),
    cohort   = rep(rep(seq.Date(as.Date("2023-01-01"), by = "month",
                                length.out = 10), each = 5), times = 2),
    dev      = rep(rep(1:5, times = 10), times = 2)
  )

  out <- lossratio:::.apply_regime_filter(
    dt, regime_break = reg,
    grp = "coverage",
    coh = "cohort", dev = "dev"
  )

  # Group A: cohorts >= 2023-04-01
  expect_true(all(out[coverage == "A"]$cohort >= as.Date("2023-04-01")))
  # Group B: cohorts >= 2023-08-01
  expect_true(all(out[coverage == "B"]$cohort >= as.Date("2023-08-01")))
})

test_that(".apply_regime_filter per-group keeps groups not in regime_break", {
  # Regime only knows about group A; group B should pass through unfiltered.
  bp <- data.table::data.table(
    coverage   = "A",
    breakpoint = as.Date("2023-08-01"),
    regime_id  = 2L,
    pre_value  = 0.5,
    post_value = 0.7,
    magnitude  = 0.2
  )
  reg <- structure(
    list(breakpoints = bp,
         multi_group = TRUE,
         groups      = "coverage"),
    class = "Regime"
  )

  dt <- data.table::data.table(
    coverage = rep(c("A", "B"), each = 50),
    cohort   = rep(rep(seq.Date(as.Date("2023-01-01"), by = "month",
                                length.out = 10), each = 5), times = 2),
    dev      = rep(rep(1:5, times = 10), times = 2)
  )

  out <- lossratio:::.apply_regime_filter(
    dt, regime_break = reg,
    grp = "coverage",
    coh = "cohort", dev = "dev"
  )

  # Group A is filtered; group B keeps all rows
  expect_true(all(out[coverage == "A"]$cohort >= as.Date("2023-08-01")))
  expect_equal(nrow(out[coverage == "B"]), 50L)
})

test_that(".apply_recent_filter with dev_min keeps early-dev cells", {
  dt <- data.table::data.table(
    cohort = rep(seq.Date(as.Date("2023-01-01"), by = "month",
                          length.out = 10), each = 5),
    dev    = rep(1:5, times = 10)
  )
  out_no_min <- lossratio:::.apply_recent_filter(
    dt, recent = 4L, cohort_var = "cohort", dev_var = "dev"
  )
  out_with_min <- lossratio:::.apply_recent_filter(
    dt, recent = 4L, cohort_var = "cohort", dev_var = "dev", dev_split = 3L
  )
  # all cells with dev <= 3 must be in out_with_min
  expect_true(all(dt[dev <= 3L]$cohort %in% out_with_min$cohort |
                   nrow(out_with_min[dev <= 3L]) == nrow(dt[dev <= 3L])))
  expect_lte(nrow(out_no_min), nrow(out_with_min))
})

test_that(".apply_break_filter with single Date drops pre-break cohorts", {
  dt <- data.table::data.table(
    cohort = rep(seq.Date(as.Date("2023-01-01"), by = "month",
                          length.out = 10), each = 5),
    dev    = rep(1:5, times = 10)
  )
  out <- lossratio:::.apply_break_filter(
    dt, break_date = "2023-06-01",
    cohort_var = "cohort", dev_var = "dev"
  )
  expect_true(all(out$cohort >= as.Date("2023-06-01")))
})

test_that(".apply_break_filter with Regime extracts last breakpoint", {
  reg <- structure(
    list(breakpoints = as.Date(c("2023-03-01", "2023-08-01"))),
    class = "Regime"
  )
  dt <- data.table::data.table(
    cohort = rep(seq.Date(as.Date("2023-01-01"), by = "month",
                          length.out = 10), each = 5),
    dev    = rep(1:5, times = 10)
  )
  out <- lossratio:::.apply_break_filter(
    dt, break_date = reg, cohort_var = "cohort", dev_var = "dev"
  )
  expect_true(all(out$cohort >= as.Date("2023-08-01")))
})

test_that(".apply_break_filter with dev_split keeps CL-region cells", {
  dt <- data.table::data.table(
    cohort = rep(seq.Date(as.Date("2023-01-01"), by = "month",
                          length.out = 10), each = 5),
    dev    = rep(1:5, times = 10)
  )
  # dev_split = 4: ED region is dev < 4 (dev = 1, 2, 3); CL region is
  # dev >= 4 (dev = 4, 5). Cohort filter applies only to ED region.
  out <- lossratio:::.apply_break_filter(
    dt, break_date = "2023-06-01",
    cohort_var = "cohort", dev_var = "dev", dev_split = 4L
  )
  # CL region (dev >= 4) must include pre-break cohorts (kept regardless).
  expect_true(any(out$cohort < as.Date("2023-06-01") & out$dev >= 4L))
  # ED region (dev < 4) must NOT include pre-break cohorts (filtered).
  expect_false(any(out$cohort < as.Date("2023-06-01") & out$dev < 4L))
})

test_that(".apply_break_filter with NULL/empty returns unchanged", {
  dt <- data.table::data.table(cohort = as.Date("2023-01-01"), dev = 1L)
  expect_equal(nrow(lossratio:::.apply_break_filter(dt, NULL,
                      cohort_var = "cohort", dev_var = "dev")), 1L)
  reg_empty <- structure(list(breakpoints = as.Date(character(0))),
                         class = "Regime")
  expect_equal(nrow(lossratio:::.apply_break_filter(dt, reg_empty,
                      cohort_var = "cohort", dev_var = "dev")), 1L)
})

test_that(".apply_break_filter with vector uses latest date", {
  dt <- data.table::data.table(
    cohort = rep(seq.Date(as.Date("2023-01-01"), by = "month",
                          length.out = 10), each = 5),
    dev    = rep(1:5, times = 10)
  )
  out <- lossratio:::.apply_break_filter(
    dt, break_date = c("2023-03-01", "2023-08-01"),
    cohort_var = "cohort", dev_var = "dev"
  )
  expect_true(all(out$cohort >= as.Date("2023-08-01")))
})

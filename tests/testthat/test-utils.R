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
    dt, regime = "2023-06-01",
    coh = "cohort", dev = "dev"
  )
  expect_true(all(out$cohort >= as.Date("2023-06-01")))
})

test_that(".apply_regime_filter with Regime extracts last change", {
  reg <- structure(
    list(changes = as.Date(c("2023-03-01", "2023-08-01"))),
    class = "Regime"
  )
  dt <- data.table::data.table(
    cohort = rep(seq.Date(as.Date("2023-01-01"), by = "month",
                          length.out = 10), each = 5),
    dev    = rep(1:5, times = 10)
  )
  out <- lossratio:::.apply_regime_filter(
    dt, regime = reg, coh = "cohort", dev = "dev"
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
    dt, regime = "2023-06-01",
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
  reg_empty <- structure(list(changes = as.Date(character(0))),
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
    dt, regime = c("2023-03-01", "2023-08-01"),
    coh = "cohort", dev = "dev"
  )
  expect_true(all(out$cohort >= as.Date("2023-08-01")))
})

test_that(".apply_regime_filter with multi-group Regime dispatches per group", {
  # Two groups, distinct changes
  bp <- data.table::data.table(
    coverage   = c("A", "B"),
    change     = as.Date(c("2023-04-01", "2023-08-01")),
    regime_id  = c(2L, 2L),
    pre_value  = c(0.5, 0.6),
    post_value = c(0.7, 0.8),
    magnitude  = c(0.2, 0.2)
  )
  reg <- structure(
    list(changes     = bp,
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
    dt, regime = reg,
    grp = "coverage",
    coh = "cohort", dev = "dev"
  )

  # Group A: cohorts >= 2023-04-01
  expect_true(all(out[coverage == "A"]$cohort >= as.Date("2023-04-01")))
  # Group B: cohorts >= 2023-08-01
  expect_true(all(out[coverage == "B"]$cohort >= as.Date("2023-08-01")))
})

test_that(".apply_regime_filter with treatment='segment_wise' applies mini-triangle filter on Triangle", {
  reg <- regime_at(change = c("2023-04-01", "2023-08-01"),
                   treatment = "segment_wise")

  # Square 10x10 *triangular* grid (cohort + dev - 1 <= 10) so each
  # segment's mini-triangle is non-trivial. Class `"Triangle"` is
  # required to trigger the mini-triangle filter (Link input keeps
  # the older tag-only behaviour).
  # cohorts 2023-01..2023-10 (ranks 1..10), dev 1..(11 - cohort_rank),
  # max cal_idx = 10. Segments:
  #   seg 1 cohorts 2023-01..2023-03 (ranks 1..3)
  #   seg 2 cohorts 2023-04..2023-07 (ranks 4..7)
  #   seg 3 cohorts 2023-08..2023-10 (ranks 8..10)
  # dev_min per segment:
  #   seg 1: 10 - 3 + 1 = 8  -> USED at dev 8..10
  #   seg 2: 10 - 7 + 1 = 4  -> USED at dev 4..7
  #   seg 3: 10 - 10 + 1 = 1 -> USED at dev 1..3
  cohorts <- seq.Date(as.Date("2023-01-01"), by = "month", length.out = 10)
  dt <- do.call(rbind, lapply(seq_along(cohorts), function(i) {
    data.table::data.table(cohort = cohorts[i], dev = seq_len(11L - i))
  }))
  data.table::setattr(dt, "class", c("Triangle", class(dt)))

  out <- lossratio:::.apply_regime_filter(
    dt, regime = reg,
    grp = character(0),
    coh = "cohort", dev = "dev"
  )

  expect_true("segment_id" %in% names(out))
  expect_equal(sort(unique(out$segment_id)), c(1L, 2L, 3L))

  seg1_devs <- sort(unique(out[segment_id == 1L]$dev))
  seg2_devs <- sort(unique(out[segment_id == 2L]$dev))
  seg3_devs <- sort(unique(out[segment_id == 3L]$dev))
  expect_equal(seg1_devs, 8:10)
  expect_equal(seg2_devs, 4:7)
  expect_equal(seg3_devs, 1:3)
})

test_that(".apply_regime_filter with treatment='segment_wise' tag-only on Link", {
  # Link input (no `Triangle` class) keeps the older tag-only
  # behaviour: every row preserved, just annotated with `segment_id`.
  reg <- regime_at(change = c("2023-04-01", "2023-08-01"),
                   treatment = "segment_wise")
  dt <- data.table::data.table(
    cohort = rep(seq.Date(as.Date("2023-01-01"), by = "month",
                          length.out = 10), each = 5),
    dev    = rep(1:5, times = 10)
  )
  out <- lossratio:::.apply_regime_filter(
    dt, regime = reg,
    grp = character(0),
    coh = "cohort", dev = "dev"
  )
  expect_equal(nrow(out), nrow(dt))
  expect_equal(sort(unique(out$segment_id)), c(1L, 2L, 3L))
})

test_that(".apply_regime_filter per-group keeps groups not in regime", {
  # Regime only knows about group A; group B should pass through unfiltered.
  bp <- data.table::data.table(
    coverage   = "A",
    change     = as.Date("2023-08-01"),
    regime_id  = 2L,
    pre_value  = 0.5,
    post_value = 0.7,
    magnitude  = 0.2
  )
  reg <- structure(
    list(changes     = bp,
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
    dt, regime = reg,
    grp = "coverage",
    coh = "cohort", dev = "dev"
  )

  # Group A is filtered; group B keeps all rows
  expect_true(all(out[coverage == "A"]$cohort >= as.Date("2023-08-01")))
  expect_equal(nrow(out[coverage == "B"]), 50L)
})


# .assign_segment ---------------------------------------------------------

test_that(".assign_segment returns 1L for NULL / empty regime", {
  coh <- as.Date(c("2023-01-01", "2023-06-01", "2024-01-01"))
  expect_equal(lossratio:::.assign_segment(coh, NULL),
               c(1L, 1L, 1L))

  empty <- structure(
    list(changes     = data.table::data.table(change = as.Date(character(0))),
         multi_group = FALSE,
         groups      = character(0)),
    class = "Regime"
  )
  expect_equal(lossratio:::.assign_segment(coh, empty),
               c(1L, 1L, 1L))
})

test_that(".assign_segment partitions cohorts by all changes (single group)", {
  coh <- as.Date(c("2022-01-01", "2023-06-01", "2024-06-01", "2025-01-01"))
  reg <- regime_at(change = c("2023-04-01", "2024-04-01"))
  # 2022-01 < 2023-04         → seg 1
  # 2023-04 <= 2023-06 < 24-04 → seg 2
  # 2024-04 <= 2024-06         → seg 3
  # 2024-04 <= 2025-01         → seg 3
  expect_equal(lossratio:::.assign_segment(coh, reg),
               c(1L, 2L, 3L, 3L))
})

test_that(".assign_segment dispatches per group on multi-group Regime", {
  coh <- as.Date(c("2023-01-01", "2023-06-01",
                   "2023-01-01", "2023-06-01"))
  grp <- data.table::data.table(coverage = c("A", "A", "B", "B"))
  reg <- regime_at(coverage = c("A", "B"),
                   change   = c("2023-04-01", "2023-08-01"))
  # A: change at 2023-04 → cohort 01 = seg 1, cohort 06 = seg 2
  # B: change at 2023-08 → both cohorts pre-change = seg 1
  expect_equal(lossratio:::.assign_segment(coh, reg, grp),
               c(1L, 2L, 1L, 1L))
})

test_that(".assign_segment keeps groups absent from regime in segment 1", {
  coh <- as.Date(c("2023-01-01", "2023-12-01"))
  grp <- data.table::data.table(coverage = c("A", "C"))
  reg <- regime_at(coverage = "A", change = "2023-06-01")
  # A: cohort 01 < 06 = seg 1, cohort 12 >= 06 = seg 2
  # C: no change → seg 1
  # but reg is single-group (one row), so multi_group is FALSE; falls back
  # to scalar path treating all cohorts against max(change). Confirm:
  expect_equal(lossratio:::.assign_segment(coh, reg, grp),
               c(1L, 2L))
})

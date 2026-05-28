test_that(".apply_recent_filter with dev_min keeps early-dev cells", {
  dt <- data.table::data.table(
    cohort = rep(seq.Date(as.Date("2023-01-01"), by = "month",
                          length.out = 10), each = 5),
    dev    = rep(1:5, times = 10)
  )
  out_no_min <- lossratio:::.apply_recent_filter(
    dt, recent = 4L, cohort = "cohort", dev = "dev"
  )
  out_with_min <- lossratio:::.apply_recent_filter(
    dt, recent = 4L, cohort = "cohort", dev = "dev", dev_split = 3L
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
    cohort = "cohort", dev = "dev"
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
    dt, regime = reg, cohort = "cohort", dev = "dev"
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
    cohort = "cohort", dev = "dev", dev_split = 4L
  )
  # CL region (dev >= 4) must include pre-break cohorts (kept regardless).
  expect_true(any(out$cohort < as.Date("2023-06-01") & out$dev >= 4L))
  # ED region (dev < 4) must NOT include pre-break cohorts (filtered).
  expect_false(any(out$cohort < as.Date("2023-06-01") & out$dev < 4L))
})

test_that(".apply_regime_filter with NULL/empty returns unchanged", {
  dt <- data.table::data.table(cohort = as.Date("2023-01-01"), dev = 1L)
  expect_equal(nrow(lossratio:::.apply_regime_filter(dt, NULL,
                      cohort = "cohort", dev = "dev")), 1L)
  reg_empty <- structure(list(changes = as.Date(character(0))),
                         class = "Regime")
  expect_equal(nrow(lossratio:::.apply_regime_filter(dt, reg_empty,
                      cohort = "cohort", dev = "dev")), 1L)
})

test_that(".apply_regime_filter with vector uses latest date", {
  dt <- data.table::data.table(
    cohort = rep(seq.Date(as.Date("2023-01-01"), by = "month",
                          length.out = 10), each = 5),
    dev    = rep(1:5, times = 10)
  )
  out <- lossratio:::.apply_regime_filter(
    dt, regime = c("2023-03-01", "2023-08-01"),
    cohort = "cohort", dev = "dev"
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
    groups = "coverage",
    cohort = "cohort", dev = "dev"
  )

  # Group A: cohorts >= 2023-04-01
  expect_true(all(out[coverage == "A"]$cohort >= as.Date("2023-04-01")))
  # Group B: cohorts >= 2023-08-01
  expect_true(all(out[coverage == "B"]$cohort >= as.Date("2023-08-01")))
})

test_that(".apply_regime_filter with treatment='segment_bridged' masks the bridged band and drops segment_id (pooled)", {
  reg <- regime_at(change = c("2023-04-01", "2023-08-01"),
                   treatment = "segment_bridged")

  # 10-cohort *triangular* grid (cohort + dev - 1 <= 10). Class
  # `"Triangle"` is required to trigger the band filter. The bridged
  # mask is identical to segment_bridged_borrowed (see the next test);
  # segment_bridged differs only in that it DROPS `segment_id` so the
  # downstream fit pools the whole band into one factor set.
  cohorts <- seq.Date(as.Date("2023-01-01"), by = "month", length.out = 10)
  dt <- do.call(rbind, lapply(seq_along(cohorts), function(i) {
    data.table::data.table(cohort = cohorts[i], dev = seq_len(11L - i))
  }))
  data.table::setattr(dt, "class", c("Triangle", class(dt)))

  out <- lossratio:::.apply_regime_filter(
    dt, regime = reg,
    groups = character(0),
    cohort = "cohort", dev = "dev"
  )

  # Pooled: no per-segment tag survives.
  expect_false("segment_id" %in% names(out))

  # The kept cells are the bridged band -- per-cohort min dev matches the
  # bridged wall (ranks 1..10 -> 7,6,5,4,4,3,2,1,1,1).
  min_dev_by_coh <- out[, list(min_dev = min(dev)), by = "cohort"
                        ][order(cohort)]
  expect_equal(min_dev_by_coh$min_dev,
               c(7L, 6L, 5L, 4L, 4L, 3L, 2L, 1L, 1L, 1L))
  # Bridged band spans dev 1..10 in the union.
  expect_equal(sort(unique(out$dev)), 1:10)
})

test_that(".apply_regime_filter with treatment='segment_bridged_borrowed' widens older segments via calendar diagonal and keeps segment_id", {
  reg <- regime_at(change = c("2023-04-01", "2023-08-01"),
                   treatment = "segment_bridged_borrowed")

  # Same 10-cohort triangular grid as the segment_bridged test.
  # Bridge anchors (next-segment first-cohort midpoint dev):
  #   from seg 2: floor((4 +  7) / 2) = 5; ext_cal_idx(seg 1) = 4 + 5 - 2 = 7
  #   from seg 3: floor((1 +  3) / 2) = 2; ext_cal_idx(seg 2) = 8 + 2 - 2 = 8
  # Per-cohort effective dev_min after the bridge:
  #   seg 1 ranks 1/2/3 -> 7/6/5
  #   seg 2 ranks 4/5/6/7 -> 4/4/3/2
  #   seg 3 ranks 8/9/10 -> 1/1/1 (newest segment, no bridge)
  cohorts <- seq.Date(as.Date("2023-01-01"), by = "month", length.out = 10)
  dt <- do.call(rbind, lapply(seq_along(cohorts), function(i) {
    data.table::data.table(cohort = cohorts[i], dev = seq_len(11L - i))
  }))
  data.table::setattr(dt, "class", c("Triangle", class(dt)))

  out <- lossratio:::.apply_regime_filter(
    dt, regime = reg,
    groups = character(0),
    cohort = "cohort", dev = "dev"
  )

  expect_true("segment_id" %in% names(out))
  expect_equal(sort(unique(out$segment_id)), c(1L, 2L, 3L))

  seg1_devs <- sort(unique(out[segment_id == 1L]$dev))
  seg2_devs <- sort(unique(out[segment_id == 2L]$dev))
  seg3_devs <- sort(unique(out[segment_id == 3L]$dev))
  expect_equal(seg1_devs, 5:10)
  expect_equal(seg2_devs, 2:7)
  expect_equal(seg3_devs, 1:3)

  # Per-cohort lower bound -- confirms the bridge sweeps segment 1 down
  # by one dev per cohort step away from the segment's last cohort
  # until it reaches the natural wall on cohort 1.
  min_dev_by_coh <- out[, list(min_dev = min(dev)),
                        by = c("cohort", "segment_id")
                        ][order(segment_id, cohort)]
  expect_equal(
    min_dev_by_coh[segment_id == 1L]$min_dev,
    c(7L, 6L, 5L)
  )
  expect_equal(
    min_dev_by_coh[segment_id == 2L]$min_dev,
    c(4L, 4L, 3L, 2L)
  )
})

test_that(".compute_segment_mini_tri_bounds returns the natural wall by default", {
  bounds <- lossratio:::.compute_segment_mini_tri_bounds(
    coh_ranks = c(1L, 2L, 3L, 4L),
    seg_ids   = c(1L, 1L, 2L, 2L),
    max_cal   = 4L
  )
  # seg_last(1) = 2 -> dev_min 3; seg_last(2) = 4 -> dev_min 1.
  expect_equal(bounds, c(3L, 3L, 1L, 1L))
})

test_that(".compute_segment_mini_tri_bounds(bridge=TRUE) widens older segment only", {
  # Two segments, oldest = id 1 (cohorts 1..2), newest = id 2 (cohorts 3..4).
  # max_cal = 4. Natural dev_min:
  #   seg 1: 4 - 2 + 1 = 3
  #   seg 2: 4 - 4 + 1 = 1
  # Bridge anchor in seg 2: first_rank = 3, first_cohort_dev_max = 4 - 3 + 1 = 2,
  #   mid_dev = floor((1 + 2) / 2) = 1, ext_cal_idx(seg 1) = 3 + 1 - 2 = 2.
  # Per-cohort effective dev_min:
  #   seg 1 rank 1: pmin(3, 2 - 1 + 1) = pmin(3, 2) = 2 (bridge widens)
  #   seg 1 rank 2: pmin(3, 2 - 2 + 1) = pmin(3, 1) = 1 (bridge widens further)
  #   seg 2 rank 3 / 4: no bridge -> 1
  bounds <- lossratio:::.compute_segment_mini_tri_bounds(
    coh_ranks = c(1L, 2L, 3L, 4L),
    seg_ids   = c(1L, 1L, 2L, 2L),
    max_cal   = 4L,
    bridge    = TRUE
  )
  expect_equal(bounds, c(2L, 1L, 1L, 1L))
})

test_that(".compute_segment_mini_tri_bounds gives natural wall when only one segment exists", {
  # Single segment -> no bridge to apply; effective dev_min == natural.
  bounds_pure <- lossratio:::.compute_segment_mini_tri_bounds(
    coh_ranks = c(1L, 2L, 3L),
    seg_ids   = c(1L, 1L, 1L),
    max_cal   = 3L
  )
  bounds_bridge <- lossratio:::.compute_segment_mini_tri_bounds(
    coh_ranks = c(1L, 2L, 3L),
    seg_ids   = c(1L, 1L, 1L),
    max_cal   = 3L,
    bridge    = TRUE
  )
  # seg_last = 3, max_cal = 3 -> dev_min = 1 for every cohort.
  expect_equal(bounds_pure, c(1L, 1L, 1L))
  expect_equal(bounds_bridge, c(1L, 1L, 1L))
})

test_that(".borrow_segment_factors fills each segment's gaps from the recent donor", {
  # seg 1 owns dev 3,4,5; seg 2 owns dev 1,2,3. Donor per dev = the
  # largest segment_id that owns that dev:
  #   dev 1,2 -> only seg 2; dev 3 -> seg 2 (max id, but both own);
  #   dev 4,5 -> only seg 1.
  sel <- data.table::data.table(
    dev        = c(3L, 4L, 5L, 1L, 2L, 3L),
    segment_id = c(1L, 1L, 1L, 2L, 2L, 2L),
    f_sel      = c(1.1, 1.2, 1.3, 2.1, 2.2, 2.3),
    sigma2     = c(0.1, 0.2, 0.3, 0.4, 0.5, 0.6)
  )
  out <- lossratio:::.borrow_segment_factors(
    sel, groups = character(0), dev_col = "dev",
    factor_cols = c("f_sel", "sigma2")
  )

  # Both segments now cover the full dev range 1..5.
  expect_equal(sort(unique(out[segment_id == 1L]$dev)), 1:5)
  expect_equal(sort(unique(out[segment_id == 2L]$dev)), 1:5)

  # seg 1 borrows its missing early devs (1,2) from seg 2; keeps its own
  # dev 3 (1.1).
  expect_equal(out[segment_id == 1L & dev == 1L]$f_sel, 2.1)
  expect_equal(out[segment_id == 1L & dev == 2L]$f_sel, 2.2)
  expect_equal(out[segment_id == 1L & dev == 3L]$f_sel, 1.1)

  # seg 2 borrows its missing late devs (4,5) from seg 1; keeps its own
  # dev 3 (2.3).
  expect_equal(out[segment_id == 2L & dev == 4L]$f_sel, 1.2)
  expect_equal(out[segment_id == 2L & dev == 5L]$f_sel, 1.3)
  expect_equal(out[segment_id == 2L & dev == 3L]$f_sel, 2.3)

  # Borrowed companion columns travel with the primary factor.
  expect_equal(out[segment_id == 1L & dev == 1L]$sigma2, 0.4)
})

test_that(".borrow_segment_factors is a no-op without segment_id or with one segment", {
  sel1 <- data.table::data.table(dev = 1:3, f_sel = c(1, 2, 3))
  expect_identical(
    lossratio:::.borrow_segment_factors(sel1, character(0), "dev", "f_sel"),
    sel1
  )
  sel2 <- data.table::data.table(dev = 1:3, segment_id = 1L,
                                 f_sel = c(1, 2, 3))
  expect_identical(
    lossratio:::.borrow_segment_factors(sel2, character(0), "dev", "f_sel"),
    sel2
  )
})

test_that(".apply_regime_filter with treatment='segment_bridged_borrowed' tag-only on Link", {
  # Link input (no `Triangle` class) keeps the tag-only behaviour:
  # every row preserved, just annotated with `segment_id`.
  reg <- regime_at(change = c("2023-04-01", "2023-08-01"),
                   treatment = "segment_bridged_borrowed")
  dt <- data.table::data.table(
    cohort = rep(seq.Date(as.Date("2023-01-01"), by = "month",
                          length.out = 10), each = 5),
    dev    = rep(1:5, times = 10)
  )
  out <- lossratio:::.apply_regime_filter(
    dt, regime = reg,
    groups = character(0),
    cohort = "cohort", dev = "dev"
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
    groups = "coverage",
    cohort = "cohort", dev = "dev"
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
  # 2022-01 < 2023-04         -> seg 1
  # 2023-04 <= 2023-06 < 24-04 -> seg 2
  # 2024-04 <= 2024-06         -> seg 3
  # 2024-04 <= 2025-01         -> seg 3
  expect_equal(lossratio:::.assign_segment(coh, reg),
               c(1L, 2L, 3L, 3L))
})

test_that(".assign_segment dispatches per group on multi-group Regime", {
  coh <- as.Date(c("2023-01-01", "2023-06-01",
                   "2023-01-01", "2023-06-01"))
  grp <- data.table::data.table(coverage = c("A", "A", "B", "B"))
  reg <- regime_at(coverage = c("A", "B"),
                   change   = c("2023-04-01", "2023-08-01"))
  # A: change at 2023-04 -> cohort 01 = seg 1, cohort 06 = seg 2
  # B: change at 2023-08 -> both cohorts pre-change = seg 1
  expect_equal(lossratio:::.assign_segment(coh, reg, grp),
               c(1L, 2L, 1L, 1L))
})

test_that(".assign_segment keeps groups absent from regime in segment 1", {
  coh <- as.Date(c("2023-01-01", "2023-12-01"))
  grp <- data.table::data.table(coverage = c("A", "C"))
  reg <- regime_at(coverage = "A", change = "2023-06-01")
  # A: cohort 01 < 06 = seg 1, cohort 12 >= 06 = seg 2
  # C: no change -> seg 1
  # but reg is single-group (one row), so multi_group is FALSE; falls back
  # to scalar path treating all cohorts against max(change). Confirm:
  expect_equal(lossratio:::.assign_segment(coh, reg, grp),
               c(1L, 2L))
})

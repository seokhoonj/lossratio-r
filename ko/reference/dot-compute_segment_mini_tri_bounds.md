# Per-cell effective `dev_min` for the segment mini-triangle band

For each cell, returns the minimum dev that keeps it inside its
segment's fit mask. The mask is the union of two regions:

1.  The segment's natural mini-triangle:
    `dev >= max_cal - seg_last + 1`.

2.  A *bridge* extension along the calendar diagonal anchored at the
    *next* (newer) segment's first-cohort midpoint dev. The bridge lets
    each older segment connect to its successor, filling the late-dev
    cells of its early cohorts that would otherwise be cut by the
    natural mini-triangle wall and leave projection cells unreachable.

Bridge construction (segments ordered by `segment_id`, lower id = older
cohorts). For each segment `s` except the newest (no successor), find
segment `s+1`'s

- `first_rank` – cohort rank of `s+1`'s first cohort,

- `seg_dev_min` – `max_cal - last_rank(s+1) + 1`,

- `first_cohort_dev_max` – `max_cal - first_rank(s+1) + 1`,

- `mid_dev` – `floor((seg_dev_min + first_cohort_dev_max) / 2)`.

The bridge diagonal for segment `s` is at
`ext_cal_idx(s) = first_rank(s+1) + mid_dev(s+1) - 2` (the cell one
cohort earlier than `s+1`'s first cohort, at the same dev as that first
cohort's mini-triangle midpoint). Each cell in segment `s` then takes

`effective_dev_min = min(seg_dev_min(s), ext_cal_idx(s) - coh_rank + 1)`

with `pmin(..., na.rm = TRUE)` so the natural mini-tri wall stays put
when no bridge applies (the last segment, or cells whose bridge ray lies
above the wall).

Bridges do not cascade: segment `s` is bridged only from segment `s+1`,
not from `s+2`. The bridge only ever *widens* a segment's mini-triangle.

## Usage

``` r
.compute_segment_mini_tri_bounds(coh_ranks, seg_ids, max_cal, bridge = FALSE)
```

## Arguments

- coh_ranks:

  Integer vector. Per-cell cohort rank within the group.

- seg_ids:

  Integer vector. Per-cell segment id (1 = oldest).

- max_cal:

  Integer scalar. Maximum calendar index in the group.

- bridge:

  Logical. When `TRUE` (used by both segment treatments), widen each
  older segment's mini-triangle with the calendar-diagonal bridge
  anchored at the next segment's first-cohort midpoint dev. When
  `FALSE`, return the natural mini-triangle wall only (no boundary-gap
  closure); retained for diagnostics and tests.

## Value

Integer vector (same length as `coh_ranks`) of per-cell effective
`dev_min` for the mini-triangle filter (bridged or pure).

# Borrow missing per-segment factors across segments (segment_bridged_borrowed)

Augments a per-segment factor table so every segment carries a factor
for the full development range, borrowing the entries a segment cannot
estimate from a donor segment that can. Used only by the
`"segment_bridged_borrowed"` treatment: early-development factors stay
regime-specific (each segment's own estimate), while late-development
factors a segment never reaches are filled from another segment.

Donor rule (“recent”): for each `(group, dev)` the donor is the segment
with the *largest* `segment_id` that has a non-`NA` primary factor at
that dev – i.e. the most recent regime whose own cohorts developed that
far. The bridged band guarantees a donor exists at every dev that any
segment needs (the boundary factor gaps are closed by the bridge), so no
dev is left unfilled.

The borrow only *adds* rows for `(segment, dev)` combinations the
segment lacks; rows a segment owns are never overwritten.

## Usage

``` r
.borrow_segment_factors(sel, groups, dev_col, factor_cols)
```

## Arguments

- sel:

  A `data.table` of per-segment factors with columns `groups`,
  `dev_col`, `segment_id`, and `factor_cols` (plus optional `ata_to` /
  `ata_link` carried along).

- groups:

  Character vector of group columns (may be empty).

- dev_col:

  Single column name holding the development index (`"dev"` after the
  projection-time rename).

- factor_cols:

  Character vector of factor columns to borrow. The first element is the
  *primary* factor (`"f_sel"` / `"g_sel"`) whose non-`NA` presence
  defines whether a segment owns a dev.

## Value

`sel` augmented with borrowed rows so every `(group, segment, dev)`
present in the donor space is covered.

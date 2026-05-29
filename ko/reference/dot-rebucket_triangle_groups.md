# Internal: rebucket a `Triangle` to a coarser `groups` partition

Re-aggregates `loss` / `premium` / `incr_loss` / `incr_premium` over the
dropped grouping columns and recomputes `ratio` / `incr_ratio` as ratios
of the aggregated totals. Other cell-level columns (`margin`, `profit`,
`loss_share`, ...) are not regenerated – the rebucketed object is
intended for
[`as_link()`](https://seokhoonj.github.io/lossratio-r/ko/reference/as_link.md)
consumption only.

## Usage

``` r
.rebucket_triangle_groups(x, groups)
```

## Arguments

- x:

  A `Triangle` object.

- groups:

  `NULL`, `character(0)`, or a `character` subset of
  `attr(x, "groups")`. `NULL` returns `x` unchanged.

## Value

A `Triangle` with `attr(., "groups")` set to the requested value and
`loss` / `premium` / `ratio` aggregated to the requested partition.

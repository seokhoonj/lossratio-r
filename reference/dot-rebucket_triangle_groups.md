# Internal: rebucket a `Triangle` to a coarser `groups` partition

Re-aggregates `loss` / `premium` / `loss_incr` / `premium_incr` over the
dropped grouping columns and recomputes `lr` / `lr_incr` as ratios of
the aggregated totals. Other cell-level columns (`margin`, `profit`,
`loss_share`, ...) are not regenerated – the rebucketed object is
intended for
[`build_link()`](https://seokhoonj.github.io/lossratio/reference/build_link.md)
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
`loss` / `premium` / `lr` aggregated to the requested partition.

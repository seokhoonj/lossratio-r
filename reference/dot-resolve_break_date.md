# Resolve a regime-break specifier to a single Date

Internal helper used by
[`.apply_break_filter()`](https://seokhoonj.github.io/lossratio/reference/dot-apply_break_filter.md)
to coerce a heterogeneous `break_date` argument (NULL, Date
scalar/vector, character coercible to Date, or a `Regime` object) into a
single Date scalar (the latest break) or `NULL`.

## Usage

``` r
.resolve_break_date(break_date)
```

## Arguments

- break_date:

  See
  [`.apply_break_filter()`](https://seokhoonj.github.io/lossratio/reference/dot-apply_break_filter.md).

## Value

A single Date, or `NULL` when no break is specified.

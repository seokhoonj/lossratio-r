# Resolve the grouping columns of a Triangle / Link / fit object

Returns `attr(x, "groups")`, or `character(0)` when the attribute is
absent – the canonical "no groups" sentinel used throughout the package.

## Usage

``` r
.resolve_groups(x)
```

## Arguments

- x:

  An object carrying (or lacking) a `"groups"` attribute.

## Value

A character vector of group column names; `character(0)` when there are
none.

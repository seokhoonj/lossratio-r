# Group vector for a data.table `by =` argument

`data.table`'s `by =` wants `NULL` (not `character(0)`) to mean "no
grouping". This converts an empty group vector accordingly.

## Usage

``` r
.by_grp(grp)
```

## Arguments

- grp:

  Character vector of group column names, possibly empty.

## Value

`grp` unchanged, or `NULL` when `grp` is empty.

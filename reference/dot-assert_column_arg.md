# Validate a column-name argument

Internal helper used by entry-point functions (`build_triangle`,
`build_link`, `fit_cl`, ...) that take column names as plain character
arguments (no NSE). Performs:

- type check — must be a non-empty character vector

- optional length-one check — for arguments expected to resolve to a
  single column (e.g., `cohort`, `loss`)

- presence check — every name must exist in `df`'s columns

Produces clear, argument-named error messages.

## Usage

``` r
.assert_column_arg(arg, arg_name, df, length_one = FALSE)
```

## Arguments

- arg:

  The argument value (already extracted from the call).

- arg_name:

  The argument name as a string, used in error messages (e.g., `"loss"`,
  `"cohort"`).

- df:

  The data.frame/data.table the columns must be present in.

- length_one:

  If `TRUE`, the argument must have length exactly 1.

## Value

Invisibly returns `arg` on success; aborts otherwise.

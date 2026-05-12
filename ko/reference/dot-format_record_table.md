# Format a list of records as column-aligned strings

Internal helper for print methods. Takes a named list of equal-length
character vectors (one entry per column, vectors aligned row-wise) and
returns a character vector of formatted rows where each column is padded
to its widest value with a configurable justification.

Useful for printing multi-record summaries (e.g., per-group regime info)
without manually computing widths in each `print.*` method.

## Usage

``` r
.format_record_table(cols, justify = "left", sep = " | ")
```

## Arguments

- cols:

  A named list of equal-length character vectors. Each entry is one
  column of the table; the entry's name is unused (kept for caller
  readability).

- justify:

  Either a single string (`"left"`, `"right"`, `"centre"`) applied to
  all columns, or a character vector of the same length as `cols` to set
  per-column justification.

- sep:

  Separator inserted between columns (default `" | "`).

## Value

A character vector of length `length(cols[[1L]])`, one formatted row per
record.

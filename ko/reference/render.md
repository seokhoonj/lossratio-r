# Render a tabular object as a compact console table

`render()` prints a data frame, data table, or Triangle object as a
compact, fixed-width console table. The layout deliberately mirrors the
dataframe console output of the package's Python sibling,
`lossratio-py`, so that the R and Python implementations produce
visually consistent table previews.

The rendered table has four parts:

- a `shape: (rows, cols)` header;

- a box-drawn grid carrying a column-name row and a column-type row
  (`<int>`, `<dbl>`, `<date>`, `<chr>`, ...);

- a head / tail sample of rows – when the object has more than `n` rows
  the middle is collapsed to a single ellipsis row;

- a "`N` more variables" footer listing the columns dropped when the
  table is too wide for the console.

Columns are selected from both ends inward until they fill `width`; the
dropped middle columns are summarised in the footer. `print.Triangle()`
delegates to `render()`, so Triangle objects print in this style by
default.

## Usage

``` r
render(x, ...)

# Default S3 method
render(x, ...)

# S3 method for class 'data.frame'
render(
  x,
  n = 10,
  width = getOption("width", 100),
  max_col_width = 14,
  verbose = TRUE,
  ...
)

# S3 method for class 'data.table'
render(
  x,
  n = 10,
  width = getOption("width", 100),
  max_col_width = 14,
  verbose = TRUE,
  ...
)

# S3 method for class 'tbl_df'
render(
  x,
  n = 10,
  width = getOption("width", 100),
  max_col_width = 14,
  verbose = TRUE,
  ...
)

# S3 method for class 'Triangle'
render(
  x,
  n = 10,
  width = getOption("width", 100),
  max_col_width = 14,
  verbose = TRUE,
  ...
)

# S3 method for class 'Triangle'
print(x, ...)
```

## Arguments

- x:

  An object to render. Methods are provided for data frames, data
  tables, tibbles, and Triangle objects; the default method falls back
  to [`print()`](https://rdrr.io/r/base/print.html).

- ...:

  Additional arguments passed to methods.

- n:

  Integer; the maximum number of data rows to show before head / tail
  sampling applies. Default `10`.

- width:

  Integer; the target console width in characters. Default
  `getOption("width", 100)`.

- max_col_width:

  Integer; the maximum width of a single column – longer values are
  truncated with an ellipsis. Default `14`.

- verbose:

  Logical; whether to print the "more variables" footer for columns
  dropped to fit `width`. Default `TRUE`.

## Value

The input object `x`, invisibly.

## Examples

``` r
data(experience)
render(head(experience, 20))
#> shape: (20, 15)
#> ┌──────────┬────────────┬────────────┬───┬───────┬───────────┬───────────────┐
#> │ coverage ┆ uy         ┆ uy_h       ┆ … ┆ dev_m ┆ incr_loss ┆ incr_exposure │
#> │ <chr>    ┆ <date>     ┆ <date>     ┆ … ┆ <int> ┆ <dbl>     ┆ <dbl>         │
#> ├──────────┼────────────┼────────────┼───┼───────┼───────────┼───────────────┤
#> │ ci       ┆ 2023-01-01 ┆ 2023-01-01 ┆ … ┆ 1     ┆ 1262380   ┆ 27993100      │
#> │ ci       ┆ 2023-01-01 ┆ 2023-01-01 ┆ … ┆ 2     ┆ 11255800  ┆ 29183900      │
#> │ ci       ┆ 2023-01-01 ┆ 2023-01-01 ┆ … ┆ 3     ┆ 11281300  ┆ 29402000      │
#> │ ci       ┆ 2023-01-01 ┆ 2023-01-01 ┆ … ┆ 4     ┆ 33602400  ┆ 26570500      │
#> │ ci       ┆ 2023-01-01 ┆ 2023-01-01 ┆ … ┆ 5     ┆ 7152620   ┆ 27471900      │
#> │ …        ┆ …          ┆ …          ┆ … ┆ …     ┆ …         ┆ …             │
#> │ ci       ┆ 2023-01-01 ┆ 2023-01-01 ┆ … ┆ 16    ┆ 7722100   ┆ 27913400      │
#> │ ci       ┆ 2023-01-01 ┆ 2023-01-01 ┆ … ┆ 17    ┆ 22519000  ┆ 27243500      │
#> │ ci       ┆ 2023-01-01 ┆ 2023-01-01 ┆ … ┆ 18    ┆ 20817800  ┆ 25789500      │
#> │ ci       ┆ 2023-01-01 ┆ 2023-01-01 ┆ … ┆ 19    ┆ 7146940   ┆ 27527300      │
#> │ ci       ┆ 2023-01-01 ┆ 2023-01-01 ┆ … ┆ 20    ┆ 33749300  ┆ 26870800      │
#> └──────────┴────────────┴────────────┴───┴───────┴───────────┴───────────────┘
#> 9 more variables: uy_q <date>, uy_m <date>, cy <date>, cy_h <date>, cy_q <date>,
#>                   cy_m <date>, dev_y <int>, dev_h <int>, dev_q <int> 
```

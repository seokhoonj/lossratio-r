# Triangle-heatmap view of dev-sequence gaps

Visualise gap positions on a `cohort x dev` grid: for every cohort with
gaps, expanded dev cells are coloured by status (`observed` /
`missing`). Complements
[`plot.TriangleValidation()`](https://seokhoonj.github.io/lossratio-r/ko/reference/plot.TriangleValidation.md)
(which shows observed-vs-expected counts as bars) – this heatmap shows
*where* the gaps are.

When the validation found no gaps, prints a message and returns
`invisible(NULL)`.

## Usage

``` r
# S3 method for class 'TriangleValidation'
plot_triangle(
  x,
  view = c("calendar", "dev"),
  show_label = FALSE,
  theme = c("view", "save", "shiny"),
  ...
)
```

## Arguments

- x:

  A `TriangleValidation` object.

- view:

  Axis layout. One of `"calendar"` (cohort x calendar grid, default) or
  `"dev"` (cohort x dev grid). `"calendar"` requires the calendar column
  to have been supplied to
  [`validate_triangle()`](https://seokhoonj.github.io/lossratio-r/ko/reference/validate_triangle.md);
  `"dev"` works when either calendar or dev was supplied.

- show_label:

  Logical; when `TRUE`, overlay each cell with the input row count
  (`.N`). Default `FALSE`.

- theme:

  String passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio-r/ko/reference/dot-switch_theme.md).

- ...:

  Extra arguments passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio-r/ko/reference/dot-switch_theme.md).

## Value

A `ggplot` object, or `invisible(NULL)` when there is nothing to
visualise.

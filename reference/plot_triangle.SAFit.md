# Plot a stage-adaptive fit as a triangle table

Triangle-style heatmap for a `"SAFit"`. Delegates to the shared
role-agnostic
[`.plot_triangle_fit()`](https://seokhoonj.github.io/lossratio-r/reference/dot-plot_triangle_fit.md)
implementation.

## Usage

``` r
# S3 method for class 'SAFit'
plot_triangle(x, ...)
```

## Arguments

- x:

  An object of class `"SAFit"`.

- ...:

  Forwarded to the shared implementation – `region`, `view`,
  `label_style`, `label_size`, `conf_level`, `amount_divisor`, `theme`,
  `nrow`, `ncol`.

## Value

A `ggplot` object.

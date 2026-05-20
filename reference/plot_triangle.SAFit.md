# Plot a stage-adaptive fit as a triangle table

Triangle-style heatmap for a `"SAFit"`. Delegates to the role-agnostic
implementation shared with
[`plot_triangle.CLFit()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.CLFit.md).

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

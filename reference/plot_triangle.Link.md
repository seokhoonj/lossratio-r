# Plot a Link object as a triangle heatmap

Visualise a `"Link"` object as a triangle-style heatmap. Dispatches to
the multiplicative ATA branch (`model = "ata"`) or the additive
exposure-driven branch (`model = "ed"`).

The default `model` is chosen from `attr(x, "exposure")`: `NULL` selects
`"ata"`, non-`NULL` selects `"ed"`.

## Usage

``` r
# S3 method for class 'Link'
plot_triangle(x, model = NULL, ...)
```

## Arguments

- x:

  An object of class `"Link"`.

- model:

  Either `"ata"` or `"ed"`. Default depends on `attr(x, "exposure")`.

- ...:

  Arguments forwarded to the underlying plotting helper.

## Value

A `ggplot` object.

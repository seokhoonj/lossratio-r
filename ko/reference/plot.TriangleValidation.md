# Plot a TriangleValidation result

Visualise dev-sequence gaps. Each cohort with gaps is a row; observed
vs. expected dev counts render as side-by-side bars. When the validation
found no gaps (and no row-level violations), prints a message and
returns `invisible(NULL)` instead of erroring.

## Usage

``` r
# S3 method for class 'TriangleValidation'
plot(x, ...)
```

## Arguments

- x:

  A `TriangleValidation` object.

- ...:

  Unused. Present for S3 compatibility.

## Value

A `ggplot` object, or `invisible(NULL)` when there is nothing to
visualise.

# Validate a `metric` plotting argument

Internal helper for the
[`plot_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.md)
methods: checks that `metric` is a single column name present in `data`
and returns it.

## Usage

``` r
.check_metric(metric, data)
```

## Arguments

- metric:

  A single character column name.

- data:

  A `data.frame`-like object.

## Value

`metric`, unchanged, after validation.

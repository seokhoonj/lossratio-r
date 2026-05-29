# Summary method for `IntensityFit`

Returns the `EDSummary` carried by the fit – one row per link with
WLS-estimated `g`, `g_se`, `rse`, `sigma`, and descriptive statistics.
Mirrors
[`summary.ATAFit()`](https://seokhoonj.github.io/lossratio-r/reference/summary.ATAFit.md).

## Usage

``` r
# S3 method for class 'IntensityFit'
summary(object, ...)
```

## Arguments

- object:

  An `"IntensityFit"`.

- ...:

  Unused.

## Value

An `EDSummary` `data.table`.

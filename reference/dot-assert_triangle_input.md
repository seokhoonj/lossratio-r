# Assert that the input is a `Triangle`, with a helpful error for `Link`

Internal helper used by `fit_*()` entry points. Wraps
[`.assert_class()`](https://seokhoonj.github.io/lossratio/reference/dot-assert_class.md)
but intercepts `Link` inputs first to print a message that explains why
a `Link` is not a valid input (build_link is called internally) and how
to pass the data correctly.

## Usage

``` r
.assert_triangle_input(x, called_from)
```

## Arguments

- x:

  The object to check.

- called_from:

  A short string naming the caller, e.g. `"fit_ata()"`, used in the
  error message.

## Value

Invisibly `NULL`. Throws an error if `x` is not a Triangle.

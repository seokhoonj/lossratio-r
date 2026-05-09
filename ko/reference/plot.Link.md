# Plot link-factor diagnostics

Visualise diagnostic summaries from a `"Link"` object. Dispatches to the
multiplicative ATA branch (`model = "ata"`) or the additive
exposure-driven branch (`model = "ed"`).

The default `model` is chosen from `attr(x, "premium_var")`: `NULL`
(single-variable link) selects `"ata"`, a non-`NULL` exposure variable
(dual-variable link) selects `"ed"`.

## Usage

``` r
# S3 method for class 'Link'
plot(x, model = NULL, ...)
```

## Arguments

- x:

  An object of class `"Link"`.

- model:

  Either `"ata"` or `"ed"`. Default depends on `attr(x, "premium_var")`.

- ...:

  Arguments forwarded to the underlying plotting helper. See the
  per-model parameter list in Details.

## Value

A `ggplot` object.

## Details

For `model = "ata"`, accepted arguments include `type`
(`"cv" | "rse" | "summary" | "box" | "point"`), `alpha`,
`show_maturity`, `cv_threshold`, `rse_threshold`, `min_valid_ratio`,
`min_n_valid`, `min_run`, `scales`, `nrow`, `ncol`, `theme`, and
`x.angle`.

For `model = "ed"`, accepted arguments include `type`
(`"summary" | "box" | "point"`), `alpha`, `scales`, `nrow`, `ncol`,
`theme`, and `x.angle`.

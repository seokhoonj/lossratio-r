# Estimate ED parameters (factor / selected) without cell-level projection

Internal helper that performs ED factor estimation from a `"Triangle"`
and returns an `"EDFit"`-shaped list missing only `$full`. Used both as
the parameter-estimation half of public
[`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md)
and directly by
[`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
(to avoid a `fit_ed -> fit_lr -> fit_ed` recursion when
[`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md)
delegates projection to
[`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)).

## Usage

``` r
.fit_ed_factors(
  x,
  value_var = "closs",
  exposure_var = "crp",
  method = c("basic", "mack"),
  alpha = 1,
  na_method = c("zero", "locf", "none"),
  sigma_method = c("min_last2", "locf", "loglinear"),
  recent = NULL,
  regime_break = NULL,
  ...
)
```

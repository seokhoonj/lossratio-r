# Apply bootstrap CI to a CL / ED dispatcher fit

The CL and ED workers don't run bootstrap natively. The dispatcher calls
this helper to map a
[`bootstrap()`](https://seokhoonj.github.io/lossratio/ko/reference/bootstrap.md)
summary onto the worker's analytical `$full` schema – same shape as the
in-worker logic in
[`fit_sa()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_sa.md).
Premium stays at observed values (loss-only bootstrap; premium-side
uncertainty is layered by
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md)).

## Usage

``` r
.lossfit_bootstrap(
  fit,
  triangle,
  bootstrap,
  B,
  seed,
  alpha,
  conf_level,
  target = "loss"
)
```

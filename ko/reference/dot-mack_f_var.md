# Compute Mack's factor variance for each development link

Internal helper computing:

\$\$\mathrm{Var}(\hat{f}\_k) = \frac{\sigma^2_k}{W_k}\$\$

where \\W_k = \sum_i w\_{i,k} \cdot C\_{i,k}^\alpha\\. This is
consistent with the WLS weight \\w\_{i,k} / C\_{i,k}^{2-\alpha}\\ used
in
[`.lm_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-lm_ata.md)
and follows Mack (1993)'s distribution-free standard-error derivation
for the chain ladder reserve estimator.

Paradigm pairing: the package keeps two natural analytical variance
helpers, one per paradigm-target pair: `.mack_f_var()` (CL / Mack 1993
applied to f-factor) and
[`.ed_g_var()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-ed_g_var.md)
(ED / Buehlmann-Straub 1970 applied to g-intensity). They share the
underlying volume-weighted variance idea (\\\sigma^2_g = \sigma^2_f\\
via \\g_k = f_k - 1\\), but operate on different `Link` columns (f reads
`loss_to`/`loss_from`; g reads `loss_delta`/`premium_from`) and produce
differently-named output columns (`f_var` / `g_var`), so are kept as
separate helpers.

Also used by
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md)
for the CL component.

## Usage

``` r
.mack_f_var(ata_fit, alpha = 1)
```

## References

Mack, T. (1993). Distribution-free calculation of the standard error of
chain ladder reserve estimates. *ASTIN Bulletin*, 23(2), 213-225.

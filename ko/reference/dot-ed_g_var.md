# Compute ED intensity variance for each development link

Internal helper computing \\\mathrm{Var}(\hat{g}\_k) = \sigma^2_k /
W_k\\ where \\W_k = \sum_i (C^P\_{i,k})^{2 - \alpha}\\. This is the
Buehlmann-Straub (1970) volume-weighted variance applied to the ED
intensity \\g_k = \sum_i \Delta L\_{i,k} / \sum_i P\_{i,k-1}\\.

Paradigm pairing: the package keeps two natural analytical variance
helpers, one per paradigm-target pair:
[`.mack_f_var()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-mack_f_var.md)
(CL / Mack 1993 applied to f-factor) and `.ed_g_var()` (ED /
Buehlmann-Straub 1970 applied to g-intensity). The cross-paradigm pairs
(`.mack_g_var`, `.bs_f_var`) are algebraically derivable via \\g_k =
f_k - 1\\ (and therefore \\\sigma^2_g = \sigma^2_f\\), so are
intentionally not provided as separate functions to avoid suggesting
paradigm mismatch is encouraged in user code.

Conceptually `.ed_g_var()` is a *factor-level* helper (operates on
per-link `$link` and `$selected` slots) and should pair with
`"IntensityFit"` (the factor-level diagnostic for ED, sibling of
`"ATAFit"`). The current implementation takes `"EDFit"`
(projection-level) for historical reasons; both objects expose the same
factor-level slots, so the implementation is functionally correct but
the class assertion is conceptually misaligned. TODO: refactor input to
`"IntensityFit"` for symmetry with `.mack_f_var(ata_fit: ATAFit)`.

Used by
[`fit_ed()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ed.md)
when `method = "mack"` and by
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md)
for the ED component.

## Usage

``` r
.ed_g_var(ed_fit, alpha = 1)
```

## Arguments

- ed_fit:

  An object of class `"EDFit"`.

- alpha:

  Numeric scalar. Default is `1`.

## Value

The `$selected` `data.table` with `g_var` column.

## References

Buehlmann, H. and Straub, E. (1970). Glaubwuerdigkeit fuer Schadensaetze
(Credibility for Loss Ratios). *Bulletin of the Swiss Association of
Actuaries*, 70, 111-133.

Mack, T. (1993). Distribution-free calculation of the standard error of
chain ladder reserve estimates. *ASTIN Bulletin*, 23(2), 213-225.

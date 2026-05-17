# Changelog

## lossratio (development version)

- **BREAKING: identifier rename `premium` -\> `prem`, `development` -\>
  `dev`.** Code-level identifiers (argument names, function names, enum
  values, slot names, attribute keys) are renamed to the short form
  already used by the column / attribute convention (`prem`, `dev`).
  Prose documentation (“premium-side projection”, “development period”)
  is unchanged.

  Migration (find-and-replace at call sites):

  - `as_triangle(..., premium = "incr_prem")` -\>
    `as_triangle(..., prem = "incr_prem")`
  - `as_triangle(..., development = "dev_m")` -\>
    `as_triangle(..., dev = "dev_m")`
  - `validate_triangle(..., development = "dev_m")` -\>
    `validate_triangle(..., dev = "dev_m")`
  - `fit_premium(...)` -\> `fit_prem(...)`
  - `fit_loss(..., premium_method = ..., premium_alpha = ..., premium_fit = ...)`
    -\>
    `fit_loss(..., prem_method = ..., prem_alpha = ..., prem_fit = ...)`
  - `fit_lr(..., premium_method = ..., premium_alpha = ..., premium_regime = ...)`
    -\>
    `fit_lr(..., prem_method = ..., prem_alpha = ..., prem_regime = ...)`
  - `backtest(..., target = "premium", premium_method = ..., premium_alpha = ..., premium_regime = ...)`
    -\>
    `backtest(..., target = "prem", prem_method = ..., prem_alpha = ..., prem_regime = ...)`
  - `bootstrap(tri, target = "premium")` -\>
    `bootstrap(tri, target = "prem")`
  - `LRFit$premium_alpha`, `LRFit$premium_regime` -\> `$prem_alpha`,
    `$prem_regime`
  - `LossFit$premium_fit` -\> `$prem_fit`
  - S3 class `"PremiumFit"` -\> `"PremFit"` (incl. `print.PremiumFit()`
    / `summary.PremiumFit()` -\>
    [`print.PremFit()`](https://seokhoonj.github.io/lossratio/ko/reference/print.PremFit.md)
    /
    [`summary.PremFit()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.PremFit.md);
    `inherits(x, "PremiumFit")` -\> `inherits(x, "PremFit")`)
  - `attr(PremiumFit_obj, "premium_method")` -\>
    `attr(PremFit_obj, "prem_method")`

  The Triangle / Calendar / Total / fit-output *column* names already
  use the short form (`prem`, `incr_prem`, `prem_proj`, …) from the
  earlier prefix sweep; this release closes the loop by aligning the
  *argument / slot* surface with that convention.

- **Default flip** —
  [`bootstrap()`](https://seokhoonj.github.io/lossratio/ko/reference/bootstrap.md)’s
  `keep_pseudo` default changes from `TRUE` to `FALSE`. The long-format
  `$pseudo_triangles` long-format data.table is no longer built on every
  call; the precomputed `$summary` (Pythagorean SE decomposition +
  optional percentile CI) is still always present. Skipping the
  long-format reshape saves roughly 250-300 ms and ~200 MB on a typical
  4-group monthly triangle at `B = 999`. Users who inspect
  `$pseudo_triangles` directly should pass `keep_pseudo = TRUE`
  explicitly; the argument is unchanged.

- **BREAKING** — the four constructor functions are renamed from
  `build_*` to `as_*` to align with the tidyverse coercion idiom and the
  Python sibling’s `lr.Triangle(df)` mental model:

  - `build_triangle()` -\>
    [`as_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/as_triangle.md)
  - `build_calendar()` -\>
    [`as_calendar()`](https://seokhoonj.github.io/lossratio/ko/reference/as_calendar.md)
  - `build_total()` -\>
    [`as_total()`](https://seokhoonj.github.io/lossratio/ko/reference/as_total.md)
  - `build_link()` -\>
    [`as_link()`](https://seokhoonj.github.io/lossratio/ko/reference/as_link.md)
    No signature change, only the verb. Migration is a global
    find-and-replace. The functions still validate, coerce, and
    aggregate substantively – the `as_*` name reflects that the returned
    object is *the* canonical lossratio shape derived from the raw
    experience data, not just a thin type cast. The PascalCase classes
    (`Triangle`, `Calendar`, `Total`, `Link`) remain unchanged.

- **BREAKING** —
  [`plot_triangle.Triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.Triangle.md)
  argument `type` renamed to `view` for parity with
  [`plot_triangle.CLFit()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.CLFit.md),
  [`plot_triangle.LRFit()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.LRFit.md),
  and
  [`plot_triangle.Backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.Backtest.md),
  which already used `view = c("value", "usage")`. The `type =` slot is
  left free for plot-method-specific semantics
  (`plot.Backtest(type = "col"/"diag"/"cell")`,
  `plot.CLFit(type = "projection"/"reserve")`, etc.). Migration:
  `plot_triangle(tri, type = "usage")` -\>
  `plot_triangle(tri, view = "usage")`.

- **Known limitation (future work) — segment_wise mini-triangle
  gap-fill**. Under `treatment = "segment_wise"`, `fit_*` produces a
  mini-triangle per regime segment using only that segment’s cohorts;
  cells that fall outside every mini-triangle (typically old cohorts at
  late development periods that cannot be reached from any single
  segment) are currently left unprojected. A follow-up phase should add
  a fallback (e.g. `latest-segment factor`, `previous-segment factor`,
  smoothing across segments) controlled by a `Regime$fallback` knob,
  plus a warning when $`k^*`$ exceeds the *change-to-now* horizon of the
  latest segment (which would also cause the mini-triangle to be
  truncated). Today the cells render as `unused` in
  `plot_triangle(view = "usage")` rather than being filled in by an
  inferred projection.

- **BREAKING** —
  [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  cell-level columns renamed from `target_actual` / `target_proj` (and
  `_incr` siblings) to `actual` / `expected` (and `actual_incr` /
  `expected_incr`). The new names match the actuarial A/E convention
  (`aeg = actual - expected`, `ae_err = actual / expected - 1`) and
  self-document the role of each column. Worker-layer column names
  (`target_proj` etc. on `CLFit$full` / `EDFit$full`) are unchanged –
  the rename is scoped to `backtest$ae_err`. Migration: replace
  `bt$ae_err$target_actual` with `bt$ae_err$actual`,
  `bt$ae_err$target_proj` with `bt$ae_err$expected`.

- [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  result slot `fit_fn_name` renamed to `dispatcher` for clarity (the
  value is still the dispatcher name — `fit_lr` / `fit_loss` /
  `fit_premium` — selected by `target=`).
  [`print()`](https://rdrr.io/r/base/print.html) /
  [`summary()`](https://rdrr.io/r/base/summary.html) labels updated
  accordingly.

- [`fit_loss()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_loss.md),
  `fit_premium()`,
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md),
  and
  [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  now attach a `$usage` `data.table` to the result: one row per
  `(group, cohort, dev)` cell of the *pre-filter* triangle with a
  `status` factor (`used` / `unused` / `holdout` / `future`).
  `plot_triangle(fit, view = "usage")` reads this directly instead of
  re-deriving the filter logic at plot time, so the heatmap always
  matches the cells the fit actually saw. New internal helper
  `.build_usage()` packages the 2-pass maturity detection plus
  [`.compute_triangle_usage()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-compute_triangle_usage.md)
  and attaches filter metadata (`regime` / `recent` / `holdout` / `m_k`
  / `m_k_dt`) as `data.table` attributes for the renderer.

- **BREAKING** — `build_triangle()`, `build_total()`, and
  [`validate_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/validate_triangle.md)
  rename their `dev =` argument to `development =`. The new name is more
  explicit about the development-period axis (matching the
  `coh <- cohort` symmetry inside the function bodies). Migration:
  replace `build_triangle(..., dev = "dev_m")` with
  `build_triangle(..., development = "dev_m")`.

- **BREAKING** —
  [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  result columns renamed from `value_proj` / `value_actual` (and `_incr`
  variants) to `target_proj` / `target_actual` (and `_incr` variants),
  matching the worker-layer `target_*` generic convention.

- **BREAKING** — summary column renames for `<metric>_<stat>`
  consistency:

  - `summary.LossFit` / `summary.PremiumFit`: `se_ultimate` /
    `cv_ultimate` -\> `ultimate_se` / `ultimate_cv`.
  - `.compute_dv()` output: `median_lr` / `mad_lr` -\> `lr_median` /
    `lr_mad`.
  - Internal `var_lr` (LR variance scratch column) -\> `lr_var`.
  - `detect_regime_optimal_window()` diagnostics column:
    `mean_magnitude` -\> `magnitude_mean`.

- [`plot_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.md)
  now derives the axis grain via `attr(tri, "grain")` when the raw
  column name (`uy_m`, `cy_q`, …) is not one of the package-standard
  forms, so user-supplied names like `uym` or `elap_m` still render tick
  labels in the abbreviated format (`23.04`, `23.1Q`, …).

- `plot_triangle(fit, view = "usage")` regime / segment_wise routing
  fixed: per-group dispatch now honours `regime$groups` even when
  `multi_group = FALSE`, so `regime_at(coverage = "SUR", ...)` scopes
  the hline / cohort cut to the SUR facet only. Filtered-out cells
  render as `unused` (gray) instead of `future` (white).

- `.datatable.aware <- TRUE` declared in `R/zzz.R`; data.table NSE NOTEs
  suppressed via mlr3-style `(".col") :=` LHS pattern + a reorganised
  [`globalVariables()`](https://rdrr.io/r/utils/globalVariables.html)
  list. Internal temp markers (`.col` prefix) use function-local `NULL`
  bindings per the data.table official recommendation.

- **BREAKING** — `as_experience()`, `check_experience()`, and
  `is_experience()` removed along with the `Experience` S3 class.
  `build_triangle()` already validates required columns, coerces dates
  and numerics, and aggregates inline, so the explicit coercion step is
  no longer needed (and the class itself was never required by any
  downstream function). Migration: replace
  `exp <- as_experience(df); build_triangle(exp, ...)` with
  `build_triangle(df, ...)`. Matches Python sibling 0.0.1.dev7.

- New
  [`fit_intensity()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_intensity.md) +
  `IntensityFit` S3 class (R/intensity.R) — factor-level ED diagnostic,
  parallel to
  [`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md)
  for the multiplicative side. Returns per-link WLS-estimated
  intensities `g_k` with standard errors and diagnostic stats; no
  projection. ED has no maturity concept, so `fit_intensity`
  deliberately omits `maturity_args`.

- Link cell-level column `g` renamed to `intensity` (concept-based,
  parallels ATA’s `ata`). Summary / fit per-link output columns (`g`,
  `g_se`, `g_var`, `g_selected`) keep Mack-style symbol naming for
  parallelism with ATA summary’s `f`, `f_se`. Layered naming: cell layer
  uses concept (`intensity`), summary layer uses symbol (`g`).

- [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md):
  cell-level metric and aggregation columns renamed from `aeg` to
  `ae_err` (column `ae_err`, aggregations `ae_err_mean` / `ae_err_med` /
  `ae_err_wt`). Print and plot labels updated to “A/E Error”. Formula
  unchanged: `(actual - pred) / pred`.

## lossratio 0.0.0.9000

### Core API

- Aggregation: `build_triangle()` (cohort × dev), `build_calendar()`
  (calendar period), `build_total()` (portfolio total).
  `build_triangle()` validates schema and coerces required columns
  inline.
- Link table: `build_link()` returns a `Link` object covering both
  single-variable (ATA-style) and dual-variable (ED-style) workflows.
  `summary.Link(model = "ata"|"ed")` dispatches to the matching
  diagnostic.
- Estimation:
  [`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md)
  (per-link factors only);
  [`fit_ed()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ed.md),
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md),
  and
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
  (factors + projection). `fit_lr` supports three methods — `"sa"`
  (default), `"ed"`, `"cl"`.
- Cell-selection diagnostics:
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
  (dev axis — link beyond which ATA factors are stable),
  [`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  (cohort axis — structural breaks across underwriting cohorts).
- Projection diagnostic:
  [`detect_convergence()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_convergence.md)
  (operates on a fitted `LRFit`; valuation depth at which projected
  ultimate loss ratio stops revising).
- Backtest:
  [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  (calendar-diagonal hold-out, supports `fit_cl`, `fit_ed`, and
  `fit_lr`).
- Visualisation: S3
  [`plot()`](https://rdrr.io/r/graphics/plot.default.html) and
  [`plot_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.md)
  methods on every fit class.

### Dataset

- `experience` — 2,664-row synthetic example data, generated by
  `data-raw/make_experience.R`.

### Documentation

- Seven vignettes covering getting started, aggregation frameworks,
  chain ladder, loss-ratio projection methods, triangle / ata
  diagnostics, regime detection, and backtesting.

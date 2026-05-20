# Changelog

## lossratio (development version)

- **Buehlmann-Straub credibility blend for
  [`fit_bf()`](https://seokhoonj.github.io/lossratio/reference/fit_bf.md)
  /
  [`fit_cc()`](https://seokhoonj.github.io/lossratio/reference/fit_cc.md).**
  A new `credibility` argument switches the BF / CC blend weight from
  the emergence fraction `q` to a Buehlmann-Straub credibility factor
  `Z = K / (K + s^2)`, where `s^2` is the variance of the cohort’s own
  CL loss-ratio estimate and `K` is the between-cohort variance of the
  true loss ratios (estimated per group, or supplied).
  `credibility = NULL` (default) keeps the classical blend. The
  credibility weight protects rare-event and very green cohorts: a CL
  estimate built on almost no data has a large `s^2`, so `Z` shrinks
  toward 0 and the cohort is pulled to the prior even when its `q` is
  high. The fit carries a `$credibility` slot with the per-cohort `Z` /
  `K`.

- **Analytical prediction error for
  [`fit_bf()`](https://seokhoonj.github.io/lossratio/reference/fit_bf.md)
  /
  [`fit_cc()`](https://seokhoonj.github.io/lossratio/reference/fit_cc.md).**
  `type = "analytical"` is now implemented (previously a stub error). It
  computes the closed-form mean squared error of prediction via the
  Mack (2008) Bornhuetter-Ferguson MSEP decomposition – process error
  plus development-pattern and prior estimation error – without
  simulation. `$summary` carries `loss_total_se` / `loss_total_cv` /
  `loss_ci_lo` / `loss_ci_hi`;
  [`fit_cc()`](https://seokhoonj.github.io/lossratio/reference/fit_cc.md)
  additionally reports `elr_cc_se` / `elr_cc_cv` / `elr_cc_ci_lo` /
  `elr_cc_ci_hi` for the data-estimated pooled ELR. The analytical path
  is also used whenever no bootstrap is requested, so every fit now
  reports an SE.

- **Distribution prior for
  [`fit_bf()`](https://seokhoonj.github.io/lossratio/reference/fit_bf.md).**
  A `data.frame` prior may carry an optional `elr_se` column – the
  standard error of the a priori ELR. The bootstrap path then draws a
  per-replicate ELR from `Normal(elr, elr_se)`, and the analytical path
  feeds it into the `Var(ELR)` term. A deterministic prior (no `elr_se`)
  is unchanged.

- **Per-group prior for
  [`fit_bf()`](https://seokhoonj.github.io/lossratio/reference/fit_bf.md).**
  A prior `data.frame` may carry the grouping columns plus `elr` without
  a `cohort` column; the group’s ELR is then broadcast to every cohort
  in that group.

- **Worker layer fix + bootstrap arg on `fit_cl` / `fit_ed`.**
  [`fit_bf()`](https://seokhoonj.github.io/lossratio/reference/fit_bf.md)
  /
  [`fit_cc()`](https://seokhoonj.github.io/lossratio/reference/fit_cc.md)
  /
  [`fit_sa()`](https://seokhoonj.github.io/lossratio/reference/fit_sa.md)
  now build their internal exposure fit by calling
  `fit_cl(loss = "exposure", ...)` directly instead of routing through
  [`fit_exposure()`](https://seokhoonj.github.io/lossratio/reference/fit_exposure.md)
  — downward-only Tier 3 -\> Tier 4 dependency.
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
  and
  [`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md)
  both gain `bootstrap`, `B`, `seed`, `conf_level` arguments for
  symmetry with the SA / BF / CC workers; `bootstrap = NULL` (default)
  preserves analytical Mack SE. All fit-result classes standardised to
  `c("XFit", "list")` (or prepended forms for the dispatchers).

- **[`fit_bf()`](https://seokhoonj.github.io/lossratio/reference/fit_bf.md) +
  [`fit_cc()`](https://seokhoonj.github.io/lossratio/reference/fit_cc.md)
  promoted to peer workers** with bootstrap composition. `fit_bf` takes
  an external prior ELR (Bornhuetter-Ferguson 1972); `fit_cc` derives
  ELR from data via payout weighting (Stanard 1985, Cape Cod). Both
  expose `bootstrap = "auto"` for cell / link / parametric simulation
  and analytical fallback. Promotion makes them available through
  `fit_loss(method = "bf" | "cc")`.

- **`fit_sa` worker + `fit_loss` true dispatcher.** Phase 4 split the
  stage-adaptive composition (`R/sa.R`, class `"SAFit"`) out of
  `R/loss.R`, and
  [`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md)
  now thin-dispatches by `method` to the worker functions (`fit_ed` /
  `fit_cl` / `fit_sa` / `fit_bf` / `fit_cc`) and augments their output
  to the LossFit-uniform `$full` schema via
  [`.lossfit_augment()`](https://seokhoonj.github.io/lossratio/reference/dot-lossfit_augment.md).
  [`fit_exposure()`](https://seokhoonj.github.io/lossratio/reference/fit_exposure.md)
  follows the same pattern with
  [`.exposurefit_augment()`](https://seokhoonj.github.io/lossratio/reference/dot-exposurefit_augment.md) +
  [`.exposurefit_bootstrap()`](https://seokhoonj.github.io/lossratio/reference/dot-exposurefit_bootstrap.md)
  (Phase 4c).

- **BREAKING: bootstrap `type = "parametric"` -\> `"analytical"`
  rename.** The Mack closed-form SE option was previously mislabelled as
  `"parametric"`. The textbook-parametric kernels (cell-distribution
  sampling + refit, England-Verrall 1999) now use `type = "parametric"`,
  and the analytical Mack closed-form lives at `type = "analytical"`.
  [`bootstrap.Triangle()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md)
  default is `"analytical"`; worker-side `fit_sa` / `fit_bf` / `fit_cc`
  `type =` defaults to `"parametric"` (cell-distribution simulation).

- **SA nonparametric bootstrap proper kernel.**
  `bootstrap(method = "sa")` previously silently dispatched to the CL
  cell kernel. Phase 1 introduced the dedicated
  `bootstrap_kernel_sa_cell` (and link variants) that respect the stage
  transition at maturity `k^*`, with ED-stage cells using additive `g_k`
  refit and CL-stage cells using multiplicative `f_k` refit.

- **ED bootstrap (Phase 1, fixed exposure).**
  [`bootstrap()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md)
  now supports `method = "ed"` for `residual = "cell"`: per-replicate
  `g*_k` refit and additive forward projection
  (`Delta loss = g_k * P_{from} + noise`) instead of the multiplicative
  chain ladder. Exposure stays fixed across replicates (projected once
  via CL on the exposure column). New native helpers
  `bootstrap_refit_gstar` / `bootstrap_fwd_proj_ed_and_clip` /
  `bootstrap_fwd_sim_ed_cell` parallel the CL kernel triple; the C entry
  point is `C_bootstrap_kernel_ed_cell` (17 args). Phase 2 / 3 (joint
  loss + exposure bootstrap) deferred. `method = "ed"` requires
  `residual = "cell"`; ED + link residuals is not implemented.

- **[`bootstrap()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md)
  method-enum reorder — `c("sa", "cl", "ed")` -\>
  `c("ed", "cl", "sa")`.** Matches the
  [`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md)
  /
  [`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md)
  default flip. Default is now `"ed"`. Users relying on `"sa"` as the
  bootstrap method must pass it explicitly.

- **BREAKING: method default flip — `"sa"` -\> `"ed"`.**
  [`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md),
  [`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md),
  and
  [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  (via `loss_method`) now default to `method = "ed"` (exposure-driven)
  instead of `"sa"` (stage-adaptive). Method-enum order is
  `c("ed", "cl", "sa")` — *simple -\> classical -\> composition*.
  Rationale: ED is the unconditional safe baseline (additive, no
  maturity-detection dependency, robust under early-dev age-to-age
  volatility); CL is the classical Mack 1993 alternative; SA is the
  composition of ED + CL requiring 2-pass maturity detection. Users
  relying on stage-adaptive behaviour must now pass `method = "sa"`
  explicitly. Migration:

  - `fit_loss(tri)` -\> still works (now defaults to ED)
  - `fit_loss(tri, method = "sa")` -\> explicit (no change)
  - Want previous SA default behaviour back? -\> add `method = "sa"`

- **Variance helper rename — `.mack_g_var` -\> `.ed_g_var`.** Internal
  factor-level variance helper renamed for paradigm clarity. `.mack_*`
  is reserved for the CL/Mack 1993 paradigm (f-factor variance); ED
  intensity variance follows the Buehlmann-Straub 1970 lineage and now
  lives at
  [`.ed_g_var()`](https://seokhoonj.github.io/lossratio/reference/dot-ed_g_var.md).
  The two natural analytical variance helpers in the package are now:
  [`.mack_f_var()`](https://seokhoonj.github.io/lossratio/reference/dot-mack_f_var.md)
  (CL paradigm, f) and
  [`.ed_g_var()`](https://seokhoonj.github.io/lossratio/reference/dot-ed_g_var.md)
  (ED paradigm, g). Cross-paradigm pairs are not provided as separate
  functions — they are algebraically derivable via `g_k = f_k - 1`. Both
  helpers now carry [@references](https://github.com/references) blocks
  citing Mack (1993) and Buehlmann-Straub (1970) respectively.

- **BREAKING: worker-arg rename `target` -\> `loss`.** Worker-layer
  functions (`fit_cl`, `fit_ed`, `fit_ata`, `fit_intensity`,
  `detect_maturity`, `detect_regime`) and
  [`as_link()`](https://seokhoonj.github.io/lossratio/reference/as_link.md)
  now take a `loss` argument in place of `target`. Worker-output columns
  rename accordingly (`target_obs` -\> `loss_obs`, `target_proj` -\>
  `loss_proj`, `target_*_se` -\> `loss_*_se`, `target_from` /
  `target_to` / `target_delta` -\> `loss_from` / `loss_to` /
  `loss_delta`). Fit-object attribute key `attr(., "target")` becomes
  `attr(., "loss")` on Link, ATAFit, EDFit, CLFit, IntensityFit,
  Maturity, Regime, and Convergence objects. The `target` arg on
  [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  (a dispatcher enum selecting `"ratio"` / `"loss"` / `"exposure"`) is
  **unchanged** — that is a different semantic (which metric to
  backtest) and stays as-is. Bootstrap’s
  `target = c("loss", "exposure")` enum is also unchanged.

  Migration:

  - `fit_cl(tri, target = "loss")` -\> `fit_cl(tri, loss = "loss")`
  - `fit_ed(tri, target = "loss", exposure = ...)` -\>
    `fit_ed(tri, loss = "loss", exposure = ...)`
  - `as_link(tri, target = "loss")` -\> `as_link(tri, loss = "loss")`
  - `detect_maturity(tri, target = "loss")` -\>
    `detect_maturity(tri, loss = "loss")`
  - `detect_regime(tri, target = "ratio")` -\>
    `detect_regime(tri, loss = "ratio")`
  - Reading `cl_fit$full$target_proj` -\> `cl_fit$full$loss_proj`
  - Reading `attr(link, "target")` -\> `attr(link, "loss")`

- **BREAKING: identifier rename `prem` -\> `exposure`, `lr` -\>
  `ratio`.** Framework-generic naming for the denominator slot
  (`exposure`) and the derived ratio column / fit family (`ratio`). The
  previous in-progress sweep `premium` -\> `prem` (still unreleased) is
  superseded — final target is `exposure`, the framework-generic word
  that covers loss reserving (risk premium = exposure), frequency
  (insureds = exposure), and severity (claim count = Bühlmann natural
  weight = exposure) uniformly. Prose noun phrases (“loss ratio”,
  “premium”, “risk premium”, “exposure measure”) are unchanged.

  Migration (find-and-replace at call sites):

  - `as_triangle(..., premium = "incr_prem")` /
    `as_triangle(..., prem = "incr_prem")` -\>
    `as_triangle(..., exposure = "incr_exposure")`
  - `as_triangle(..., development = "dev_m")` -\>
    `as_triangle(..., dev = "dev_m")`
  - `validate_triangle(..., development = "dev_m")` -\>
    `validate_triangle(..., dev = "dev_m")`
  - `fit_premium(...)` / `fit_prem(...)` -\> `fit_exposure(...)`
  - `fit_lr(...)` -\> `fit_ratio(...)`
  - `fit_loss(..., prem_method = ..., prem_alpha = ..., prem_fit = ...)`
    -\>
    `fit_loss(..., exposure_method = ..., exposure_alpha = ..., exposure_fit = ...)`
  - `fit_lr(..., prem_method = ..., prem_alpha = ..., prem_regime = ...)`
    -\>
    `fit_ratio(..., exposure_method = ..., exposure_alpha = ..., exposure_regime = ...)`
  - `backtest(..., target = "lr", prem_method = ..., prem_alpha = ...)`
    -\>
    `backtest(..., target = "ratio", exposure_method = ..., exposure_alpha = ...)`
  - `backtest(..., target = "prem")` -\>
    `backtest(..., target = "exposure")`
  - `bootstrap(tri, target = "prem")` -\>
    `bootstrap(tri, target = "exposure")`
  - `LRFit$prem_alpha`, `LRFit$prem_regime` -\>
    `RatioFit$exposure_alpha`, `$exposure_regime`
  - `LossFit$prem_fit` -\> `$exposure_fit`
  - S3 class `"PremFit"` -\> `"ExposureFit"` (incl. `print.PremFit()` /
    `summary.PremFit()` -\>
    [`print.ExposureFit()`](https://seokhoonj.github.io/lossratio/reference/print.ExposureFit.md)
    /
    [`summary.ExposureFit()`](https://seokhoonj.github.io/lossratio/reference/summary.ExposureFit.md))
  - S3 class `"LRFit"` -\> `"RatioFit"` (incl. `print.LRFit()` /
    `summary.LRFit()` / `plot.LRFit()` / `plot_triangle.LRFit()` -\>
    `*.RatioFit()`)
  - `attr(PremFit_obj, "prem_method")` -\>
    `attr(ExposureFit_obj, "exposure_method")`
  - Triangle / Calendar / Total columns: `prem`, `incr_prem`,
    `prem_share`, `incr_prem_share`, `lr`, `incr_lr` -\> `exposure`,
    `incr_exposure`, `exposure_share`, `incr_exposure_share`, `ratio`,
    `incr_ratio`
  - Fit output columns: `prem_proj`, `prem_obs`, `prem_proc_se`,
    `prem_param_se`, `prem_total_se`, `prem_total_cv`, `prem_ci_lo`,
    `prem_ci_hi`, `incr_prem_proj` -\> `exposure_*`; `lr_proj`, `lr_se`,
    `lr_cv`, `lr_ci_lo`, `lr_ci_hi`, `lr_ult`, `lr_latest`,
    `incr_lr_proj` -\> `ratio_*`
  - R source files: `R/prem.R`, `R/lr.R`, `R/lr-vis.R` -\>
    `R/exposure.R`, `R/ratio.R`, `R/ratio-vis.R`
  - Raw dataset (`data/experience.rda`): column `incr_prem` -\>
    `incr_exposure` (regenerated)

  The package name `lossratio` is unchanged; this sweep is purely a
  code-identifier refactor. The conceptual “loss ratio” framework is
  preserved — `ratio` is the column / fit name for the loss-to-exposure
  ratio, and the package continues to specialise in long-term health
  insurance reserving on developing exposure (risk premium) triangles.

- **Default flip** —
  [`bootstrap()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md)’s
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
    [`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md)
  - `build_calendar()` -\>
    [`as_calendar()`](https://seokhoonj.github.io/lossratio/reference/as_calendar.md)
  - `build_total()` -\>
    [`as_total()`](https://seokhoonj.github.io/lossratio/reference/as_total.md)
  - `build_link()` -\>
    [`as_link()`](https://seokhoonj.github.io/lossratio/reference/as_link.md)
    No signature change, only the verb. Migration is a global
    find-and-replace. The functions still validate, coerce, and
    aggregate substantively – the `as_*` name reflects that the returned
    object is *the* canonical lossratio shape derived from the raw
    experience data, not just a thin type cast. The PascalCase classes
    (`Triangle`, `Calendar`, `Total`, `Link`) remain unchanged.

- **BREAKING** —
  [`plot_triangle.Triangle()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.Triangle.md)
  argument `type` renamed to `view` for parity with
  [`plot_triangle.CLFit()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.CLFit.md),
  `plot_triangle.LRFit()`, and
  [`plot_triangle.Backtest()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.Backtest.md),
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
  [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  cell-level columns renamed from `target_actual` / `target_proj` (and
  `_incr` siblings) to `actual` / `expected` (and `actual_incr` /
  `expected_incr`). The new names match the actuarial A/E convention
  (`aeg = actual - expected`, `ae_err = actual / expected - 1`) and
  self-document the role of each column. Worker-layer column names
  (`target_proj` etc. on `CLFit$full` / `EDFit$full`) are unchanged –
  the rename is scoped to `backtest$ae_err`. Migration: replace
  `bt$ae_err$target_actual` with `bt$ae_err$actual`,
  `bt$ae_err$target_proj` with `bt$ae_err$expected`.

- [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  result slot `fit_fn_name` renamed to `dispatcher` for clarity (the
  value is still the dispatcher name — `fit_ratio` / `fit_loss` /
  `fit_exposure` — selected by `target=`).
  [`print()`](https://rdrr.io/r/base/print.html) /
  [`summary()`](https://rdrr.io/r/base/summary.html) labels updated
  accordingly.

- [`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md),
  [`fit_exposure()`](https://seokhoonj.github.io/lossratio/reference/fit_exposure.md),
  [`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md),
  and
  [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  now attach a `$usage` `data.table` to the result: one row per
  `(group, cohort, dev)` cell of the *pre-filter* triangle with a
  `status` factor (`used` / `unused` / `holdout` / `future`).
  `plot_triangle(fit, view = "usage")` reads this directly instead of
  re-deriving the filter logic at plot time, so the heatmap always
  matches the cells the fit actually saw. New internal helper
  `.build_usage()` packages the 2-pass maturity detection plus
  [`.compute_triangle_usage()`](https://seokhoonj.github.io/lossratio/reference/dot-compute_triangle_usage.md)
  and attaches filter metadata (`regime` / `recent` / `holdout` / `m_k`
  / `m_k_dt`) as `data.table` attributes for the renderer.

- **BREAKING** — `build_triangle()`, `build_total()`, and
  [`validate_triangle()`](https://seokhoonj.github.io/lossratio/reference/validate_triangle.md)
  rename their `dev =` argument to `development =`. The new name is more
  explicit about the development-period axis (matching the
  `coh <- cohort` symmetry inside the function bodies). Migration:
  replace `build_triangle(..., dev = "dev_m")` with
  `build_triangle(..., development = "dev_m")`.

- **BREAKING** —
  [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
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

- [`plot_triangle()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.md)
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
  [`fit_intensity()`](https://seokhoonj.github.io/lossratio/reference/fit_intensity.md) +
  `IntensityFit` S3 class (R/intensity.R) — factor-level ED diagnostic,
  parallel to
  [`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md)
  for the multiplicative side. Returns per-link WLS-estimated
  intensities `g_k` with standard errors and diagnostic stats; no
  projection. ED has no maturity concept, so `fit_intensity`
  deliberately omits `maturity_args`.

- Link cell-level column `g` renamed to `intensity` (concept-based,
  parallels ATA’s `ata`). Summary / fit per-link output columns (`g`,
  `g_se`, `g_var`, `g_selected`) keep Mack-style symbol naming for
  parallelism with ATA summary’s `f`, `f_se`. Layered naming: cell layer
  uses concept (`intensity`), summary layer uses symbol (`g`).

- [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md):
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
  [`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md)
  (per-link factors only);
  [`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md),
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md),
  and `fit_lr()` (factors + projection). `fit_lr` supports three methods
  — `"sa"` (default), `"ed"`, `"cl"`.
- Cell-selection diagnostics:
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
  (dev axis — link beyond which ATA factors are stable),
  [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  (cohort axis — structural breaks across underwriting cohorts).
- Projection diagnostic:
  [`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md)
  (operates on a fitted `LRFit`; valuation depth at which projected
  ultimate loss ratio stops revising).
- Backtest:
  [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  (calendar-diagonal hold-out, supports `fit_cl`, `fit_ed`, and
  `fit_lr`).
- Visualisation: S3
  [`plot()`](https://rdrr.io/r/graphics/plot.default.html) and
  [`plot_triangle()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.md)
  methods on every fit class.

### Dataset

- `experience` — 2,664-row synthetic example data, generated by
  `data-raw/make_experience.R`.

### Documentation

- Seven vignettes covering getting started, aggregation frameworks,
  chain ladder, loss-ratio projection methods, triangle / ata
  diagnostics, regime detection, and backtesting.

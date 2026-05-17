/* =============================================================================
 * lossratio: bootstrap stage-1 native kernels
 *
 * R <-> C contract
 * ----------------
 * Output layout: a 3D REALSXP of dim c(n_coh, n_dev, B), column-major,
 *   i.e. cum[i, j, b] = flat[i + j*n_coh + b*n_coh*n_dev] (0-indexed
 *   inside C). Allocated inside the kernel and returned to R; R wraps
 *   it as `out_arr` and reshapes to long-format afterwards.
 *
 * Index conventions: integer inputs from R are 1-indexed (positions in
 *   the original [n_coh, n_dev] grid or in the link/dev vectors). The
 *   kernel converts to 0-indexed on entry. NA_INTEGER means "absent".
 *
 * RNG: kernels that resample residuals call GetRNGstate() once on entry
 *   and PutRNGstate() once on exit. R's `set.seed()` controls the seed.
 *   Drawing uses `unif_rand() * pool_size` floored to an int index.
 *
 * Pool layout (CSR-like, used by cell + link residual kernels):
 *   - pool_residuals : concatenated residual values from every pool.
 *   - pool_starts    : length n_pools + 1; pool p occupies
 *                      pool_residuals[pool_starts[p-1] : pool_starts[p]-1]
 *                      (1-indexed pool ids match R-level).
 *   - cell_pool_idx /
 *     link_pool_idx  : 1-indexed pool id per active cell / per link
 *                      (0 means "no pool" — residual draw falls back
 *                      to zero so the cell stays at its fitted value).
 *
 * Native routine registration lives in src/init.c. Public function
 * signatures are declared in src/lossratio.h. R-side counterpart is
 * R/bootstrap.R; `.boot_stage1_one()` dispatches into the kernel
 * matching the requested residual / type combination.
 * =============================================================================
 */
#include "lossratio.h"
#include <math.h>    /* sqrt, pow, fabs */
#include <stdlib.h>  /* qsort */
#include <string.h>  /* memset, memcpy */
#include <Rmath.h>   /* Rf_rgamma */


/* =============================================================================
 * Section 1 — Shared helpers (file-local; only kernels in this TU use them)
 * =============================================================================
 */

/* Ascending comparator for qsort of doubles. */
static int cmp_dbl_asc(const void *a, const void *b) {
  double da = *(const double *)a, db = *(const double *)b;
  return (da > db) - (da < db);
}

/* bootstrap_refit_fstar
 *
 *   Volume-weighted refit of f*_k per link, per replicate, from the
 *   already-built pseudo cumulative array `cum` [n_coh, n_dev, B]. Cells
 *   outside the upper triangle are expected to be NA_real_ so they
 *   contribute neither to numerator nor denominator. When the
 *   denominator sum is non-positive the factor falls back to
 *   `f_hat_vec[k]` (the anchor f_k from the original data).
 *
 *   `f_k` (anchor) and `f*_k` (bootstrap refit) are distinct quantities:
 *     - f_hat_vec[k]    : scalar anchor from original cumulative
 *     - f_star[k, b]    : bootstrap refit at replicate b, scalar
 *     - f_star (output) : full [n_links, B] matrix, column-major
 */
static void bootstrap_refit_fstar(
    const double *cum,
    const int *link_to_idx,
    const double *f_hat_vec,
    int n_coh, int n_dev, int B, int n_links,
    double *f_star) {

  R_xlen_t slab = (R_xlen_t)n_coh * n_dev;
  for (int k = 0; k < n_links; k++) {
    int to_col_1 = link_to_idx[k];
    int fallback = !(to_col_1 != NA_INTEGER && to_col_1 >= 2);
    if (fallback) {
      for (int b = 0; b < B; b++)
        f_star[k + (R_xlen_t)b * n_links] = f_hat_vec[k];
      continue;
    }
    int from_col = to_col_1 - 2;
    int to_col   = to_col_1 - 1;
    R_xlen_t off_from_base = (R_xlen_t)from_col * n_coh;
    R_xlen_t off_to_base   = (R_xlen_t)to_col   * n_coh;
    for (int b = 0; b < B; b++) {
      R_xlen_t b_off = (R_xlen_t)b * slab;
      double num = 0.0, den = 0.0;
      for (int i = 0; i < n_coh; i++) {
        double from_v = cum[off_from_base + b_off + i];
        double to_v   = cum[off_to_base   + b_off + i];
        if (R_FINITE(from_v) && R_FINITE(to_v)) {
          num += to_v;
          den += from_v;
        }
      }
      f_star[k + (R_xlen_t)b * n_links] =
        (R_FINITE(den) && den > 0.0) ? (num / den) : f_hat_vec[k];
    }
  }
}


/* bootstrap_fwd_proj_and_clip
 *
 *   Fill lower-triangle cells of `cum` [n_coh, n_dev, B] dev by dev,
 *   then clip finite negatives to 0. For each dev j (2..n_dev), cohorts
 *   with last_obs_idx[i] < j receive
 *       cum[i, j, b] = f*[k, b] * cum[i, j-1, b]
 *   where k = k_idx_by_j[j] (1-indexed; NA -> carry forward unchanged).
 *
 *   Caller is responsible for populating `f_star` (refit for cell/link,
 *   direct random draw for parametric).
 */
static void bootstrap_fwd_proj_and_clip(
    double *cum, const double *f_star,
    const int *last_obs_idx, const int *k_idx_by_j,
    int n_coh, int n_dev, int B, int n_links) {

  R_xlen_t slab = (R_xlen_t)n_coh * n_dev;

  for (int j = 1; j < n_dev; j++) {
    int k_idx_1 = k_idx_by_j[j];
    int k_idx   = (k_idx_1 == NA_INTEGER) ? -1 : (k_idx_1 - 1);
    R_xlen_t off_curr_base = (R_xlen_t)j       * n_coh;
    R_xlen_t off_prev_base = (R_xlen_t)(j - 1) * n_coh;
    for (int i = 0; i < n_coh; i++) {
      int lj = last_obs_idx[i];
      if (lj == NA_INTEGER) continue;
      if (lj >= j + 1) continue;           /* upper triangle: keep */
      for (int b = 0; b < B; b++) {
        R_xlen_t b_off = (R_xlen_t)b * slab;
        double base = cum[off_prev_base + b_off + i];
        if (k_idx < 0) {
          cum[off_curr_base + b_off + i] = base;
        } else {
          double f_b = f_star[k_idx + (R_xlen_t)b * n_links];
          if (!R_FINITE(f_b)) f_b = 1.0;
          cum[off_curr_base + b_off + i] = f_b * base;
        }
      }
    }
  }

  R_xlen_t total = slab * B;
  for (R_xlen_t p = 0; p < total; p++) {
    if (R_FINITE(cum[p]) && cum[p] < 0.0) cum[p] = 0.0;
  }
}


/* bootstrap_fwd_sim_cell
 *
 *   Produces `cum_sampled` by noisy forward simulation on the lower
 *   triangle of `cum_mean` (cell / ODP paradigm). For each cohort i and
 *   replicate b, walking dev j = last_obs_idx[i] .. n_dev-1:
 *
 *     inc_mean    = cum_mean[i, j, b] - cum_mean[i, j-1, b]
 *     inc_sampled = ProcessDist(inc_mean, var = phi * |inc_mean|^alpha)
 *     cum_sampled[i, j, b] = cum_sampled[i, j-1, b] + inc_sampled
 *
 *   Upper triangle of `cum_sampled` is copied from `cum_mean` unchanged
 *   (the upper triangle of cum_mean already carries the Stage 1
 *   perturbation — the residual / parametric draw — so no further noise
 *   is added there). The two arrays therefore differ only on the
 *   projected region; their cohort-by-cohort cumulative variance over B
 *   gives the Pythagorean SE decomposition param_se / proc_se.
 *
 *   process_code:
 *     1 (gamma) / 2 (od_pois)  : rgamma(shape = inc_mean / phi,
 *                                       scale = phi)
 *                                 (Gamma moment-matched ODP — mean =
 *                                  shape * scale = inc_mean,
 *                                  var = shape * scale^2 = phi * inc_mean,
 *                                  i.e. alpha = 1; with alpha != 1 the
 *                                  variance formula generalises to
 *                                  phi * |inc_mean|^alpha — currently
 *                                  alpha is metadata only, the gamma
 *                                  scale is phi as in the ODP / E-V
 *                                  literature.)
 *     3 (normal)               : inc_mean + rnorm(0, sqrt(phi * |inc_mean|^alpha))
 *
 *   For inc_mean <= 0 or non-finite, the draw is deterministic (no
 *   noise): cum_sampled accumulates the bare inc_mean. This preserves
 *   the trajectory shape when the chain ladder produces non-positive
 *   increments in extrapolation.
 *
 *   `phi`: scalar group-level dispersion (per-group in cell mode).
 *   `alpha`: variance exponent (Mack's alpha; 1 = volume-weighted).
 *   `last_obs_idx`: 1-indexed last observed dev per cohort; NA_INTEGER
 *                   skips the cohort entirely.
 *
 *   `cum_mean` and `cum_sampled` are both column-major [n_coh, n_dev, B].
 */
static void bootstrap_fwd_sim_cell(
    const double *cum_mean,
    const int *last_obs_idx,
    int n_coh, int n_dev, int B,
    double phi, double alpha,
    int process_code,
    double *cum_sampled) {

  R_xlen_t slab  = (R_xlen_t)n_coh * n_dev;
  R_xlen_t total = slab * B;

  /* Initialize cum_sampled = cum_mean — upper triangle stays unchanged,
   * lower triangle is overwritten by noisy forward sim below. */
  memcpy(cum_sampled, cum_mean, (size_t)total * sizeof(double));

  if (!R_FINITE(phi) || phi <= 0.0) return;

  GetRNGstate();
  for (int b = 0; b < B; b++) {
    R_xlen_t b_off = (R_xlen_t)b * slab;
    for (int i = 0; i < n_coh; i++) {
      int lj = last_obs_idx[i];                /* 1-indexed */
      if (lj == NA_INTEGER) continue;
      if (lj >= n_dev) continue;               /* fully observed cohort */

      /* prev_sampled starts at the last observed cumulative cell
       * (0-indexed col = lj - 1, copied from cum_mean above). */
      double prev_sampled = cum_sampled[b_off + (R_xlen_t)(lj - 1) * n_coh + i];
      if (!R_FINITE(prev_sampled)) continue;

      for (int j = lj; j < n_dev; j++) {
        R_xlen_t off_curr = b_off + (R_xlen_t)j       * n_coh + i;
        R_xlen_t off_prev = b_off + (R_xlen_t)(j - 1) * n_coh + i;
        double cum_curr = cum_mean[off_curr];
        double cum_prev = cum_mean[off_prev];
        if (!R_FINITE(cum_curr) || !R_FINITE(cum_prev)) {
          cum_sampled[off_curr] = NA_REAL;
          continue;
        }
        double inc_mean = cum_curr - cum_prev;
        double inc_sampled;
        if (R_FINITE(inc_mean) && inc_mean > 0.0) {
          switch (process_code) {
            case 1:   /* gamma */
            case 2: { /* od_pois (Gamma moment-matched) */
              double shape = inc_mean / phi;
              double scale = phi;
              inc_sampled = Rf_rgamma(shape, scale);
              break;
            }
            case 3: { /* normal */
              double sd = sqrt(phi * pow(fabs(inc_mean), alpha));
              inc_sampled = inc_mean + norm_rand() * sd;
              break;
            }
            default:
              inc_sampled = inc_mean;
          }
        } else {
          inc_sampled = inc_mean;  /* deterministic for non-positive mean */
        }
        cum_sampled[off_curr] = prev_sampled + inc_sampled;
        prev_sampled = cum_sampled[off_curr];
      }
    }
  }
  PutRNGstate();
}


/* bootstrap_fwd_sim_link
 *
 *   Mack-paradigm forward simulation: per-link cumulative recursion
 *
 *     C_{i,k+1} = f*_k * C_{i,k} + epsilon_{i,k+1}
 *     epsilon ~ ProcessDist(mean = f*_k * C_{i,k},
 *                            var  = sigma^2_k * C_{i,k}^alpha)
 *
 *   For each cohort i, projecting from j = last_obs_idx[i] to n_dev,
 *   using the SAME f_star (refit) as cum_mean uses — so the *mean
 *   trajectory* of cum_sampled equals cum_mean, but each step accumulates
 *   noise from sigma2_k. The two arrays differ on the lower triangle
 *   only.
 *
 *   sigma2_vec[k] : per-link Mack sigma^2 (anchored from original data,
 *                   NOT refit per replicate — Phase 5 design).
 *   f_star[k, b]  : per-replicate refit factors (same as caller's f_star
 *                   used by bootstrap_fwd_proj_and_clip).
 *   alpha         : variance exponent.
 *   process_code  : 1 gamma / 2 od_pois (Gamma moment-matched) / 3 normal.
 *
 *   For pathological cases (non-finite f, non-positive prev, NA), the
 *   noisy step degenerates to the deterministic recursion.
 */
static void bootstrap_fwd_sim_link(
    const double *cum_mean,
    const int *last_obs_idx,
    const int *k_idx_by_j,
    const double *f_star,         /* [n_links * B] */
    const double *sigma2_vec,     /* [n_links] */
    int n_coh, int n_dev, int B, int n_links,
    double alpha,
    int process_code,
    double *cum_sampled) {

  R_xlen_t slab  = (R_xlen_t)n_coh * n_dev;
  R_xlen_t total = slab * B;

  /* Initialize cum_sampled = cum_mean. Upper-triangle stays; lower
   * triangle is overwritten below. */
  memcpy(cum_sampled, cum_mean, (size_t)total * sizeof(double));

  GetRNGstate();
  for (int b = 0; b < B; b++) {
    R_xlen_t b_off = (R_xlen_t)b * slab;
    for (int i = 0; i < n_coh; i++) {
      int lj = last_obs_idx[i];
      if (lj == NA_INTEGER) continue;
      if (lj >= n_dev) continue;
      double prev_sampled =
        cum_sampled[b_off + (R_xlen_t)(lj - 1) * n_coh + i];
      if (!R_FINITE(prev_sampled)) continue;

      for (int j = lj; j < n_dev; j++) {
        R_xlen_t off_curr = b_off + (R_xlen_t)j * n_coh + i;
        int k_idx_1 = k_idx_by_j[j];
        if (k_idx_1 == NA_INTEGER) {
          cum_sampled[off_curr] = prev_sampled;
          continue;
        }
        int k = k_idx_1 - 1;
        double f_b = f_star[k + (R_xlen_t)b * n_links];
        if (!R_FINITE(f_b)) f_b = 1.0;
        double mu_step = f_b * prev_sampled;
        double s2_k = (k >= 0 && k < n_links) ? sigma2_vec[k] : NA_REAL;
        double new_sampled;
        if (R_FINITE(s2_k) && s2_k > 0.0 &&
            R_FINITE(prev_sampled) && prev_sampled > 0.0) {
          double var = s2_k * pow(fabs(prev_sampled), alpha);
          if (R_FINITE(var) && var > 0.0 && R_FINITE(mu_step) && mu_step > 0.0) {
            switch (process_code) {
              case 1:   /* gamma */
              case 2: { /* od_pois */
                double shape = mu_step * mu_step / var;
                double scale = var / mu_step;
                new_sampled = Rf_rgamma(shape, scale);
                break;
              }
              case 3: { /* normal */
                new_sampled = mu_step + norm_rand() * sqrt(var);
                break;
              }
              default:
                new_sampled = mu_step;
            }
          } else {
            new_sampled = mu_step;
          }
        } else {
          new_sampled = mu_step;
        }
        if (R_FINITE(new_sampled) && new_sampled < 0.0) new_sampled = 0.0;
        cum_sampled[off_curr] = new_sampled;
        prev_sampled = new_sampled;
      }
    }
  }
  PutRNGstate();
}


/* bootstrap_summary_decompose
 *
 *   Per (cohort i, dev j) cell, compute the Pythagorean SE decomposition
 *   from the two replicate arrays `cum_mean` (Stage 1) and `cum_sampled`
 *   (Stage 1 + Stage 2):
 *
 *     mean_proj  = mean(cum_mean[i, j, .])
 *     param_se   = sd  (cum_mean[i, j, .])         (parameter uncertainty)
 *     total_se   = sd  (cum_sampled[i, j, .])      (full predictive)
 *     proc_se    = sqrt(pmax(total_se^2 - param_se^2, 0))   (process)
 *     total_cv   = total_se / mean_proj            (NA when mean_proj <= 0)
 *
 *   `na.rm = TRUE` semantics -- only finite (i, j, b) cells contribute.
 *   Two-pass: sum / sum-of-squares around the sample mean (numerically
 *   adequate for B in the 100-10000 range).
 *
 *   Output arrays are flat length n_coh x n_dev (column-major,
 *   cohort fastest). When n < 2 for a cell, all outputs = NA_real_.
 *
 *   Optional quantile CI: when `out_ci_lo` is non-NULL, also emits
 *   `n_probs` empirical percentile bounds per cell from `cum_sampled`.
 *   `probs` carries the target probabilities (typically c(0.025, 0.975)
 *   so `n_probs == 2`, with `out_ci_lo` / `out_ci_hi` receiving the
 *   first / last). Davison-Hinkley type=1 ordinal: rank
 *   `idx = ceil(p * n_finite) - 1` (0-indexed) on the ascending-sorted
 *   finite values. When `n_finite < 2`, both CI slots are NA_real_.
 *   `scratch` is a caller-supplied length-B reusable buffer.
 *
 *   Replaces the R-level `data.table` group-wise aggregation that
 *   bypassed gforce on `quantile` and was the dominant cost of the
 *   `$summary` build. mean/sd/proc/total/cv/CI all single-pass C loops
 *   (CI adds one qsort per cell on the finite values only).
 */
static void bootstrap_summary_decompose(
    const double *cum_mean,
    const double *cum_sampled,
    int n_coh, int n_dev, int B,
    double *out_mean,
    double *out_param_se,
    double *out_proc_se,
    double *out_total_se,
    double *out_total_cv,
    double *out_ci_lo,
    double *out_ci_hi,
    int n_probs,
    const double *probs,
    double *scratch) {

  R_xlen_t slab = (R_xlen_t)n_coh * n_dev;
  int want_ci = (out_ci_lo != NULL);

  for (int j = 0; j < n_dev; j++) {
    R_xlen_t col_base = (R_xlen_t)j * n_coh;
    for (int i = 0; i < n_coh; i++) {
      R_xlen_t cell_off = col_base + i;
      double sum_m = 0.0, sum_s = 0.0;
      int n = 0;
      for (int b = 0; b < B; b++) {
        double v_m = cum_mean   [cell_off + (R_xlen_t)b * slab];
        double v_s = cum_sampled[cell_off + (R_xlen_t)b * slab];
        if (R_FINITE(v_m) && R_FINITE(v_s)) {
          sum_m += v_m;
          sum_s += v_s;
          n++;
        }
      }
      if (n < 2) {
        out_mean    [cell_off] = NA_REAL;
        out_param_se[cell_off] = NA_REAL;
        out_proc_se [cell_off] = NA_REAL;
        out_total_se[cell_off] = NA_REAL;
        out_total_cv[cell_off] = NA_REAL;
        if (want_ci) {
          out_ci_lo[cell_off] = NA_REAL;
          out_ci_hi[cell_off] = NA_REAL;
        }
        continue;
      }
      double mean_m = sum_m / n;
      double mean_s = sum_s / n;
      double ssq_m = 0.0, ssq_s = 0.0;
      for (int b = 0; b < B; b++) {
        double v_m = cum_mean   [cell_off + (R_xlen_t)b * slab];
        double v_s = cum_sampled[cell_off + (R_xlen_t)b * slab];
        if (R_FINITE(v_m) && R_FINITE(v_s)) {
          double dm = v_m - mean_m;
          double ds = v_s - mean_s;
          ssq_m += dm * dm;
          ssq_s += ds * ds;
        }
      }
      double var_m  = ssq_m / (n - 1);
      double var_s  = ssq_s / (n - 1);
      double var_p  = var_s - var_m;
      if (var_p < 0.0) var_p = 0.0;   /* finite-B noise clamp */
      double total_se = sqrt(var_s);
      out_mean    [cell_off] = mean_m;
      out_param_se[cell_off] = sqrt(var_m);
      out_proc_se [cell_off] = sqrt(var_p);
      out_total_se[cell_off] = total_se;
      out_total_cv[cell_off] =
        (R_FINITE(mean_m) && mean_m > 0.0) ? (total_se / mean_m) : NA_REAL;

      if (want_ci) {
        /* Collect finite cum_sampled values for this cell -- na.rm = TRUE
         * semantics matching stats::quantile(..., na.rm = TRUE, type = 1). */
        int n_fin = 0;
        for (int b = 0; b < B; b++) {
          double v_s = cum_sampled[cell_off + (R_xlen_t)b * slab];
          if (R_FINITE(v_s)) scratch[n_fin++] = v_s;
        }
        if (n_fin < 2) {
          out_ci_lo[cell_off] = NA_REAL;
          out_ci_hi[cell_off] = NA_REAL;
        } else {
          qsort(scratch, (size_t)n_fin, sizeof(double), cmp_dbl_asc);
          /* type = 1 ordinal: idx0 = ceil(p * n) - 1 (0-indexed). */
          for (int q = 0; q < n_probs; q++) {
            double p_q = probs[q];
            int idx0 = (int)ceil(p_q * (double)n_fin) - 1;
            if (idx0 < 0) idx0 = 0;
            if (idx0 >= n_fin) idx0 = n_fin - 1;
            double v = scratch[idx0];
            if (q == 0)              out_ci_lo[cell_off] = v;
            if (q == n_probs - 1)    out_ci_hi[cell_off] = v;
          }
        }
      }
    }
  }
}


/* =============================================================================
 * Section 2 — Cell-residual kernel (residual = "cell")
 *
 * Six fused phases:
 *   (a) Resample residuals + place pseudo incrementals.
 *   (b) Cumulative sum along the dev axis (per cohort × replicate).
 *   (c) Mask lower triangle to NA_real_.
 *   (d) Refit f*_k per link  -> bootstrap_refit_fstar.
 *   (e) Forward-project + clip negatives -> bootstrap_fwd_proj_and_clip.
 *   (f) Apply Stage 2 process noise on lower triangle ->
 *       bootstrap_fwd_sim_cell. Produces `cum_sampled` alongside the
 *       Stage 1 `cum_mean`; the two arrays are returned as a named list.
 *
 * Returns:
 *   list(cum_mean    = real[n_coh, n_dev, B],   // Stage 1 only
 *        cum_sampled = real[n_coh, n_dev, B])   // Stage 1 + Stage 2
 * =============================================================================
 */

/* bootstrap_summary_kernel
 *
 *   R-callable entry that takes the two cumulative arrays (column-major
 *   length n_coh x n_dev x B) and returns a named list of five (or seven)
 *   flat length n_coh x n_dev REALSXPs: mean_proj, param_se, proc_se,
 *   total_se, total_cv -- plus ci_lo, ci_hi when `quantile_ci_sxp` is
 *   TRUE. Wraps the file-local bootstrap_summary_decompose helper so
 *   R-side .boot_summary_from_arrays() / .boot_summary_decompose() can
 *   produce the $summary slot in C -- bypassing data.table's R-level
 *   group-wise aggregation (which costs ~1.2s on typical experience
 *   triangles because quantile bypasses gforce; mean/sd also incur
 *   thousands of group-dispatch hits).
 *
 *   `probs_sxp` is honoured only when `quantile_ci_sxp` is TRUE. Length
 *   is typically 2 (c(0.025, 0.975)); the first prob populates ci_lo and
 *   the last populates ci_hi. CI uses Davison-Hinkley type=1 ordinal
 *   ranks `ceil(p * n_finite)` (1-indexed) on the finite cum_sampled
 *   values per cell; NA_real_ when fewer than 2 finite values exist.
 */
SEXP bootstrap_summary_kernel(
    SEXP cum_mean_sxp,
    SEXP cum_sampled_sxp,
    SEXP n_coh_sxp,
    SEXP n_dev_sxp,
    SEXP n_groups_sxp,
    SEXP quantile_ci_sxp,
    SEXP probs_sxp) {

  int n_coh    = Rf_asInteger(n_coh_sxp);
  int n_dev    = Rf_asInteger(n_dev_sxp);
  int n_groups = Rf_asInteger(n_groups_sxp);
  int want_ci  = Rf_asLogical(quantile_ci_sxp) == TRUE;

  if (n_coh <= 0 || n_dev <= 0 || n_groups <= 0)
    Rf_error("n_coh, n_dev, n_groups must all be positive.");

  R_xlen_t slab  = (R_xlen_t)n_coh * n_dev;
  R_xlen_t total = XLENGTH(cum_mean_sxp);
  if (total != XLENGTH(cum_sampled_sxp))
    Rf_error("cum_mean and cum_sampled must have the same length.");

  R_xlen_t per_group = total / n_groups;
  if (per_group * n_groups != total)
    Rf_error("input length not divisible by n_groups.");
  if (per_group % slab != 0)
    Rf_error("per-group length must be a multiple of n_coh * n_dev.");
  int B = (int)(per_group / slab);
  if (B < 2)
    Rf_error("B must be at least 2 for SD computation.");

  int n_probs = 0;
  const double *probs = NULL;
  if (want_ci) {
    if (TYPEOF(probs_sxp) != REALSXP)
      Rf_error("probs must be a numeric vector when quantile_ci = TRUE.");
    n_probs = LENGTH(probs_sxp);
    if (n_probs < 1)
      Rf_error("probs must have length >= 1 when quantile_ci = TRUE.");
    probs = REAL(probs_sxp);
  }

  double *cum_mean    = REAL(cum_mean_sxp);
  double *cum_sampled = REAL(cum_sampled_sxp);

  R_xlen_t out_len = slab * n_groups;
  int n_protect = 0;
  SEXP out_mean   = PROTECT(Rf_allocVector(REALSXP, out_len)); n_protect++;
  SEXP out_param  = PROTECT(Rf_allocVector(REALSXP, out_len)); n_protect++;
  SEXP out_proc   = PROTECT(Rf_allocVector(REALSXP, out_len)); n_protect++;
  SEXP out_total  = PROTECT(Rf_allocVector(REALSXP, out_len)); n_protect++;
  SEXP out_cv     = PROTECT(Rf_allocVector(REALSXP, out_len)); n_protect++;
  SEXP out_ci_lo  = R_NilValue;
  SEXP out_ci_hi  = R_NilValue;
  if (want_ci) {
    out_ci_lo = PROTECT(Rf_allocVector(REALSXP, out_len)); n_protect++;
    out_ci_hi = PROTECT(Rf_allocVector(REALSXP, out_len)); n_protect++;
  }

  /* One reusable scratch buffer for quantile collection -- avoids
   * per-cell malloc/free churn. R_alloc cleans up automatically on
   * function exit. Only allocated when CI is requested. */
  double *scratch = want_ci
    ? (double *) R_alloc((size_t)B, sizeof(double))
    : NULL;

  /* block-major: each group occupies a contiguous per_group span.
   * Within each block, layout is the same column-major [n_coh, n_dev, B]
   * that the kernel produced and that the long-format reshape preserved. */
  for (int g = 0; g < n_groups; g++) {
    R_xlen_t in_off  = (R_xlen_t)g * per_group;
    R_xlen_t out_off = (R_xlen_t)g * slab;
    bootstrap_summary_decompose(
      cum_mean    + in_off,
      cum_sampled + in_off,
      n_coh, n_dev, B,
      REAL(out_mean)  + out_off,
      REAL(out_param) + out_off,
      REAL(out_proc)  + out_off,
      REAL(out_total) + out_off,
      REAL(out_cv)    + out_off,
      want_ci ? (REAL(out_ci_lo) + out_off) : NULL,
      want_ci ? (REAL(out_ci_hi) + out_off) : NULL,
      n_probs, probs, scratch);
  }

  int n_out = want_ci ? 7 : 5;
  SEXP out = PROTECT(Rf_allocVector(VECSXP, n_out)); n_protect++;
  SET_VECTOR_ELT(out, 0, out_mean);
  SET_VECTOR_ELT(out, 1, out_param);
  SET_VECTOR_ELT(out, 2, out_proc);
  SET_VECTOR_ELT(out, 3, out_total);
  SET_VECTOR_ELT(out, 4, out_cv);
  if (want_ci) {
    SET_VECTOR_ELT(out, 5, out_ci_lo);
    SET_VECTOR_ELT(out, 6, out_ci_hi);
  }
  SEXP nm = PROTECT(Rf_allocVector(STRSXP, n_out)); n_protect++;
  SET_STRING_ELT(nm, 0, Rf_mkChar("mean_proj"));
  SET_STRING_ELT(nm, 1, Rf_mkChar("param_se"));
  SET_STRING_ELT(nm, 2, Rf_mkChar("proc_se"));
  SET_STRING_ELT(nm, 3, Rf_mkChar("total_se"));
  SET_STRING_ELT(nm, 4, Rf_mkChar("total_cv"));
  if (want_ci) {
    SET_STRING_ELT(nm, 5, Rf_mkChar("ci_lo"));
    SET_STRING_ELT(nm, 6, Rf_mkChar("ci_hi"));
  }
  Rf_setAttrib(out, R_NamesSymbol, nm);

  UNPROTECT(n_protect);
  return out;
}


SEXP bootstrap_kernel_cell(
    SEXP B_sxp,
    SEXP mu_active_sxp,         /* [n_active] doubles                       */
    SEXP sqrt_active_sxp,       /* [n_active] doubles (= sqrt(|mu_active|)) */
    SEXP active_lin_sxp,        /* [n_active] ints (1-indexed pos in n_coh x n_dev) */
    SEXP cell_pool_idx_sxp,     /* [n_active] ints (1-indexed pool id, or 0) */
    SEXP pool_residuals_sxp,    /* concatenated pool residuals              */
    SEXP pool_starts_sxp,       /* [n_pools + 1] ints                       */
    SEXP last_obs_idx_sxp,      /* [n_coh] ints (1-indexed) or NA           */
    SEXP link_to_idx_sxp,       /* [n_links] ints (1-indexed)               */
    SEXP k_idx_by_j_sxp,        /* [n_dev] ints (1-indexed) or NA           */
    SEXP f_hat_vec_sxp,         /* [n_links] doubles                        */
    SEXP phi_sxp,               /* scalar dispersion phi (cell mode)        */
    SEXP alpha_sxp,             /* scalar variance exponent                 */
    SEXP process_code_sxp,      /* int: 1 gamma / 2 od_pois / 3 normal     */
    SEXP n_coh_sxp,
    SEXP n_dev_sxp) {

  int B       = Rf_asInteger(B_sxp);
  int n_coh   = Rf_asInteger(n_coh_sxp);
  int n_dev   = Rf_asInteger(n_dev_sxp);
  int n_active = LENGTH(active_lin_sxp);
  int n_links = LENGTH(link_to_idx_sxp);
  int n_pools = LENGTH(pool_starts_sxp) - 1;

  if (B <= 0 || n_coh <= 0 || n_dev <= 0)
    Rf_error("B, n_coh, n_dev must all be positive.");
  if (LENGTH(mu_active_sxp)     != n_active ||
      LENGTH(sqrt_active_sxp)   != n_active ||
      LENGTH(cell_pool_idx_sxp) != n_active)
    Rf_error("mu_active / sqrt_active / cell_pool_idx must each have length n_active.");
  if (LENGTH(last_obs_idx_sxp) != n_coh)
    Rf_error("last_obs_idx must have length n_coh.");
  if (LENGTH(k_idx_by_j_sxp)   != n_dev)
    Rf_error("k_idx_by_j must have length n_dev.");
  if (LENGTH(f_hat_vec_sxp)    != n_links)
    Rf_error("f_hat_vec must have length n_links.");
  if (n_pools < 0)
    Rf_error("pool_starts must have length >= 1.");

  double *mu_active   = REAL(mu_active_sxp);
  double *sqrt_active = REAL(sqrt_active_sxp);
  int *active_lin     = INTEGER(active_lin_sxp);
  int *cell_pool_idx  = INTEGER(cell_pool_idx_sxp);
  double *pool_resid  = REAL(pool_residuals_sxp);
  int *pool_starts    = INTEGER(pool_starts_sxp);
  int *last_obs_idx   = INTEGER(last_obs_idx_sxp);
  int *link_to_idx    = INTEGER(link_to_idx_sxp);
  int *k_idx_by_j     = INTEGER(k_idx_by_j_sxp);
  double *f_hat_vec   = REAL(f_hat_vec_sxp);

  R_xlen_t slab  = (R_xlen_t)n_coh * n_dev;
  R_xlen_t total = slab * B;

  /* Allocate output [n_coh, n_dev, B]. */
  SEXP cum_sxp = PROTECT(Rf_allocVector(REALSXP, total));
  SEXP dims = PROTECT(Rf_allocVector(INTSXP, 3));
  INTEGER(dims)[0] = n_coh;
  INTEGER(dims)[1] = n_dev;
  INTEGER(dims)[2] = B;
  Rf_setAttrib(cum_sxp, R_DimSymbol, dims);
  UNPROTECT(1); /* dims held via setAttrib */

  double *cum = REAL(cum_sxp);
  memset(cum, 0, (size_t)total * sizeof(double));

  /* ----- (a) Resample residuals + place increments ------------------- */
  GetRNGstate();
  for (int b = 0; b < B; b++) {
    R_xlen_t b_off = (R_xlen_t)b * slab;
    for (int a = 0; a < n_active; a++) {
      double mu = mu_active[a];
      if (!R_FINITE(mu)) continue;
      double r_star = 0.0;
      int pid = cell_pool_idx[a];           /* 1-indexed; 0 == no pool */
      if (pid != NA_INTEGER && pid > 0 && pid <= n_pools) {
        int start = pool_starts[pid - 1];
        int end   = pool_starts[pid];
        int psz   = end - start;
        if (psz > 0) {
          int idx = (int)(unif_rand() * psz);
          if (idx >= psz) idx = psz - 1;
          r_star = pool_resid[start + idx];
        }
      }
      cum[b_off + active_lin[a] - 1] = mu + r_star * sqrt_active[a];
    }
  }
  PutRNGstate();

  /* ----- (b) Cumsum along dev (per cohort × replicate) --------------- */
  for (int b = 0; b < B; b++) {
    R_xlen_t b_off = (R_xlen_t)b * slab;
    for (int j = 1; j < n_dev; j++) {
      R_xlen_t off_curr = b_off + (R_xlen_t)j * n_coh;
      R_xlen_t off_prev = off_curr - n_coh;
      for (int i = 0; i < n_coh; i++) {
        cum[off_curr + i] += cum[off_prev + i];
      }
    }
  }

  /* ----- (c) Mask lower triangle to NA ------------------------------- */
  for (int i = 0; i < n_coh; i++) {
    int L = last_obs_idx[i];
    int j_start = (L == NA_INTEGER) ? 0 : L;
    for (int j = j_start; j < n_dev; j++) {
      R_xlen_t col_base = (R_xlen_t)j * n_coh + i;
      for (int b = 0; b < B; b++) {
        cum[col_base + (R_xlen_t)b * slab] = NA_REAL;
      }
    }
  }

  /* ----- (d) Refit f*_k from pseudo cumulative ----------------------- */
  double *f_star = (double *) R_alloc((size_t)n_links * B, sizeof(double));
  bootstrap_refit_fstar(cum, link_to_idx, f_hat_vec,
                        n_coh, n_dev, B, n_links, f_star);

  /* ----- (e) Forward-project + clip ---------------------------------- */
  bootstrap_fwd_proj_and_clip(cum, f_star, last_obs_idx, k_idx_by_j,
                              n_coh, n_dev, B, n_links);

  /* ----- (f) Stage 2 process noise -> cum_sampled -------------------- */
  double phi          = Rf_asReal(phi_sxp);
  double alpha        = Rf_asReal(alpha_sxp);
  int    process_code = Rf_asInteger(process_code_sxp);

  SEXP cum_sampled_sxp = PROTECT(Rf_allocVector(REALSXP, total));
  SEXP dims_s = PROTECT(Rf_allocVector(INTSXP, 3));
  INTEGER(dims_s)[0] = n_coh;
  INTEGER(dims_s)[1] = n_dev;
  INTEGER(dims_s)[2] = B;
  Rf_setAttrib(cum_sampled_sxp, R_DimSymbol, dims_s);
  UNPROTECT(1); /* dims_s held via setAttrib */

  bootstrap_fwd_sim_cell(cum, last_obs_idx, n_coh, n_dev, B,
                              phi, alpha, process_code,
                              REAL(cum_sampled_sxp));

  /* ----- Return list(cum_mean, cum_sampled) -------------------------- */
  SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
  SET_VECTOR_ELT(out, 0, cum_sxp);
  SET_VECTOR_ELT(out, 1, cum_sampled_sxp);
  SEXP nm = PROTECT(Rf_allocVector(STRSXP, 2));
  SET_STRING_ELT(nm, 0, Rf_mkChar("cum_mean"));
  SET_STRING_ELT(nm, 1, Rf_mkChar("cum_sampled"));
  Rf_setAttrib(out, R_NamesSymbol, nm);

  UNPROTECT(4);  /* cum_sxp, cum_sampled_sxp, out, nm */
  return out;
}


/* =============================================================================
 * Section 3 — Link-residual kernel (residual = "link")
 *
 * Five fused phases (mirrors R/bootstrap.R:1167-1233 exactly):
 *   (a) Initialize cum to NA_real_; copy `mat_obs` column 0 to cum col 0
 *       across all replicates (the base of the cumulative recursion).
 *   (b) Per replicate, per link k: chain residual resample on cumulative
 *       cells where mat_obs[i, to_col] is observed AND prev_alt > 0:
 *           cum[i, to_col, b] = f_hat[k] * prev_alt
 *                             + r_star * sqrt(sigma2[k] * prev_alt)
 *       — `r_star` drawn from pool `link_pool_idx[k]` (0 → no pool).
 *   (c) Pre-refit clip: zero finite negatives in the upper triangle.
 *   (d) Refit f*_k per link -> bootstrap_refit_fstar.
 *   (e) Forward-project lower triangle + final clip ->
 *       bootstrap_fwd_proj_and_clip.
 *
 * RNG draw order matches R `sample(pool, n_alt, replace=TRUE)` semantics
 * (per-cohort `unif_rand() * pool_size` floored) so the outer loop order
 * (b outer, k inner, i innermost over was_obs cohorts) gives the same
 * sequence under a fixed seed.
 * =============================================================================
 */

SEXP bootstrap_kernel_link(
    SEXP B_sxp,
    SEXP mat_obs_sxp,             /* [n_coh × n_dev] doubles, observed cum   */
    SEXP last_obs_idx_sxp,        /* [n_coh] ints (1-indexed) or NA          */
    SEXP link_to_idx_sxp,         /* [n_links] ints (1-indexed) or NA        */
    SEXP k_idx_by_j_sxp,          /* [n_dev] ints (1-indexed) or NA          */
    SEXP f_hat_vec_sxp,           /* [n_links] doubles                       */
    SEXP sigma2_vec_sxp,          /* [n_links] doubles (Mack sigma^2)        */
    SEXP link_pool_idx_sxp,       /* [n_links] ints (1-indexed pool id, or 0) */
    SEXP pool_residuals_sxp,      /* concatenated pool residuals             */
    SEXP pool_starts_sxp,         /* [n_pools + 1] ints                      */
    SEXP alpha_sxp,               /* scalar variance exponent                */
    SEXP process_code_sxp,        /* int: 1 gamma / 2 od_pois / 3 normal     */
    SEXP n_coh_sxp,
    SEXP n_dev_sxp) {

  int B       = Rf_asInteger(B_sxp);
  int n_coh   = Rf_asInteger(n_coh_sxp);
  int n_dev   = Rf_asInteger(n_dev_sxp);
  int n_links = LENGTH(link_to_idx_sxp);
  int n_pools = LENGTH(pool_starts_sxp) - 1;

  if (B <= 0 || n_coh <= 0 || n_dev <= 0)
    Rf_error("B, n_coh, n_dev must all be positive.");
  if (XLENGTH(mat_obs_sxp) != (R_xlen_t)n_coh * n_dev)
    Rf_error("mat_obs must have length n_coh * n_dev.");
  if (LENGTH(last_obs_idx_sxp) != n_coh)
    Rf_error("last_obs_idx must have length n_coh.");
  if (LENGTH(k_idx_by_j_sxp) != n_dev)
    Rf_error("k_idx_by_j must have length n_dev.");
  if (LENGTH(f_hat_vec_sxp)     != n_links ||
      LENGTH(sigma2_vec_sxp)    != n_links ||
      LENGTH(link_pool_idx_sxp) != n_links)
    Rf_error("f_hat_vec / sigma2_vec / link_pool_idx must have length n_links.");
  if (n_pools < 0)
    Rf_error("pool_starts must have length >= 1.");

  double *mat_obs       = REAL(mat_obs_sxp);
  int    *last_obs_idx  = INTEGER(last_obs_idx_sxp);
  int    *link_to_idx   = INTEGER(link_to_idx_sxp);
  int    *k_idx_by_j    = INTEGER(k_idx_by_j_sxp);
  double *f_hat_vec     = REAL(f_hat_vec_sxp);
  double *sigma2_vec    = REAL(sigma2_vec_sxp);
  int    *link_pool_idx = INTEGER(link_pool_idx_sxp);
  double *pool_resid    = REAL(pool_residuals_sxp);
  int    *pool_starts   = INTEGER(pool_starts_sxp);

  R_xlen_t slab  = (R_xlen_t)n_coh * n_dev;
  R_xlen_t total = slab * B;

  SEXP cum_sxp = PROTECT(Rf_allocVector(REALSXP, total));
  SEXP dims = PROTECT(Rf_allocVector(INTSXP, 3));
  INTEGER(dims)[0] = n_coh;
  INTEGER(dims)[1] = n_dev;
  INTEGER(dims)[2] = B;
  Rf_setAttrib(cum_sxp, R_DimSymbol, dims);
  UNPROTECT(1); /* dims held via setAttrib */

  double *cum = REAL(cum_sxp);

  /* ----- (a) Init to NA_real_; copy mat_obs col 0 to cum col 0 (all b)  */
  for (R_xlen_t p = 0; p < total; p++) cum[p] = NA_REAL;
  for (int b = 0; b < B; b++) {
    R_xlen_t b_off = (R_xlen_t)b * slab;
    for (int i = 0; i < n_coh; i++) cum[b_off + i] = mat_obs[i];
  }

  /* ----- (b) Chain residual resample, per replicate, per link --------- */
  GetRNGstate();
  for (int b = 0; b < B; b++) {
    R_xlen_t b_off = (R_xlen_t)b * slab;
    for (int k = 0; k < n_links; k++) {
      int to_col_1 = link_to_idx[k];
      if (to_col_1 == NA_INTEGER || to_col_1 < 2) continue;
      int from_col = to_col_1 - 2;
      int to_col   = to_col_1 - 1;

      double f_k  = f_hat_vec[k];
      double s2_k = sigma2_vec[k];
      if (!R_FINITE(s2_k) || s2_k < 0.0) s2_k = 0.0;

      int p_size = 0;
      const double *r_pool = NULL;
      int pid = link_pool_idx[k];          /* 1-indexed; 0 == no pool */
      if (pid != NA_INTEGER && pid > 0 && pid <= n_pools) {
        int p_start = pool_starts[pid - 1];
        int p_end   = pool_starts[pid];
        p_size = p_end - p_start;
        if (p_size > 0) r_pool = &pool_resid[p_start];
      }

      R_xlen_t off_from = b_off + (R_xlen_t)from_col * n_coh;
      R_xlen_t off_to   = b_off + (R_xlen_t)to_col   * n_coh;
      R_xlen_t obs_to_base = (R_xlen_t)to_col * n_coh;

      for (int i = 0; i < n_coh; i++) {
        double obs_to   = mat_obs[obs_to_base + i];
        double prev_alt = cum[off_from + i];
        if (!R_FINITE(obs_to) || !R_FINITE(prev_alt) || prev_alt <= 0.0) continue;

        double r_star = 0.0;
        if (r_pool != NULL) {
          int idx = (int)(unif_rand() * p_size);
          if (idx >= p_size) idx = p_size - 1;
          r_star = r_pool[idx];
        }
        cum[off_to + i] = f_k * prev_alt + r_star * sqrt(s2_k * prev_alt);
      }
    }
  }
  PutRNGstate();

  /* ----- (c) Pre-refit clip: zero finite negatives -------------------- */
  for (R_xlen_t p = 0; p < total; p++) {
    if (R_FINITE(cum[p]) && cum[p] < 0.0) cum[p] = 0.0;
  }

  /* ----- (d) Refit f*_k from pseudo cumulative ----------------------- */
  double *f_star = (double *) R_alloc((size_t)n_links * B, sizeof(double));
  bootstrap_refit_fstar(cum, link_to_idx, f_hat_vec,
                        n_coh, n_dev, B, n_links, f_star);

  /* ----- (e) Forward-project + final clip ----------------------------- */
  bootstrap_fwd_proj_and_clip(cum, f_star, last_obs_idx, k_idx_by_j,
                              n_coh, n_dev, B, n_links);

  /* ----- (f) Stage 2 process noise -> cum_sampled (Mack paradigm) ----- */
  double alpha        = Rf_asReal(alpha_sxp);
  int    process_code = Rf_asInteger(process_code_sxp);

  SEXP cum_sampled_sxp = PROTECT(Rf_allocVector(REALSXP, total));
  SEXP dims_s = PROTECT(Rf_allocVector(INTSXP, 3));
  INTEGER(dims_s)[0] = n_coh;
  INTEGER(dims_s)[1] = n_dev;
  INTEGER(dims_s)[2] = B;
  Rf_setAttrib(cum_sampled_sxp, R_DimSymbol, dims_s);
  UNPROTECT(1);

  bootstrap_fwd_sim_link(cum, last_obs_idx, k_idx_by_j,
                             f_star, sigma2_vec,
                             n_coh, n_dev, B, n_links,
                             alpha, process_code,
                             REAL(cum_sampled_sxp));

  /* ----- Return list(cum_mean, cum_sampled) -------------------------- */
  SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
  SET_VECTOR_ELT(out, 0, cum_sxp);
  SET_VECTOR_ELT(out, 1, cum_sampled_sxp);
  SEXP nm = PROTECT(Rf_allocVector(STRSXP, 2));
  SET_STRING_ELT(nm, 0, Rf_mkChar("cum_mean"));
  SET_STRING_ELT(nm, 1, Rf_mkChar("cum_sampled"));
  Rf_setAttrib(out, R_NamesSymbol, nm);

  UNPROTECT(4);  /* cum_sxp, cum_sampled_sxp, out, nm */
  return out;
}


/* =============================================================================
 * Section 4 — Parametric kernel (type = "parametric")
 *
 * Three fused phases (mirrors R/bootstrap.R:1235-1267):
 *   (a) Initialize cum to mat_obs across all replicates (observed cells
 *       unchanged — parametric perturbs link factors, not data).
 *   (b) Draw f*_k ~ N(f_hat_k, sqrt(f_var_k)) per replicate, per link.
 *       Drawn only when f_var_k is finite and > 0 (else f*_k = f_hat_k).
 *   (c) Forward-project lower triangle + final clip ->
 *       bootstrap_fwd_proj_and_clip.
 *
 * RNG draw order matches R `rnorm(1, mu, sigma)` semantics: one
 * `norm_rand()` per (b, k) iff f_var_k > 0 (regardless of f_hat_k
 * finiteness — to preserve seed-deterministic RNG state).
 * =============================================================================
 */

SEXP bootstrap_kernel_parametric(
    SEXP B_sxp,
    SEXP mat_obs_sxp,             /* [n_coh × n_dev] doubles, observed cum   */
    SEXP last_obs_idx_sxp,        /* [n_coh] ints (1-indexed) or NA          */
    SEXP k_idx_by_j_sxp,          /* [n_dev] ints (1-indexed) or NA          */
    SEXP f_hat_vec_sxp,           /* [n_links] doubles                       */
    SEXP f_var_vec_sxp,           /* [n_links] doubles (Var(f_hat))          */
    SEXP sigma2_vec_sxp,          /* [n_links] doubles (Mack sigma^2)        */
    SEXP alpha_sxp,               /* scalar variance exponent                */
    SEXP process_code_sxp,        /* int: 1 gamma / 2 od_pois / 3 normal     */
    SEXP n_coh_sxp,
    SEXP n_dev_sxp) {

  int B       = Rf_asInteger(B_sxp);
  int n_coh   = Rf_asInteger(n_coh_sxp);
  int n_dev   = Rf_asInteger(n_dev_sxp);
  int n_links = LENGTH(f_hat_vec_sxp);

  if (B <= 0 || n_coh <= 0 || n_dev <= 0)
    Rf_error("B, n_coh, n_dev must all be positive.");
  if (XLENGTH(mat_obs_sxp) != (R_xlen_t)n_coh * n_dev)
    Rf_error("mat_obs must have length n_coh * n_dev.");
  if (LENGTH(last_obs_idx_sxp) != n_coh)
    Rf_error("last_obs_idx must have length n_coh.");
  if (LENGTH(k_idx_by_j_sxp) != n_dev)
    Rf_error("k_idx_by_j must have length n_dev.");
  if (LENGTH(f_var_vec_sxp)  != n_links ||
      LENGTH(sigma2_vec_sxp) != n_links)
    Rf_error("f_hat_vec, f_var_vec, sigma2_vec must have same length.");

  double *mat_obs      = REAL(mat_obs_sxp);
  int    *last_obs_idx = INTEGER(last_obs_idx_sxp);
  int    *k_idx_by_j   = INTEGER(k_idx_by_j_sxp);
  double *f_hat_vec    = REAL(f_hat_vec_sxp);
  double *f_var_vec    = REAL(f_var_vec_sxp);
  double *sigma2_vec   = REAL(sigma2_vec_sxp);

  R_xlen_t slab  = (R_xlen_t)n_coh * n_dev;
  R_xlen_t total = slab * B;

  SEXP cum_sxp = PROTECT(Rf_allocVector(REALSXP, total));
  SEXP dims = PROTECT(Rf_allocVector(INTSXP, 3));
  INTEGER(dims)[0] = n_coh;
  INTEGER(dims)[1] = n_dev;
  INTEGER(dims)[2] = B;
  Rf_setAttrib(cum_sxp, R_DimSymbol, dims);
  UNPROTECT(1); /* dims held via setAttrib */

  double *cum = REAL(cum_sxp);

  /* ----- (a) cum = mat_obs replicated across B ------------------------ */
  for (int b = 0; b < B; b++) {
    R_xlen_t b_off = (R_xlen_t)b * slab;
    memcpy(&cum[b_off], mat_obs, (size_t)slab * sizeof(double));
  }

  /* ----- (b) Draw f*_k per (replicate, link) -------------------------- */
  double *f_star = (double *) R_alloc((size_t)n_links * B, sizeof(double));
  GetRNGstate();
  for (int b = 0; b < B; b++) {
    R_xlen_t b_off = (R_xlen_t)b * n_links;
    for (int k = 0; k < n_links; k++) {
      double f_hat = f_hat_vec[k];
      double f_var = f_var_vec[k];
      if (R_FINITE(f_var) && f_var > 0.0) {
        double z = norm_rand();
        f_star[b_off + k] = R_FINITE(f_hat) ? (f_hat + sqrt(f_var) * z) : NA_REAL;
      } else {
        f_star[b_off + k] = f_hat;
      }
    }
  }
  PutRNGstate();

  /* ----- (c) Forward-project + final clip ----------------------------- */
  bootstrap_fwd_proj_and_clip(cum, f_star, last_obs_idx, k_idx_by_j,
                              n_coh, n_dev, B, n_links);

  /* ----- (d) Stage 2 process noise -> cum_sampled (Mack paradigm) ----- */
  double alpha        = Rf_asReal(alpha_sxp);
  int    process_code = Rf_asInteger(process_code_sxp);

  SEXP cum_sampled_sxp = PROTECT(Rf_allocVector(REALSXP, total));
  SEXP dims_s = PROTECT(Rf_allocVector(INTSXP, 3));
  INTEGER(dims_s)[0] = n_coh;
  INTEGER(dims_s)[1] = n_dev;
  INTEGER(dims_s)[2] = B;
  Rf_setAttrib(cum_sampled_sxp, R_DimSymbol, dims_s);
  UNPROTECT(1);

  bootstrap_fwd_sim_link(cum, last_obs_idx, k_idx_by_j,
                             f_star, sigma2_vec,
                             n_coh, n_dev, B, n_links,
                             alpha, process_code,
                             REAL(cum_sampled_sxp));

  /* ----- Return list(cum_mean, cum_sampled) -------------------------- */
  SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
  SET_VECTOR_ELT(out, 0, cum_sxp);
  SET_VECTOR_ELT(out, 1, cum_sampled_sxp);
  SEXP nm = PROTECT(Rf_allocVector(STRSXP, 2));
  SET_STRING_ELT(nm, 0, Rf_mkChar("cum_mean"));
  SET_STRING_ELT(nm, 1, Rf_mkChar("cum_sampled"));
  Rf_setAttrib(out, R_NamesSymbol, nm);

  UNPROTECT(4);
  return out;
}

/* =============================================================================
 * lossratio: bootstrap stage-2 summary kernel (paradigm-agnostic post-pass)
 *
 * This file holds the post-processing stage that consumes the (cum_mean,
 * cum_sampled) array pair produced by either the ED or the CL stage-1
 * kernel and produces per-cell Pythagorean SE decomposition
 * (param_se / proc_se / total_se / total_cv) plus optional empirical
 * percentile CI. The math is paradigm-agnostic: it cares only about the
 * shape of the two 3D arrays. The ED-specific stage-1 kernel lives in
 * src/bootstrap_ed.c; the CL-specific stage-1 kernels live in
 * src/bootstrap_cl.c.
 *
 * R <-> C contract (shared across all three files)
 * ------------------------------------------------
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
#include <math.h>    /* sqrt */
#include <stdlib.h>  /* qsort */


/* Ascending comparator for qsort of doubles. */
static int cmp_dbl_asc(const void *a, const void *b) {
  double da = *(const double *)a, db = *(const double *)b;
  return (da > db) - (da < db);
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

/* bootstrap_summary_kernel
 *
 *   R-callable entry that takes the two cumulative arrays (column-major
 *   length n_coh x n_dev x B) and returns a named list of five (or seven)
 *   flat length n_coh x n_dev REALSXPs: mean_proj, param_se, proc_se,
 *   total_se, total_cv -- plus ci_lo, ci_hi when `quantile_ci_sxp` is
 *   TRUE. Wraps the file-local bootstrap_summary_decompose helper so
 *   R-side .boot_summary_from_arrays() can produce the $summary slot
 *   in C -- bypassing data.table's R-level
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

/* bootstrap_cell_kernel
 *
 *   Native kernel for the cell-residual bootstrap stage 1. Replaces what
 *   was previously a chain of R-level vectorised steps with a single
 *   self-contained C pass that, given the precomputed pieces (active
 *   cells, residual pool, anchor factors), produces the [n_coh, n_dev, B]
 *   cumulative-loss array for all B replicates.
 *
 *   The kernel runs five fused phases:
 *
 *     (a) Resample residuals + place pseudo incrementals.
 *         For each replicate b and active cell a, draw one residual from
 *         the pool that cell belongs to (uniform with replacement, using
 *         R's RNG via unif_rand()) and write the pseudo incremental
 *         mu[a] + r * sqrt(|mu[a]|) into cum[active_lin[a], b].
 *
 *     (b) Cumulative sum along the dev axis (per cohort × replicate).
 *
 *     (c) Mask cells outside each cohort's upper-triangle observation
 *         region to NA_real_. Using last_obs_idx[i]: any dev j with
 *         j > last_obs_idx[i] is set to NA across all B replicates.
 *
 *     (d) Volume-weighted refit of f*_k per link, per replicate, using
 *         only cohorts where both the from- and to-cell are finite.
 *         When the denominator sum is non-positive the factor falls
 *         back to f_hat_vec[k].
 *
 *     (e) Forward-project lower-triangle cells dev by dev. For each
 *         dev j (2..n_dev), cohorts with last_obs_idx < j receive
 *         cum[i, j, b] = f*[k, b] * cum[i, j-1, b] where k is the link
 *         whose ata_to lands at j (k_idx_by_j). When the mapping is NA,
 *         the previous column is carried forward.
 *
 *     (f) Clip finite negative cumulatives to 0.
 *
 *   Pool layout (CSR-like):
 *     - pool_residuals: concatenated residuals from every pool.
 *     - pool_starts:    length n_pools + 1; pool p occupies
 *                       pool_residuals[pool_starts[p-1] : pool_starts[p]-1]
 *                       (1-indexed pool ids match R-level).
 *     - cell_pool_idx:  1-indexed pool id per active cell, or 0 to
 *                       indicate "no pool" (residual draws fall back to
 *                       zero, i.e. the cell stays at its fitted value).
 */
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <string.h>  /* memset */

static SEXP bootstrap_cell_kernel(
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
  UNPROTECT(1); /* dims now held via setAttrib */

  double *cum = REAL(cum_sxp);
  memset(cum, 0, (size_t)total * sizeof(double));

  /* ===== (a) Resample residuals + place increments ==================== */
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
          if (idx >= psz) idx = psz - 1;    /* ceiling-edge safety */
          r_star = pool_resid[start + idx];
        }
      }
      cum[b_off + active_lin[a] - 1] = mu + r_star * sqrt_active[a];
    }
  }
  PutRNGstate();

  /* ===== (b) Cumsum along dev (per cohort × replicate) ================ */
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

  /* ===== (c) Mask cells outside upper triangle to NA ================== */
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

  /* ===== (d) Refit f*_k per link, per replicate ======================= */
  double *f_star = (double *) R_alloc((size_t)n_links * B, sizeof(double));
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

  /* ===== (e) Forward-project lower-triangle cells ==================== */
  for (int j = 1; j < n_dev; j++) {
    int k_idx_1 = k_idx_by_j[j];
    int k_idx   = (k_idx_1 == NA_INTEGER) ? -1 : (k_idx_1 - 1);
    R_xlen_t off_curr_base = (R_xlen_t)j       * n_coh;
    R_xlen_t off_prev_base = (R_xlen_t)(j - 1) * n_coh;
    for (int i = 0; i < n_coh; i++) {
      int lj = last_obs_idx[i];
      if (lj == NA_INTEGER) continue;
      if (lj >= j + 1) continue;             /* upper triangle: keep */
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

  /* ===== (f) Clip finite negatives to 0 =============================== */
  for (R_xlen_t p = 0; p < total; p++) {
    if (R_FINITE(cum[p]) && cum[p] < 0.0) cum[p] = 0.0;
  }

  UNPROTECT(1);
  return cum_sxp;
}

static const R_CallMethodDef CallEntries[] = {
  {"C_bootstrap_cell_kernel", (DL_FUNC) &bootstrap_cell_kernel, 13},
  {NULL, NULL, 0}
};

void R_init_lossratio(DllInfo *dll) {
  R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
}

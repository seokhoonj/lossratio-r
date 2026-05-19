/* =============================================================================
 * lossratio: bootstrap stage-1 native kernel -- SA (stage-adaptive) paradigm
 *
 * This file holds the SA-paradigm cell bootstrap, which composes the ED and
 * CL paradigms with a per-cohort stage transition at the maturity point
 * `mat_k`. Math (per cohort i, per dev j, per replicate b):
 *
 *   Stage 1 (cell perturbation):
 *     For each active cell a, mu_active[a] and sqrt_active[a] are PRE-COMPUTED
 *     in R using the paradigm appropriate for that cell:
 *       - ED stage (from-dev < mat_k[i]):
 *           mu        = g_k * exposure_from
 *           sqrt_term = sqrt(|mu|)
 *           r_star drawn from the ED Pearson pool (pool_id prefixed "ed|...")
 *       - CL stage (from-dev >= mat_k[i]):
 *           mu        = f_k * C_{i, from}
 *           sqrt_term = sqrt(f_sigma2_k * |C_{i, from}|)
 *           r_star drawn from the CL Pearson pool (pool_id prefixed "cl|...")
 *     The active-cell loop (a) is paradigm-agnostic at the C level: the R
 *     side selects the right pool bucket per cell via cell_pool_idx[a].
 *     C kernel just resamples: cum[lin] = mu + r_star * sqrt_term.
 *
 *   Stage 1 (refit): BOTH f_star and g_star are refit per replicate from
 *     the perturbed cumulative array, even though only one is used per
 *     cohort at any given dev -- they're cheap and uniform across cohorts.
 *
 *   Stage 1 (forward projection):
 *     for j = first_proj .. n_dev-1:
 *       for i with last_obs_idx[i] < j+1 (cohort needs projection at dev j):
 *         k = k_idx_by_j[j] - 1  (link from -> to)
 *         v_prev = cum[i, j-1, b]
 *         stage_cl = (j >= mat_k_vec[i])
 *           -- j is 0-indexed to-dev; mat_k_vec stores 1-indexed from-dev;
 *              CL when from_dev_1based >= mat_k (see bootstrap_sa_stage_cl_for_to_dev)
 *         cum[i, j, b] = stage_cl ? f_star[k, b] * v_prev
 *                                : v_prev + g_star[k, b] * exposure_proj[i, j-1]
 *
 *   Stage 2 (process noise on the lower triangle):
 *     For each cohort, walking forward from last_obs_idx[i]:
 *       inc_mean = cum_mean[i, j, b] - cum_mean[i, j-1, b]    (paradigm-read)
 *       phi_use  = stage_cl ? phi_cl : phi_ed                  (per-cell)
 *       inc_sampled ~ ProcessDist(inc_mean, var = phi_use * |inc_mean|^alpha)
 *       cum_sampled[i, j, b] = cum_sampled[i, j-1, b] + inc_sampled
 *
 * Exposure (`exposure_proj`) is CL-projected once in R (same as the ED-only
 * kernel) and stays fixed across all B replicates in Phase 1.
 *
 * `mat_k_vec[i]` is the 1-indexed from-dev at which CL begins for cohort i:
 *   - mat_k_vec[i] == NA_INTEGER or INT_MAX  -> all-ED (no CL stage)
 *   - mat_k_vec[i] == k means: links with from_dev = 1..(k-1) are ED,
 *     links with from_dev = k.. are CL. In 0-indexed C with j = 0-indexed
 *     to-dev, the from_dev_1based is j (since to-dev = from-dev + 1, both
 *     1-indexed gives to_1 = j+1, from_1 = j). So stage_cl iff j >= mat_k.
 *
 * Helpers re-use the file-local statics from bootstrap_cl.c and bootstrap_ed.c
 * (bootstrap_refit_cl_fstar / bootstrap_refit_ed_gstar). Those are file-static
 * for binary-size hygiene, so this file duplicates the helper code rather
 * than introducing a cross-file header dependency. See file headers for math.
 * =============================================================================
 */
#include "lossratio.h"
#include <math.h>     /* sqrt, pow, fabs */
#include <string.h>   /* memset, memcpy */
#include <limits.h>   /* INT_MAX */
#include <Rmath.h>    /* Rf_rgamma */


/* bootstrap_sa_refit_fstar
 *
 *   File-local mirror of bootstrap_refit_cl_fstar (src/bootstrap_cl.c). The
 *   SA kernel refits BOTH f_star (CL anchor) and g_star (ED anchor) every
 *   replicate, even though each cohort uses only one per dev. The cost is
 *   negligible (n_links * B doubles each) and keeps the projection branch
 *   trivial. See bootstrap_cl.c for the math.
 */
static void bootstrap_sa_refit_fstar(
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


/* bootstrap_sa_refit_gstar
 *
 *   File-local mirror of bootstrap_refit_ed_gstar (src/bootstrap_ed.c).
 *   See that file for the math.
 */
static void bootstrap_sa_refit_gstar(
    const double *cum,
    const double *exposure_proj,
    const int *link_to_idx,
    const double *g_hat_vec,
    int n_coh, int n_dev, int B, int n_links,
    double *g_star) {

  R_xlen_t slab = (R_xlen_t)n_coh * n_dev;
  for (int k = 0; k < n_links; k++) {
    int to_col_1 = link_to_idx[k];
    int fallback = !(to_col_1 != NA_INTEGER && to_col_1 >= 2);
    if (fallback) {
      for (int b = 0; b < B; b++)
        g_star[k + (R_xlen_t)b * n_links] = g_hat_vec[k];
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
        double p_v    = exposure_proj[off_from_base + i];
        if (R_FINITE(from_v) && R_FINITE(to_v) &&
            R_FINITE(p_v) && p_v > 0.0) {
          num += (to_v - from_v);
          den += p_v;
        }
      }
      g_star[k + (R_xlen_t)b * n_links] =
        (R_FINITE(den) && den > 0.0) ? (num / den) : g_hat_vec[k];
    }
  }
}


/* bootstrap_sa_stage_cl_for_to_dev
 *
 *   Given 0-indexed to-dev `j` and per-cohort 1-indexed CL-start
 *   `mat_k_vec[i]`, returns 1 iff the link from -> to is in the CL stage.
 *
 *   Mapping notes:
 *     - j (0-indexed to-dev)  corresponds to to_dev_1based = j + 1
 *     - to_dev_1based = from_dev_1based + 1, so from_dev_1based = j
 *     - mat_k_vec stores the 1-indexed from-dev at which CL begins
 *     - stage_cl iff from_dev_1based >= mat_k_vec[i]  <==>  j >= mat_k_vec[i]
 *     - NA_INTEGER or INT_MAX -> all-ED (returns 0 always)
 */
static inline int bootstrap_sa_stage_cl_for_to_dev(int j, int mat_k_1) {
  if (mat_k_1 == NA_INTEGER) return 0;
  if (mat_k_1 == INT_MAX)    return 0;
  return (j >= mat_k_1) ? 1 : 0;
}


/* bootstrap_sa_fwd_proj_and_clip
 *
 *   SA-paradigm forward projection. Walks j = 1..n_dev-1; for each cohort
 *   needing projection at dev j, applies the paradigm-appropriate step
 *   using the per-cohort stage from `mat_k_vec`. Clips finite negatives to
 *   0 at the end (same convention as CL / ED projectors).
 */
static void bootstrap_sa_fwd_proj_and_clip(
    double *cum,
    const double *f_star,
    const double *g_star,
    const double *exposure_proj,
    const int *last_obs_idx,
    const int *k_idx_by_j,
    const int *mat_k_vec,
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
      if (lj >= j + 1) continue;             /* upper triangle: keep */

      int stage_cl = bootstrap_sa_stage_cl_for_to_dev(j, mat_k_vec[i]);
      double p_prev = exposure_proj[off_prev_base + i];

      for (int b = 0; b < B; b++) {
        R_xlen_t b_off = (R_xlen_t)b * slab;
        double base = cum[off_prev_base + b_off + i];
        if (k_idx < 0) {
          cum[off_curr_base + b_off + i] = base;
          continue;
        }
        if (stage_cl) {
          double f_b = f_star[k_idx + (R_xlen_t)b * n_links];
          if (!R_FINITE(f_b)) f_b = 1.0;
          cum[off_curr_base + b_off + i] = f_b * base;
        } else {
          double g_b = g_star[k_idx + (R_xlen_t)b * n_links];
          if (!R_FINITE(g_b)) g_b = 0.0;
          double inc = R_FINITE(p_prev) ? (g_b * p_prev) : 0.0;
          cum[off_curr_base + b_off + i] = base + inc;
        }
      }
    }
  }

  R_xlen_t total = slab * B;
  for (R_xlen_t p = 0; p < total; p++) {
    if (R_FINITE(cum[p]) && cum[p] < 0.0) cum[p] = 0.0;
  }
}


/* bootstrap_sa_fwd_sim_cell
 *
 *   SA-paradigm Stage 2 process noise. Per cohort i, walking dev forward
 *   from last_obs_idx[i]; cell paradigm decided by `mat_k_vec[i]` vs `j`.
 *   `phi_use` is selected per-cell (ED -> phi_ed, CL -> phi_cl). The
 *   per-step ProcessDist switch mirrors the CL/ED cell kernels.
 *
 *   When phi_use is non-finite or non-positive, that cell falls back to
 *   the deterministic mean increment (no noise). When inc_mean <= 0 or
 *   non-finite, the cell also falls back to deterministic propagation.
 */
static void bootstrap_sa_fwd_sim_cell(
    const double *cum_mean,
    const int *last_obs_idx,
    const int *mat_k_vec,
    int n_coh, int n_dev, int B,
    double phi_ed, double phi_cl, double alpha,
    int process_code,
    double *cum_sampled) {

  R_xlen_t slab  = (R_xlen_t)n_coh * n_dev;
  R_xlen_t total = slab * B;

  /* Initialize cum_sampled = cum_mean (upper triangle kept, lower
   * triangle overwritten below). */
  memcpy(cum_sampled, cum_mean, (size_t)total * sizeof(double));

  GetRNGstate();
  for (int b = 0; b < B; b++) {
    R_xlen_t b_off = (R_xlen_t)b * slab;
    for (int i = 0; i < n_coh; i++) {
      int lj = last_obs_idx[i];                  /* 1-indexed */
      if (lj == NA_INTEGER) continue;
      if (lj >= n_dev) continue;                 /* fully observed */

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

        int stage_cl = bootstrap_sa_stage_cl_for_to_dev(j, mat_k_vec[i]);
        double phi_use = stage_cl ? phi_cl : phi_ed;

        double inc_mean = cum_curr - cum_prev;
        double inc_sampled;
        if (R_FINITE(phi_use) && phi_use > 0.0 &&
            R_FINITE(inc_mean) && inc_mean > 0.0) {
          switch (process_code) {
            case 1:   /* gamma */
            case 2: { /* od_pois (Gamma moment-matched) */
              double shape = inc_mean / phi_use;
              double scale = phi_use;
              inc_sampled = Rf_rgamma(shape, scale);
              break;
            }
            case 3: { /* normal */
              double sd = sqrt(phi_use * pow(fabs(inc_mean), alpha));
              inc_sampled = inc_mean + norm_rand() * sd;
              break;
            }
            default:
              inc_sampled = inc_mean;
          }
        } else {
          inc_sampled = inc_mean;  /* deterministic fallback */
        }
        cum_sampled[off_curr] = prev_sampled + inc_sampled;
        prev_sampled = cum_sampled[off_curr];
      }
    }
  }
  PutRNGstate();
}


/* bootstrap_kernel_sa_cell
 *
 *   Main SA-paradigm cell kernel. Same six-phase structure as the CL / ED
 *   siblings:
 *     (a) Resample residuals + place pseudo incrementals -- IDENTICAL to
 *         CL / ED at the C level. `mu_active`, `sqrt_active`,
 *         `cell_pool_idx` are PRE-COMPUTED in R using paradigm-appropriate
 *         formulas per cell, so the C kernel just draws and places.
 *     (b) Cumsum along the dev axis (identical to CL / ED).
 *     (c) Mask lower triangle to NA (identical to CL / ED).
 *     (d) Refit BOTH f*_k AND g*_k per link  -> bootstrap_sa_refit_fstar +
 *         bootstrap_sa_refit_gstar. Both are needed because per-cohort stage
 *         differs.
 *     (e) Forward-project with per-cohort stage switch + clip
 *         -> bootstrap_sa_fwd_proj_and_clip.
 *     (f) Stage 2 process noise with per-cohort, per-dev paradigm switch
 *         -> bootstrap_sa_fwd_sim_cell.
 *
 *   `mat_k_vec[i]`: per-cohort 1-indexed from-dev at which CL begins.
 *   NA_INTEGER or INT_MAX => cohort stays ED forever (mirror `.sa_proj`
 *   silent fallback when `maturity_from` is NA).
 *
 *   `phi_ed` and `phi_cl`: paradigm-specific Stage-2 dispersion scalars.
 *   Each cell at Stage 2 uses the phi matching its stage.
 */
SEXP bootstrap_kernel_sa_cell(
    SEXP B_sxp,
    SEXP mu_active_sxp,
    SEXP sqrt_active_sxp,
    SEXP active_lin_sxp,
    SEXP cell_pool_idx_sxp,
    SEXP pool_residuals_sxp,
    SEXP pool_starts_sxp,
    SEXP last_obs_idx_sxp,
    SEXP link_to_idx_sxp,
    SEXP k_idx_by_j_sxp,
    SEXP f_hat_vec_sxp,
    SEXP g_hat_vec_sxp,
    SEXP exposure_proj_sxp,
    SEXP mat_k_vec_sxp,
    SEXP phi_ed_sxp,
    SEXP phi_cl_sxp,
    SEXP alpha_sxp,
    SEXP process_code_sxp,
    SEXP n_coh_sxp,
    SEXP n_dev_sxp) {

  int B        = Rf_asInteger(B_sxp);
  int n_coh    = Rf_asInteger(n_coh_sxp);
  int n_dev    = Rf_asInteger(n_dev_sxp);
  int n_active = LENGTH(active_lin_sxp);
  int n_links  = LENGTH(link_to_idx_sxp);
  int n_pools  = LENGTH(pool_starts_sxp) - 1;

  if (B <= 0 || n_coh <= 0 || n_dev <= 0)
    Rf_error("B, n_coh, n_dev must all be positive.");
  if (LENGTH(mu_active_sxp)     != n_active ||
      LENGTH(sqrt_active_sxp)   != n_active ||
      LENGTH(cell_pool_idx_sxp) != n_active)
    Rf_error("mu_active / sqrt_active / cell_pool_idx must each have length n_active.");
  if (LENGTH(last_obs_idx_sxp) != n_coh)
    Rf_error("last_obs_idx must have length n_coh.");
  if (LENGTH(mat_k_vec_sxp) != n_coh)
    Rf_error("mat_k_vec must have length n_coh.");
  if (LENGTH(k_idx_by_j_sxp) != n_dev)
    Rf_error("k_idx_by_j must have length n_dev.");
  if (LENGTH(f_hat_vec_sxp) != n_links)
    Rf_error("f_hat_vec must have length n_links.");
  if (LENGTH(g_hat_vec_sxp) != n_links)
    Rf_error("g_hat_vec must have length n_links.");
  if (XLENGTH(exposure_proj_sxp) != (R_xlen_t)n_coh * n_dev)
    Rf_error("exposure_proj must have length n_coh * n_dev.");
  if (n_pools < 0)
    Rf_error("pool_starts must have length >= 1.");

  double *mu_active     = REAL(mu_active_sxp);
  double *sqrt_active   = REAL(sqrt_active_sxp);
  int *active_lin       = INTEGER(active_lin_sxp);
  int *cell_pool_idx    = INTEGER(cell_pool_idx_sxp);
  double *pool_resid    = REAL(pool_residuals_sxp);
  int *pool_starts      = INTEGER(pool_starts_sxp);
  int *last_obs_idx     = INTEGER(last_obs_idx_sxp);
  int *link_to_idx      = INTEGER(link_to_idx_sxp);
  int *k_idx_by_j       = INTEGER(k_idx_by_j_sxp);
  double *f_hat_vec     = REAL(f_hat_vec_sxp);
  double *g_hat_vec     = REAL(g_hat_vec_sxp);
  double *exposure_proj = REAL(exposure_proj_sxp);
  int *mat_k_vec        = INTEGER(mat_k_vec_sxp);

  R_xlen_t slab  = (R_xlen_t)n_coh * n_dev;
  R_xlen_t total = slab * B;

  /* Allocate cum_mean output [n_coh, n_dev, B]. */
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
      int pid = cell_pool_idx[a];                /* 1-indexed; 0 == no pool */
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

  /* ----- (b) Cumsum along dev (per cohort x replicate) --------------- */
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

  /* ----- (d) Refit BOTH f*_k AND g*_k from pseudo cumulative --------- */
  double *f_star = (double *) R_alloc((size_t)n_links * B, sizeof(double));
  double *g_star = (double *) R_alloc((size_t)n_links * B, sizeof(double));
  bootstrap_sa_refit_fstar(cum, link_to_idx, f_hat_vec,
                    n_coh, n_dev, B, n_links, f_star);
  bootstrap_sa_refit_gstar(cum, exposure_proj, link_to_idx, g_hat_vec,
                    n_coh, n_dev, B, n_links, g_star);

  /* ----- (e) Forward-project with per-cohort stage switch + clip ----- */
  bootstrap_sa_fwd_proj_and_clip(cum, f_star, g_star, exposure_proj,
                       last_obs_idx, k_idx_by_j, mat_k_vec,
                       n_coh, n_dev, B, n_links);

  /* ----- (f) Stage 2 process noise -> cum_sampled -------------------- */
  double phi_ed       = Rf_asReal(phi_ed_sxp);
  double phi_cl       = Rf_asReal(phi_cl_sxp);
  double alpha        = Rf_asReal(alpha_sxp);
  int    process_code = Rf_asInteger(process_code_sxp);

  SEXP cum_sampled_sxp = PROTECT(Rf_allocVector(REALSXP, total));
  SEXP dims_s = PROTECT(Rf_allocVector(INTSXP, 3));
  INTEGER(dims_s)[0] = n_coh;
  INTEGER(dims_s)[1] = n_dev;
  INTEGER(dims_s)[2] = B;
  Rf_setAttrib(cum_sampled_sxp, R_DimSymbol, dims_s);
  UNPROTECT(1);

  bootstrap_sa_fwd_sim_cell(cum, last_obs_idx, mat_k_vec,
                  n_coh, n_dev, B,
                  phi_ed, phi_cl, alpha, process_code,
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


/* bootstrap_kernel_sa_param -- SA textbook parametric kernel
 * (type = "parametric", method = "sa")
 *
 * Phase (a) differs from bootstrap_kernel_sa_cell: each active cell value
 * is drawn directly from ProcessDist(mu_active[a], phi_active[a]) where
 * phi_active is per-cell (phi_ed for ED cells, phi_cl for CL cells; the R
 * side builds this via fifelse on the cell paradigm classification).
 * Phases (b)-(f) mirror the SA cell kernel exactly (cumsum -> mask ->
 * refit f* + g* -> per-cohort stage-switch projection -> Stage 2 noise
 * via bootstrap_sa_fwd_sim_cell with scalar phi_ed / phi_cl on a per-cohort stage
 * basis).
 */
SEXP bootstrap_kernel_sa_param(
    SEXP B_sxp,
    SEXP mu_active_sxp,
    SEXP active_lin_sxp,
    SEXP last_obs_idx_sxp,
    SEXP link_to_idx_sxp,
    SEXP k_idx_by_j_sxp,
    SEXP f_hat_vec_sxp,
    SEXP g_hat_vec_sxp,
    SEXP exposure_proj_sxp,
    SEXP mat_k_vec_sxp,
    SEXP phi_active_sxp,
    SEXP phi_ed_sxp,
    SEXP phi_cl_sxp,
    SEXP alpha_sxp,
    SEXP process_code_sxp,
    SEXP n_coh_sxp,
    SEXP n_dev_sxp) {

  int B        = Rf_asInteger(B_sxp);
  int n_coh    = Rf_asInteger(n_coh_sxp);
  int n_dev    = Rf_asInteger(n_dev_sxp);
  int n_active = LENGTH(active_lin_sxp);
  int n_links  = LENGTH(link_to_idx_sxp);

  if (B <= 0 || n_coh <= 0 || n_dev <= 0)
    Rf_error("B, n_coh, n_dev must all be positive.");
  if (LENGTH(mu_active_sxp)  != n_active ||
      LENGTH(phi_active_sxp) != n_active)
    Rf_error("mu_active / phi_active must each have length n_active.");
  if (LENGTH(last_obs_idx_sxp) != n_coh)
    Rf_error("last_obs_idx must have length n_coh.");
  if (LENGTH(mat_k_vec_sxp) != n_coh)
    Rf_error("mat_k_vec must have length n_coh.");
  if (LENGTH(k_idx_by_j_sxp) != n_dev)
    Rf_error("k_idx_by_j must have length n_dev.");
  if (LENGTH(f_hat_vec_sxp) != n_links)
    Rf_error("f_hat_vec must have length n_links.");
  if (LENGTH(g_hat_vec_sxp) != n_links)
    Rf_error("g_hat_vec must have length n_links.");
  if (XLENGTH(exposure_proj_sxp) != (R_xlen_t)n_coh * n_dev)
    Rf_error("exposure_proj must have length n_coh * n_dev.");

  double *mu_active     = REAL(mu_active_sxp);
  double *phi_active    = REAL(phi_active_sxp);
  int *active_lin       = INTEGER(active_lin_sxp);
  int *last_obs_idx     = INTEGER(last_obs_idx_sxp);
  int *link_to_idx      = INTEGER(link_to_idx_sxp);
  int *k_idx_by_j       = INTEGER(k_idx_by_j_sxp);
  double *f_hat_vec     = REAL(f_hat_vec_sxp);
  double *g_hat_vec     = REAL(g_hat_vec_sxp);
  double *exposure_proj = REAL(exposure_proj_sxp);
  int *mat_k_vec        = INTEGER(mat_k_vec_sxp);

  double phi_ed       = Rf_asReal(phi_ed_sxp);
  double phi_cl       = Rf_asReal(phi_cl_sxp);
  double alpha        = Rf_asReal(alpha_sxp);
  int    process_code = Rf_asInteger(process_code_sxp);

  R_xlen_t slab  = (R_xlen_t)n_coh * n_dev;
  R_xlen_t total = slab * B;

  /* Allocate cum_mean output [n_coh, n_dev, B]. */
  SEXP cum_sxp = PROTECT(Rf_allocVector(REALSXP, total));
  SEXP dims = PROTECT(Rf_allocVector(INTSXP, 3));
  INTEGER(dims)[0] = n_coh;
  INTEGER(dims)[1] = n_dev;
  INTEGER(dims)[2] = B;
  Rf_setAttrib(cum_sxp, R_DimSymbol, dims);
  UNPROTECT(1); /* dims held via setAttrib */

  double *cum = REAL(cum_sxp);
  memset(cum, 0, (size_t)total * sizeof(double));

  /* ----- (a) Parametric draw on each active cell (per-cell phi) ----- */
  GetRNGstate();
  for (int b = 0; b < B; b++) {
    R_xlen_t b_off = (R_xlen_t)b * slab;
    for (int a = 0; a < n_active; a++) {
      double mu      = mu_active[a];
      double phi_use = phi_active[a];
      R_xlen_t off   = b_off + active_lin[a] - 1;
      if (!R_FINITE(mu)) {
        cum[off] = mu;
        continue;
      }
      double draw;
      switch (process_code) {
        case 1:   /* gamma */
        case 2: { /* od_pois */
          if (mu <= 0.0 || !R_FINITE(phi_use) || phi_use <= 0.0) {
            draw = mu;
          } else {
            double shape = mu / phi_use;
            double scale = phi_use;
            draw = Rf_rgamma(shape, scale);
          }
          break;
        }
        case 3: { /* normal */
          if (!R_FINITE(phi_use) || phi_use <= 0.0) {
            draw = mu;
          } else {
            double sd = sqrt(phi_use * pow(fabs(mu), alpha));
            double x_star = mu + norm_rand() * sd;
            draw = (x_star < 0.0) ? 0.0 : x_star;
          }
          break;
        }
        default:
          draw = mu;
      }
      cum[off] = draw;
    }
  }
  PutRNGstate();

  /* ----- (b) Cumsum along dev (per cohort x replicate) --------------- */
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

  /* ----- (d) Refit BOTH f*_k AND g*_k from pseudo cumulative --------- */
  double *f_star = (double *) R_alloc((size_t)n_links * B, sizeof(double));
  double *g_star = (double *) R_alloc((size_t)n_links * B, sizeof(double));
  bootstrap_sa_refit_fstar(cum, link_to_idx, f_hat_vec,
                    n_coh, n_dev, B, n_links, f_star);
  bootstrap_sa_refit_gstar(cum, exposure_proj, link_to_idx, g_hat_vec,
                    n_coh, n_dev, B, n_links, g_star);

  /* ----- (e) Forward-project with per-cohort stage switch + clip ----- */
  bootstrap_sa_fwd_proj_and_clip(cum, f_star, g_star, exposure_proj,
                       last_obs_idx, k_idx_by_j, mat_k_vec,
                       n_coh, n_dev, B, n_links);

  /* ----- (f) Stage 2 process noise -> cum_sampled -------------------- */
  SEXP cum_sampled_sxp = PROTECT(Rf_allocVector(REALSXP, total));
  SEXP dims_s = PROTECT(Rf_allocVector(INTSXP, 3));
  INTEGER(dims_s)[0] = n_coh;
  INTEGER(dims_s)[1] = n_dev;
  INTEGER(dims_s)[2] = B;
  Rf_setAttrib(cum_sampled_sxp, R_DimSymbol, dims_s);
  UNPROTECT(1);

  bootstrap_sa_fwd_sim_cell(cum, last_obs_idx, mat_k_vec,
                  n_coh, n_dev, B,
                  phi_ed, phi_cl, alpha, process_code,
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

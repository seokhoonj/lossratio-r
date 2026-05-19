/* =============================================================================
 * lossratio: bootstrap stage-1 native kernels -- ED paradigm
 *
 * This file holds the ED (exposure-driven) paradigm bootstrap, which uses
 * the additive recursion `Delta loss = g_k * exposure + noise` instead of
 * the multiplicative chain ladder. The CL-paradigm sibling lives in
 * src/bootstrap_cl.c; shared SE-decomposition helpers live in
 * src/bootstrap_common.c. See the latter for the full R <-> C contract.
 *
 * ED-paradigm cell-residual kernel (Phase 1, fixed exposure)
 *
 * ED bootstrap mirrors the CL cell kernel six-phase structure but uses the
 * exposure-driven additive recursion instead of the multiplicative chain
 * ladder. Math (per cell, per replicate b):
 *
 *   Stage 1:
 *     mu_{ik}        = g_k * P_{i,k-1}                    (pre-computed in R)
 *     loss_alt_{ik}  = mu_{ik} + r* * sqrt(|mu_{ik}|)     (Pearson-style resample)
 *     cum[b]         = cumsum along dev (per cohort)
 *     g*_k,b         = sum_i (cum[i, to, b] - cum[i, from, b]) / sum_i P_{i, from}
 *     cum[i, j, b]   = cum[i, j-1, b] + g*_k,b * P[i, j-1]   for j > last_obs_idx[i]
 *
 *   Stage 2:
 *     inc_mean       = g*_k,b * P[i, j-1]
 *     inc_sampled    = ProcessDist(inc_mean, var = phi * |inc_mean|^alpha)
 *     cum_sampled[i, j, b] = cum_sampled[i, j-1, b] + inc_sampled
 *
 * P (exposure) is projected once (via CL on the exposure column) in R and
 * passed in as `exposure_proj` [n_coh, n_dev]; it stays fixed across all B
 * replicates (Phase 1 assumption). Phase 2/3 will release fixed-exposure
 * by jointly bootstrapping the exposure column.
 *
 * Helpers parallel the CL kernel triple:
 *   bootstrap_refit_ed_gstar         <-> bootstrap_refit_cl_fstar
 *   bootstrap_fwd_proj_ed_and_clip <-> bootstrap_fwd_proj_cl_and_clip
 *   bootstrap_fwd_sim_ed_cell      <-> bootstrap_fwd_sim_cl_cell
 *
 * Stage 1 phases (a)-(c) are identical to the CL kernel because
 * `mu` and `sqrt(|mu|)` are pre-computed in R: the CL kernel reads
 * `mu = f_k * C_{i, from}` while the ED kernel reads `mu = g_k * P_{i, from}`,
 * but downstream the placement / cumsum / mask logic is the same.
 * =============================================================================
 */
#include "lossratio.h"
#include <math.h>    /* sqrt, pow, fabs */
#include <string.h>  /* memset, memcpy */
#include <Rmath.h>   /* Rf_rgamma */


/* bootstrap_refit_ed_gstar
 *
 *   Refit g*_k per link, per replicate, from the already-built pseudo
 *   cumulative array `cum` [n_coh, n_dev, B] (cell-mode upper triangle has
 *   absorbed the residual draw and been cumsummed; the lower triangle is
 *   masked NA). Math:
 *
 *     g*_k,b = sum_i (cum[i, to, b] - cum[i, from, b]) / sum_i exposure_proj[i, from]
 *
 *   where `from` = to - 1 (dev pairs). Cells where either cum endpoint is
 *   non-finite are skipped (NA mask convention from caller). When the
 *   denominator sum is non-positive the factor falls back to
 *   `g_hat_vec[k]` (the anchor intensity from the original data).
 *
 *   `exposure_proj` stays fixed across replicates (Phase 1 assumption);
 *   only the cumulative loss array `cum` varies with b.
 */
static void bootstrap_refit_ed_gstar(
    const double *cum,
    const double *exposure_proj,    /* [n_coh * n_dev] column-major */
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
    /* g_star coverage must match analytical g_hat: only cohorts with
     * observed (finite) cum at both `from` and `to` contribute to the
     * numerator, and the denominator sums P[i, from] over the SAME cohort
     * set. The earlier optimisation summed exposure_proj over all finite
     * cohorts -- but exposure_proj is CL-extended to every cell, so that
     * sum included cohorts whose loss is not yet observed at this link,
     * inflating the denominator and systematically depressing g_star
     * (agent #21 finding, 23-37% under-projection on 4 cv synthetic). */
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


/* bootstrap_fwd_proj_ed_and_clip
 *
 *   Additive ED forward projection: fill lower-triangle cells of `cum`
 *   [n_coh, n_dev, B] dev by dev. For each dev j (2..n_dev), cohorts with
 *   last_obs_idx[i] < j receive
 *       cum[i, j, b] = cum[i, j-1, b] + g*_k,b * exposure_proj[i, j-1]
 *   where k = k_idx_by_j[j] (1-indexed; NA -> carry forward unchanged).
 *
 *   Clips finite negatives to 0 in a final pass — same convention as the
 *   CL projector.
 */
static void bootstrap_fwd_proj_ed_and_clip(
    double *cum, const double *g_star,
    const double *exposure_proj,
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
      double p_prev = exposure_proj[off_prev_base + i];
      for (int b = 0; b < B; b++) {
        R_xlen_t b_off = (R_xlen_t)b * slab;
        double base = cum[off_prev_base + b_off + i];
        if (k_idx < 0) {
          cum[off_curr_base + b_off + i] = base;
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


/* bootstrap_fwd_sim_ed_cell
 *
 *   ED additive Stage-2 process noise. Mirror of bootstrap_fwd_sim_cl_cell
 *   but the per-step mean comes from the additive recursion:
 *
 *     inc_mean    = g*_k,b * P[i, j-1]
 *     inc_sampled = ProcessDist(inc_mean, var = phi * |inc_mean|^alpha)
 *     cum_sampled[i, j, b] = cum_sampled[i, j-1, b] + inc_sampled
 *
 *   Upper triangle copied from cum_mean unchanged (Stage 1 already absorbs
 *   noise there). Same process_code switch (1 gamma / 2 od_pois / 3 normal)
 *   and same deterministic fallback for non-positive inc_mean.
 */
static void bootstrap_fwd_sim_ed_cell(
    const double *cum_mean,
    const double *g_star,           /* [n_links * B] */
    const double *exposure_proj,
    const int *last_obs_idx,
    const int *k_idx_by_j,
    int n_coh, int n_dev, int B, int n_links,
    double phi, double alpha,
    int process_code,
    double *cum_sampled) {

  R_xlen_t slab  = (R_xlen_t)n_coh * n_dev;
  R_xlen_t total = slab * B;

  /* Initialize cum_sampled = cum_mean -- upper triangle stays unchanged,
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

      double prev_sampled = cum_sampled[b_off + (R_xlen_t)(lj - 1) * n_coh + i];
      if (!R_FINITE(prev_sampled)) continue;

      for (int j = lj; j < n_dev; j++) {
        R_xlen_t off_curr = b_off + (R_xlen_t)j       * n_coh + i;
        R_xlen_t off_prev_p = (R_xlen_t)(j - 1) * n_coh + i;
        int k_idx_1 = k_idx_by_j[j];
        if (k_idx_1 == NA_INTEGER) {
          cum_sampled[off_curr] = prev_sampled;
          continue;
        }
        int k = k_idx_1 - 1;
        double g_b = (k >= 0 && k < n_links)
                     ? g_star[k + (R_xlen_t)b * n_links]
                     : NA_REAL;
        double p_prev = exposure_proj[off_prev_p];
        if (!R_FINITE(g_b) || !R_FINITE(p_prev)) {
          cum_sampled[off_curr] = prev_sampled;
          continue;
        }
        double inc_mean = g_b * p_prev;
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
          inc_sampled = inc_mean;
        }
        cum_sampled[off_curr] = prev_sampled + inc_sampled;
        prev_sampled = cum_sampled[off_curr];
      }
    }
  }
  PutRNGstate();
}


/* bootstrap_kernel_ed_cell
 *
 *   Main ED-paradigm cell kernel. Same six-phase structure as
 *   bootstrap_kernel_cl_cell:
 *     (a) Resample residuals + place pseudo incrementals (identical -- mu
 *         and sqrt(|mu|) come precomputed from R).
 *     (b) Cumsum along the dev axis (identical).
 *     (c) Mask lower triangle to NA (identical).
 *     (d) Refit g*_k per link  -> bootstrap_refit_ed_gstar (ED, additive).
 *     (e) Forward-project additive + clip
 *         -> bootstrap_fwd_proj_ed_and_clip.
 *     (f) Stage 2 process noise on lower triangle (ED additive)
 *         -> bootstrap_fwd_sim_ed_cell. Produces `cum_sampled` alongside
 *         the Stage 1 `cum_mean`; the two arrays are returned as a named
 *         list (same shape as the CL kernel output).
 *
 *   exposure_proj [n_coh * n_dev] is the column-major projected exposure
 *   array. Caller (R-side) builds it once via a CL projection on the
 *   exposure column of the triangle; in Phase 1 it stays fixed across all
 *   B replicates so the same vector serves all of refit / forward proj /
 *   Stage 2.
 */
SEXP bootstrap_kernel_ed_cell(
    SEXP B_sxp,
    SEXP mu_active_sxp,         /* [n_active] doubles: g_k * P[i, k-1] */
    SEXP sqrt_active_sxp,       /* [n_active] doubles: sqrt(|g_k * P[i, k-1]|) */
    SEXP active_lin_sxp,        /* [n_active] ints (1-indexed pos in n_coh x n_dev) */
    SEXP cell_pool_idx_sxp,     /* [n_active] ints (1-indexed pool id, or 0) */
    SEXP pool_residuals_sxp,    /* concatenated pool residuals */
    SEXP pool_starts_sxp,       /* [n_pools + 1] ints */
    SEXP last_obs_idx_sxp,      /* [n_coh] ints (1-indexed) or NA */
    SEXP link_to_idx_sxp,       /* [n_links] ints (1-indexed) */
    SEXP k_idx_by_j_sxp,        /* [n_dev] ints (1-indexed) or NA */
    SEXP g_hat_vec_sxp,         /* [n_links] doubles: g_k anchor */
    SEXP exposure_proj_sxp,     /* [n_coh * n_dev] doubles: projected exposure */
    SEXP phi_sxp,               /* scalar dispersion phi (cell mode) */
    SEXP alpha_sxp,             /* scalar variance exponent */
    SEXP process_code_sxp,      /* int: 1 gamma / 2 od_pois / 3 normal */
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
  if (LENGTH(k_idx_by_j_sxp)   != n_dev)
    Rf_error("k_idx_by_j must have length n_dev.");
  if (LENGTH(g_hat_vec_sxp)    != n_links)
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
  double *g_hat_vec     = REAL(g_hat_vec_sxp);
  double *exposure_proj = REAL(exposure_proj_sxp);

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
      int pid = cell_pool_idx[a];
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

  /* ----- (d) Refit g*_k from pseudo cumulative + fixed exposure ------ */
  double *g_star = (double *) R_alloc((size_t)n_links * B, sizeof(double));
  bootstrap_refit_ed_gstar(cum, exposure_proj, link_to_idx, g_hat_vec,
                        n_coh, n_dev, B, n_links, g_star);

  /* ----- (e) Forward-project (additive) + clip ----------------------- */
  bootstrap_fwd_proj_ed_and_clip(cum, g_star, exposure_proj,
                                  last_obs_idx, k_idx_by_j,
                                  n_coh, n_dev, B, n_links);

  /* ----- (f) Stage 2 process noise -> cum_sampled (ED additive) ------ */
  double phi          = Rf_asReal(phi_sxp);
  double alpha        = Rf_asReal(alpha_sxp);
  int    process_code = Rf_asInteger(process_code_sxp);

  SEXP cum_sampled_sxp = PROTECT(Rf_allocVector(REALSXP, total));
  SEXP dims_s = PROTECT(Rf_allocVector(INTSXP, 3));
  INTEGER(dims_s)[0] = n_coh;
  INTEGER(dims_s)[1] = n_dev;
  INTEGER(dims_s)[2] = B;
  Rf_setAttrib(cum_sampled_sxp, R_DimSymbol, dims_s);
  UNPROTECT(1);

  bootstrap_fwd_sim_ed_cell(cum, g_star, exposure_proj,
                             last_obs_idx, k_idx_by_j,
                             n_coh, n_dev, B, n_links,
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

  UNPROTECT(4);
  return out;
}


/* bootstrap_kernel_ed_param -- ED textbook parametric kernel
 * (type = "parametric", method = "ed")
 *
 * Phase (a) differs from bootstrap_kernel_ed_cell: instead of resampling a
 * Pearson residual from a pool, each active cell value is drawn directly
 * from ProcessDist(mu_active[a], phi). Phases (b)-(f) mirror the ED cell
 * kernel exactly (cumsum -> mask -> refit g* via fixed exposure ->
 * forward project additive -> Stage 2 noise via bootstrap_fwd_sim_ed_cell).
 *
 * The `process = "normal"` path is rejected at the R level for ED (positivity
 * required for additive ED variance); the kernel still handles it defensively
 * via the cell-level >= 0 clip, but it's not a supported user path.
 */
SEXP bootstrap_kernel_ed_param(
    SEXP B_sxp,
    SEXP mu_active_sxp,
    SEXP active_lin_sxp,
    SEXP last_obs_idx_sxp,
    SEXP link_to_idx_sxp,
    SEXP k_idx_by_j_sxp,
    SEXP g_hat_vec_sxp,
    SEXP exposure_proj_sxp,
    SEXP phi_sxp,
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
  if (LENGTH(mu_active_sxp) != n_active)
    Rf_error("mu_active must have length n_active.");
  if (LENGTH(last_obs_idx_sxp) != n_coh)
    Rf_error("last_obs_idx must have length n_coh.");
  if (LENGTH(k_idx_by_j_sxp) != n_dev)
    Rf_error("k_idx_by_j must have length n_dev.");
  if (LENGTH(g_hat_vec_sxp) != n_links)
    Rf_error("g_hat_vec must have length n_links.");
  if (XLENGTH(exposure_proj_sxp) != (R_xlen_t)n_coh * n_dev)
    Rf_error("exposure_proj must have length n_coh * n_dev.");

  double *mu_active     = REAL(mu_active_sxp);
  int *active_lin       = INTEGER(active_lin_sxp);
  int *last_obs_idx     = INTEGER(last_obs_idx_sxp);
  int *link_to_idx      = INTEGER(link_to_idx_sxp);
  int *k_idx_by_j       = INTEGER(k_idx_by_j_sxp);
  double *g_hat_vec     = REAL(g_hat_vec_sxp);
  double *exposure_proj = REAL(exposure_proj_sxp);

  double phi          = Rf_asReal(phi_sxp);
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

  /* ----- (a) Parametric draw on each active cell -------------------- */
  GetRNGstate();
  for (int b = 0; b < B; b++) {
    R_xlen_t b_off = (R_xlen_t)b * slab;
    for (int a = 0; a < n_active; a++) {
      double mu = mu_active[a];
      R_xlen_t off = b_off + active_lin[a] - 1;
      if (!R_FINITE(mu)) {
        cum[off] = mu;
        continue;
      }
      double draw;
      switch (process_code) {
        case 1:   /* gamma */
        case 2: { /* od_pois */
          if (mu <= 0.0 || !R_FINITE(phi) || phi <= 0.0) {
            draw = mu;
          } else {
            double shape = mu / phi;
            double scale = phi;
            draw = Rf_rgamma(shape, scale);
          }
          break;
        }
        case 3: { /* normal -- not a supported user path for ED */
          if (!R_FINITE(phi) || phi <= 0.0) {
            draw = mu;
          } else {
            double sd = sqrt(phi * pow(fabs(mu), alpha));
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

  /* ----- (d) Refit g*_k from pseudo cumulative + fixed exposure ------ */
  double *g_star = (double *) R_alloc((size_t)n_links * B, sizeof(double));
  bootstrap_refit_ed_gstar(cum, exposure_proj, link_to_idx, g_hat_vec,
                           n_coh, n_dev, B, n_links, g_star);

  /* ----- (e) Forward-project (additive) + clip ----------------------- */
  bootstrap_fwd_proj_ed_and_clip(cum, g_star, exposure_proj,
                                 last_obs_idx, k_idx_by_j,
                                 n_coh, n_dev, B, n_links);

  /* ----- (f) Stage 2 process noise -> cum_sampled (ED additive) ------ */
  SEXP cum_sampled_sxp = PROTECT(Rf_allocVector(REALSXP, total));
  SEXP dims_s = PROTECT(Rf_allocVector(INTSXP, 3));
  INTEGER(dims_s)[0] = n_coh;
  INTEGER(dims_s)[1] = n_dev;
  INTEGER(dims_s)[2] = B;
  Rf_setAttrib(cum_sampled_sxp, R_DimSymbol, dims_s);
  UNPROTECT(1);

  bootstrap_fwd_sim_ed_cell(cum, g_star, exposure_proj,
                            last_obs_idx, k_idx_by_j,
                            n_coh, n_dev, B, n_links,
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

  UNPROTECT(4);
  return out;
}

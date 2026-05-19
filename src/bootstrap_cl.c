/* =============================================================================
 * lossratio: bootstrap stage-1 native kernels -- CL paradigm
 *
 * This file holds the CL (chain ladder) paradigm bootstrap, which uses the
 * multiplicative recursion `C_{k+1} = f_k * C_k + noise`. Three residual /
 * type modes share the file-local helpers:
 *   - bootstrap_kernel_cl_cell        (residual = "cell"  / England-Verrall ODP)
 *   - bootstrap_kernel_cl_link        (residual = "link"  / Mack / Pinheiro)
 *   - bootstrap_kernel_cl_parametric  (type     = "parametric" / Mack closed)
 *
 * The ED-paradigm sibling lives in src/bootstrap_ed.c; shared
 * SE-decomposition helpers live in src/bootstrap_common.c. See the latter
 * for the full R <-> C contract.
 * =============================================================================
 */
#include "lossratio.h"
#include <math.h>    /* sqrt, pow, fabs */
#include <string.h>  /* memset, memcpy */
#include <Rmath.h>   /* Rf_rgamma */


/* bootstrap_refit_cl_fstar
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
static void bootstrap_refit_cl_fstar(
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


/* bootstrap_fwd_proj_cl_and_clip
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
static void bootstrap_fwd_proj_cl_and_clip(
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


/* bootstrap_fwd_sim_cl_cell
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
static void bootstrap_fwd_sim_cl_cell(
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


/* bootstrap_fwd_sim_cl_link
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
 *                   used by bootstrap_fwd_proj_cl_and_clip).
 *   alpha         : variance exponent.
 *   process_code  : 1 gamma / 2 od_pois (Gamma moment-matched) / 3 normal.
 *
 *   For pathological cases (non-finite f, non-positive prev, NA), the
 *   noisy step degenerates to the deterministic recursion.
 */
static void bootstrap_fwd_sim_cl_link(
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


/* bootstrap_kernel_cl_cell -- CL cell-residual kernel (residual = "cell")
 *
 * Six fused phases:
 *   (a) Resample residuals + place pseudo incrementals.
 *   (b) Cumulative sum along the dev axis (per cohort × replicate).
 *   (c) Mask lower triangle to NA_real_.
 *   (d) Refit f*_k per link  -> bootstrap_refit_cl_fstar.
 *   (e) Forward-project + clip negatives -> bootstrap_fwd_proj_cl_and_clip.
 *   (f) Apply Stage 2 process noise on lower triangle ->
 *       bootstrap_fwd_sim_cl_cell. Produces `cum_sampled` alongside the
 *       Stage 1 `cum_mean`; the two arrays are returned as a named list.
 *
 * Returns:
 *   list(cum_mean    = real[n_coh, n_dev, B],   // Stage 1 only
 *        cum_sampled = real[n_coh, n_dev, B])   // Stage 1 + Stage 2
 */

SEXP bootstrap_kernel_cl_cell(
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
  bootstrap_refit_cl_fstar(cum, link_to_idx, f_hat_vec,
                        n_coh, n_dev, B, n_links, f_star);

  /* ----- (e) Forward-project + clip ---------------------------------- */
  bootstrap_fwd_proj_cl_and_clip(cum, f_star, last_obs_idx, k_idx_by_j,
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

  bootstrap_fwd_sim_cl_cell(cum, last_obs_idx, n_coh, n_dev, B,
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


/* bootstrap_kernel_cl_link -- CL link-residual kernel (residual = "link")
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
 *   (d) Refit f*_k per link -> bootstrap_refit_cl_fstar.
 *   (e) Forward-project lower triangle + final clip ->
 *       bootstrap_fwd_proj_cl_and_clip.
 *
 * RNG draw order matches R `sample(pool, n_alt, replace=TRUE)` semantics
 * (per-cohort `unif_rand() * pool_size` floored) so the outer loop order
 * (b outer, k inner, i innermost over was_obs cohorts) gives the same
 * sequence under a fixed seed.
 */

SEXP bootstrap_kernel_cl_link(
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
  bootstrap_refit_cl_fstar(cum, link_to_idx, f_hat_vec,
                        n_coh, n_dev, B, n_links, f_star);

  /* ----- (e) Forward-project + final clip ----------------------------- */
  bootstrap_fwd_proj_cl_and_clip(cum, f_star, last_obs_idx, k_idx_by_j,
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

  bootstrap_fwd_sim_cl_link(cum, last_obs_idx, k_idx_by_j,
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


/* bootstrap_kernel_cl_parametric -- CL parametric kernel (type = "parametric")
 *
 * Three fused phases (mirrors R/bootstrap.R:1235-1267):
 *   (a) Initialize cum to mat_obs across all replicates (observed cells
 *       unchanged — parametric perturbs link factors, not data).
 *   (b) Draw f*_k ~ N(f_hat_k, sqrt(f_var_k)) per replicate, per link.
 *       Drawn only when f_var_k is finite and > 0 (else f*_k = f_hat_k).
 *   (c) Forward-project lower triangle + final clip ->
 *       bootstrap_fwd_proj_cl_and_clip.
 *
 * RNG draw order matches R `rnorm(1, mu, sigma)` semantics: one
 * `norm_rand()` per (b, k) iff f_var_k > 0 (regardless of f_hat_k
 * finiteness — to preserve seed-deterministic RNG state).
 */

SEXP bootstrap_kernel_cl_parametric(
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
  bootstrap_fwd_proj_cl_and_clip(cum, f_star, last_obs_idx, k_idx_by_j,
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

  bootstrap_fwd_sim_cl_link(cum, last_obs_idx, k_idx_by_j,
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


/* bootstrap_kernel_cl_param -- CL textbook parametric kernel
 * (type = "parametric", method = "cl")
 *
 * Phase (a) differs from bootstrap_kernel_cl_cell: instead of resampling a
 * Pearson residual from a pool, each active cell value is drawn directly
 * from ProcessDist(mu_active[a], phi). Phases (b)-(f) mirror the cell
 * kernel exactly (cumsum -> mask -> refit f* -> forward project -> Stage 2
 * process noise via bootstrap_fwd_sim_cl_cell).
 *
 * Gamma path uses `scale = phi` (var = phi*mu, ignores alpha) -- matches
 * the existing Stage-2 gamma convention.
 *
 * RNG draws per cell per replicate:
 *   gamma/od_pois : 1 Rf_rgamma call iff mu > 0 (else deterministic = mu)
 *   normal        : 1 norm_rand() call iff mu finite (clipped to >= 0)
 */
SEXP bootstrap_kernel_cl_param(
    SEXP B_sxp,
    SEXP mu_active_sxp,
    SEXP active_lin_sxp,
    SEXP last_obs_idx_sxp,
    SEXP link_to_idx_sxp,
    SEXP k_idx_by_j_sxp,
    SEXP f_hat_vec_sxp,
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
  if (LENGTH(f_hat_vec_sxp) != n_links)
    Rf_error("f_hat_vec must have length n_links.");

  double *mu_active   = REAL(mu_active_sxp);
  int *active_lin     = INTEGER(active_lin_sxp);
  int *last_obs_idx   = INTEGER(last_obs_idx_sxp);
  int *link_to_idx    = INTEGER(link_to_idx_sxp);
  int *k_idx_by_j     = INTEGER(k_idx_by_j_sxp);
  double *f_hat_vec   = REAL(f_hat_vec_sxp);

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
        cum[off] = mu;          /* deterministic NA propagation */
        continue;
      }
      double draw;
      switch (process_code) {
        case 1:   /* gamma */
        case 2: { /* od_pois (Gamma moment-matched) */
          if (mu <= 0.0 || !R_FINITE(phi) || phi <= 0.0) {
            draw = mu;          /* deterministic fallback */
          } else {
            double shape = mu / phi;
            double scale = phi;
            draw = Rf_rgamma(shape, scale);
          }
          break;
        }
        case 3: { /* normal */
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

  /* ----- (d) Refit f*_k from pseudo cumulative ----------------------- */
  double *f_star = (double *) R_alloc((size_t)n_links * B, sizeof(double));
  bootstrap_refit_cl_fstar(cum, link_to_idx, f_hat_vec,
                           n_coh, n_dev, B, n_links, f_star);

  /* ----- (e) Forward-project + clip ---------------------------------- */
  bootstrap_fwd_proj_cl_and_clip(cum, f_star, last_obs_idx, k_idx_by_j,
                                 n_coh, n_dev, B, n_links);

  /* ----- (f) Stage 2 process noise -> cum_sampled -------------------- */
  SEXP cum_sampled_sxp = PROTECT(Rf_allocVector(REALSXP, total));
  SEXP dims_s = PROTECT(Rf_allocVector(INTSXP, 3));
  INTEGER(dims_s)[0] = n_coh;
  INTEGER(dims_s)[1] = n_dev;
  INTEGER(dims_s)[2] = B;
  Rf_setAttrib(cum_sampled_sxp, R_DimSymbol, dims_s);
  UNPROTECT(1);

  bootstrap_fwd_sim_cl_cell(cum, last_obs_idx, n_coh, n_dev, B,
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

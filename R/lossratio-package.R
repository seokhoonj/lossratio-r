#' @details
#' The core loss ratio is defined as:
#' \deqn{lr = loss / prem}
#'
#' where `prem` represents risk premium, not written prem.
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @useDynLib lossratio, .registration = TRUE
#' @importFrom data.table `:=` `.BY` `.GRP` `.I` `.N` `.SD` as.data.table copy
#'   data.table fifelse melt set setattr setcolorder setnames setorderv shift
#' @importFrom ggplot2 aes coord_flip facet_wrap geom_boxplot geom_hline
#'   geom_line geom_point geom_vline ggplot labs scale_color_manual
#'   scale_y_continuous stat_summary xlab ylab
#' @importFrom ggshort geom_hline1 get_legend ggbar ggheatmap ggline ggtable
#'   hstack_plots_with_legend scale_color_by_month_gradientn
#'   scale_fill_pair_manual scale_y_comma set_ggshort_font stat_mean_hline
#'   switch_theme
#' @importFrom instead add_group_stats assert_class assert_length capture_names
#'   check_col_spec format_period get_half_start get_half_start
#'   get_quarter_start get_year_start has_cols longer prepend_class
#'   set_instead_font summarise_group_stats update_class read_rds
#' @importFrom rlang enquo
#' @importFrom stats median reformulate setNames sigma window
#' @importFrom utils head tail
## usethis namespace: end
NULL

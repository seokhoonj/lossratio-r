#' @details
#' The core loss ratio is defined as:
#' \deqn{ratio = loss / exposure}
#'
#' where `exposure` represents risk premium, not written premium.
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
#' @importFrom rlang enquo
#' @importFrom stats median reformulate setNames sigma window
#' @importFrom utils head tail
## usethis namespace: end
NULL

# lossratio: Loss Ratio Analysis for Insurance Experience Data

A toolkit for loss-ratio analysis and projection on long-format
experience data, oriented toward long-term health insurance. Implements
stage-adaptive loss-ratio projection that uses an exposure-driven model
before the maturity point and chain ladder after it, with supporting
maturity point detection and cohort regime detection for handling
structural breaks. Provides cohort by development period, calendar
period, and total aggregation frameworks for diagnostics, and applies to
any cumulative loss and exposure setting with sufficient sample per
cell.

## Details

The core loss ratio is defined as: \$\$lr = loss / rp\$\$

where `rp` represents risk premium, not written premium.

## See also

Useful links:

- <https://seokhoonj.github.io/lossratio>

- <https://github.com/seokhoonj/lossratio>

- Report bugs at <https://github.com/seokhoonj/lossratio/issues>

## Author

**Maintainer**: Seokhoon Joo <seokhoonj@gmail.com>

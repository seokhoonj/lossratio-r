# lossratio: Loss Ratio Analytics for Long-Term Health Insurance

A loss ratio analytics toolkit for long-term health insurance, covering
cohort development analysis, stage-adaptive loss-ratio projection,
regime detection, and backtest validation on long-format experience
data. Implements stage-adaptive loss-ratio projection that uses an
exposure-driven model before the maturity point and chain ladder after
it, with supporting maturity point detection and cohort regime detection
for handling structural breaks. Provides cohort by development period,
calendar period, and total aggregation frameworks for diagnostics, and
applies to any cumulative loss and premium setting with sufficient
sample per cell.

## Details

The core loss ratio is defined as: \$\$ratio = loss / premium\$\$

where `premium` represents risk premium, not written premium.

## See also

Useful links:

- <https://seokhoonj.github.io/lossratio-r>

- <https://seokhoonj.github.io/lossratio-r/ko>

- <https://github.com/seokhoonj/lossratio-r>

- Report bugs at <https://github.com/seokhoonj/lossratio-r/issues>

## Author

**Maintainer**: Seokhoon Joo <seokhoonj@gmail.com>

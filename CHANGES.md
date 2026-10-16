# Changes

All notable changes to this library are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/) (before 1.0.0, a minor version may break the API).

## Unreleased

Nothing yet.

## 0.1.0 (not yet tagged)

First release.

### Added

- `Stats`: moments, excess kurtosis, autocorrelation, quantiles, two-sample
  Kolmogorov-Smirnov, Wasserstein-1, variance ratio.
- `Series`: trades, two-sided book samples, book level-change counts and optional exact
  order counts of one market over a window.
- `Norm_source`: a series from a recorder data directory (trades, L2 or BBO event logs),
  windowed by venue time.
- `Journal_source`: a series from an exchange-core input journal by replay, and order
  counts from the inputs alone.
- `Fact`: twelve stylised facts (return kurtosis, return and absolute-return
  autocorrelation, volatility clustering, spread, depth, trade size, inter-trade time,
  variance ratios, aggressor imbalance autocorrelation, order-to-trade and cancel ratios)
  with distances and pass bands.
- `Scorecard`: both sides' summaries and the facts, as JSON and markdown.
- `sim-scorecard compare` and `sim-scorecard facts`.

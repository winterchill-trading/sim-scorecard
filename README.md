# sim-scorecard

Measures how realistic a simulator run is: it computes the same stylised facts of order
flow on the simulator's output and on recorded market data over a window, and reports for
each fact both values, a distance (Kolmogorov-Smirnov or Wasserstein for distributions,
differences of curves or ratios otherwise) and a pass/fail band. Every simulator change can
then show whether realism moved, fact by fact.

Built with [OxCaml](https://oxcaml.org) and the Jane Street stack. Recorded data is read
through the public API of
[market-data](https://github.com/winterchill-trading/market-data) (the norm event logs the
[market-recorder](https://github.com/winterchill-trading/market-recorder) writes), and
simulator journals through
[exchange-core](https://github.com/winterchill-trading/exchange-core)'s `Journal`.

This is its own repository because `market-data` depends on `exchange-core`; the
scorecard depends on both.

## Usage

```sh
sim-scorecard compare \
  -sim SIM_DATA_DIR -sim-symbol hyperliquid:BTC -sim-journal run.journal \
  -recorded DATA_DIR -instrument binance:BTCUSDT \
  -from 2026-10-12T13:34:45Z -to 2026-10-12T13:36:14Z \
  -json card.json -markdown card.md
sim-scorecard facts        # the facts, their metric and default band
```

`-sim` is either

- a recorder data directory holding the simulator's own norm logs: record the simulator
  with `market-recorder` (`(config (Local (port N)))`), so both sides are observed through
  the same channel (the venue's websocket, the same book push cadence); or
- an engine input journal (`EXJRNL..`), replayed through `Exchange.Config.default`: right
  for `Stepped` and `Market_sim` runs on a default exchange. A venue simulator with its own
  universe (fees, ticks, margin tiers) replays faithfully only with its own configuration,
  so for those use the norm directory and pass the journal as `-sim-journal`, which adds
  exact order and cancel counts (they need no replay).

`-from`/`-to` select the recorded window (venue time); `-sim-from`/`-sim-to` the
simulator's (an ISO time, or for a journal an offset of its clock such as `90s`); without
them the whole log is used. `-interval-ms` sets the return grid (default 1000), `-depth`
the book levels (default 10), `-band FACT=MAX` overrides a band.

## The facts

Returns are log returns of the mid sampled on a 1 s grid (last book at or before each
point); spread and depth are read on the same grid, so they are time-weighted. A fact
needs 30 samples on each side (15 realised-variance windows), and grid facts count the
book samples behind the grid, not grid points, so a sparse book log is reported as `n/a`
instead of passing for a long series of zero returns.

| Fact | Value shown | Distance | Default band |
| --- | --- | --- | --- |
| `return_kurtosis` | excess kurtosis of returns | abs log ratio of raw kurtosis | 0.25 |
| `return_acf` | lag-1 autocorrelation of returns | mean abs diff over lags 1-10 | 0.10 |
| `abs_return_acf` | mean autocorrelation of absolute returns, lags 1-10 | mean abs diff over lags 1-10 | 0.10 |
| `vol_clustering` | lag-1 autocorrelation of realised variance per 10 returns | abs diff | 0.30 |
| `spread_bps` | median relative spread | KS (and W1) | 0.25 |
| `depth` | median quote notional over the top levels | KS (and W1) | 0.30 |
| `trade_size` | median trade notional | KS (and W1) | 0.25 |
| `inter_trade_time` | median ms between trades | KS (and W1) | 0.25 |
| `variance_ratio` | variance ratio at 10 steps (signature plot) | mean abs diff over 2, 5, 10, 30 | 0.25 |
| `aggressor_imbalance_acf` | mean autocorrelation of per-second aggressor volume imbalance | mean abs diff over lags 1-10 | 0.10 |
| `order_to_trade` | book level additions per trade | abs log ratio (ln 2 = a factor of two) | 0.69 |
| `cancel_ratio` | share of removed depth not explained by traded volume | abs diff | 0.20 |

Recorded venues publish L2, not orders, so the last two are L2 proxies computed the same
way on both sides: size changes at each price level between consecutive book samples, over
the price range both samples cover. A journal adds the exact numbers (orders per trade,
cancels per order) to the header lines. The bands are starting points, not calibrated
thresholds; the per-fact distances are the result, and the pass count is only a summary.

## Results: hl-sim with and without price anchoring

The workspace holds one real recording from market-recorder: about 90 seconds of mainnet
data on 2026-10-12, 13:34:45 to 13:36:14 UTC. Its Hyperliquid BTC book log has only 17
samples in that window (too few for the book facts), so the main comparison is against
Binance BTCUSDT from the same recording, the richest log in it (849 book samples, 2617
trades). hl-sim ran twice for 100 s, each recorded by market-recorder from its websocket
(`hyperliquid:BTC`, top 10 levels):

- **free**: the default random walk with 10 noise traders (`-seed 1`);
- **anchored**: `-anchor binance:BTCUSDT=BTC -anchor-norm <recording> -anchor-from
  13:34:45Z -anchor-to 13:36:14Z -anchor-noise 10`, i.e. the same recorded window replayed
  at speed 1 as the reference (mark, five shadow levels, trade replay), with the same 10
  noise traders kept on BTC.

Distances against recorded Binance BTCUSDT (arm64, 2026-10-16):

| Fact | Recorded | Free sim | Distance | | Anchored sim | Distance | |
| --- | ---: | ---: | --- | --- | ---: | --- | --- |
| `return_kurtosis` | 1.76 | 1.42 | 0.075 | pass | 13.0 | 1.211 | FAIL |
| `return_acf` | 0.061 | 0.349 | 0.159 | FAIL | 0.198 | 0.088 | pass |
| `abs_return_acf` | 0.007 | -0.015 | 0.134 | FAIL | 0.099 | 0.181 | FAIL |
| `vol_clustering` | 0.190 | -0.177 | 0.367 | n/a | 0.047 | 0.144 | n/a |
| `spread_bps` | 0.012 | 2.20 | KS 1.000 | FAIL | 0.121 | KS 1.000 | FAIL |
| `depth` (USD) | 1,399,083 | 20,530 | KS 1.000 | FAIL | 1,306,439 | KS 0.206 | pass |
| `trade_size` (USD) | 165 | 475 | KS 0.270 | FAIL | 557 | KS 0.256 | FAIL |
| `inter_trade_time` (ms) | 0 | 101 | KS 0.365 | FAIL | 107 | KS 0.469 | FAIL |
| `variance_ratio` | 0.93 | 1.93 | 0.551 | FAIL | 0.23 | 0.666 | FAIL |
| `aggressor_imbalance_acf` | -0.014 | 0.105 | 0.199 | FAIL | -0.041 | 0.149 | FAIL |
| `order_to_trade` | 1.05 | 2.36 | 0.814 | FAIL | 3.80 | 1.287 | FAIL |
| `cancel_ratio` | 0.904 | 0.766 | 0.138 | pass | 0.998 | 0.094 | pass |
| Passed | | | 2 of 11 | | | 3 of 11 | |

From the journals: the free run sent 6.8 orders per trade and cancelled 0.81 of them;
the anchored run 16.9 and 0.92 (the anchor's shadow levels are re-placed as the reference
book moves).

What the numbers say:

- **Anchoring brings the book to the reference.** Depth goes from 1.5% of Binance's to
  within KS 0.21 (the shadow levels copy the top five levels), and return autocorrelation
  from 0.35 (the random walk's 100 ms ticks seen on a 1 s grid) to within the band.
- **The spread is set by the tick, not the anchor.** hl-sim uses Hyperliquid's five
  significant figures, a 1 USD tick at 82,500, so its spread is 0.121 bps, exactly what
  recorded Hyperliquid BTC shows (0.121 bps) and ten times Binance's 0.1 USD tick.
- **Anchored returns jump.** The mark follows the reference every 100 ms but noise flow
  around it is thin, so the 1 s mid moves in steps: kurtosis 13 against 1.8, and a
  variance ratio of 0.23 (strong mean reversion at short horizons).
- **Order flow is still synthetic.** Trades arrive on the simulator's 100 ms tick (median
  gap 101-107 ms against 0 ms on Binance, where sweeps print many trades in the same
  millisecond), trade sizes are three times larger, and aggressor imbalance has none of the
  real flow's structure. These are the targets for the next realism work (agent
  populations, self-exciting order flow).
- Ninety seconds is short: volatility clustering is `n/a` everywhere (8 windows of 10 s),
  and the other numbers carry wide sampling error. Recording a longer window and re-running
  is the next step; the tool needs no change for it.

Two real venues against each other (recorded Hyperliquid BTC against Binance BTCUSDT) fail
most of the scored facts too (trade size, imbalance, order-to-trade), which is a reminder
that the reference must be the venue being simulated once enough of its data is recorded.

Reproduce (from the workspace root, with the recording at
`/tmp/market-recorder-mainnet/data`):

```sh
hl-sim -port 3600 -seed 1 -input-journal anchor.journal \
  -anchor binance:BTCUSDT=BTC -anchor-norm /tmp/market-recorder-mainnet/data -anchor-noise 10 \
  -anchor-from 2026-10-12T13:34:45Z -anchor-to 2026-10-12T13:36:14Z &
market-recorder run -config anchor.sexp &   # Hyperliquid BTC, (Local (port 3600))
# ... 100 s, then stop both
sim-scorecard compare -sim anchor-data -sim-symbol hyperliquid:BTC -sim-journal anchor.journal \
  -recorded /tmp/market-recorder-mainnet/data -instrument binance:BTCUSDT \
  -from 2026-10-12T13:34:45Z -to 2026-10-12T13:36:14Z
```

## Library

| Module | Contents |
| --- | --- |
| `Stats` | Mean, variance, excess kurtosis, autocorrelation, quantiles, two-sample KS, Wasserstein-1, variance ratio |
| `Series` | The observations of one market: trades, two-sided book samples, level-change counts, optional exact order counts; `Builder` |
| `Norm_source` | A `Series.t` from a recorder data directory over a window (Async) |
| `Journal_source` | A `Series.t` from an engine input journal by replay; order counts from inputs alone |
| `Fact` | Fact ids, metrics, configuration and bands, `compute` |
| `Scorecard` | Both sides' summaries and the facts; JSON and markdown |

```ocaml
let%bind sim = Norm_source.load ~dir:sim_dir hl_btc ~from ~to_ () in
let%bind recorded = Norm_source.load ~dir:data_dir binance_btc ~from ~to_ () in
let card = Scorecard.create ~sim ~recorded () in
print_string (Scorecard.to_markdown card)
```

## Build

Inside the workspace (siblings resolve by public name):

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @sim-scorecard/all @sim-scorecard/runtest
```

Standalone, CI pins `fixed-decimal`, `exchange-core`, `order-book`,
`exchange-core-engine` (same URL as `exchange-core`), `parquet` and `market-data` from
GitHub in that order.

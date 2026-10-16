# AGENTS.md: sim-scorecard

## Purpose

Scores how realistic a simulator run is: the same stylised facts of order flow computed on
the simulator's output and on recorded market data, each with both values, a distance and a
pass band. One library (`sim-scorecard`, module `Sim_scorecard`) and the `sim-scorecard` CLI.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | `Stats`, `Series`, `Norm_source`, `Journal_source`, `Fact`, `Scorecard` |
| `bin/` | `sim-scorecard compare` and `sim-scorecard facts` |
| `test/` | Expect tests: statistics on known distributions, sources, facts, scorecard output |
| `.github/` | CI workflow (ox-setup with sibling pins, obj-magic) |
| `README.md` | Method, usage, the first hl-sim results |
| `CHANGES.md` | Changes per release |

## Build, test, docs

From this repository inside the workspace:

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @sim-scorecard/all @sim-scorecard/runtest
opam exec --switch 5.2.0+ox -- dune exec --root .. sim-scorecard -- facts
```

Parallel work: prefix with `DUNE_BUILD_DIR=../_build-sim-scorecard`. When a sibling's
half-written `dune` file breaks the workspace build, use a private workspace: a directory
with the root `dune-workspace` and `dune-project` and links to `fixed-decimal`,
`order-book`, `exchange-core`, `parquet`, `market-data` and this repository, built with
`--root <dir>`.

## Conventions

- Format only this repository: `dune build --root .. @sim-scorecard/fmt --auto-promote`.
- Every module has an `.mli`; consume siblings by public name.
- A fact is computed by one function for both sides; never special-case the simulator.
- Distances and verdicts are the result; do not add a weighted overall score.
- Bands are starting points; a changed band needs a reason in the commit message.
- Read recorded data only through `market-data`'s public API (`Event_log`, `L2_book`).

## Dependencies and dependents

Siblings: `exchange-core` and `exchange-core-engine` (journals, replay),
`market-data` (event logs), and through them `fixed-decimal`, `order-book`, `parquet`.
`market-data` depends on `exchange-core`, which is why this is not part of exchange-core.
No dependents yet.

## CI

`.github/workflows/ci.yml` runs the shared `ox-setup` action with pins `fixed-decimal`,
`exchange-core`, `order-book`, `exchange-core-engine` (same URL as `exchange-core`),
`parquet`, `market-data`, then `dune build` and `dune test`; the obj-magic check follows.
Check a run with one `gh run list --limit 1` and at most one `gh run watch <id>
--exit-status`.

## Pitfalls

- `open! Async` replaces `printf` with Async's writer, which a `Command.basic` never
  flushes; use `Core.printf` there.
- `Event_log` files are per UTC day of receive time; `Norm_source` filters by venue time,
  so a window near midnight reads two days.
- A grid forward-fills sparse books; facts count book samples, not grid points.
- Journals of venue simulators replay faithfully only with the simulator's own
  configuration; score their recorded norm logs instead.
- Exception and time sexps differ between macOS and Linux CI; keep paths and local times
  out of expect output.

## Where to read more

- `README.md`; `../specs/repos/sim-scorecard.md`; `../specs/design/simulators.md`.
- `../market-data/README.md` (event log layout), `../market-recorder/README.md`.
- `../oxcaml-claude-skills/AGENTS.md`, `../oxcaml-claude-skills/GOTCHAS.md`.

## Never do

- Install opam packages that change the compiler or `core`, `base`, `async`, `ppx_jane` on
  the shared `5.2.0+ox` switch (dry-run first).
- Publish, tag or release.
- Poll CI in loops.

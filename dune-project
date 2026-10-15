(lang dune 3.17)

(name sim-scorecard)

(generate_opam_files true)

(license MIT)

(maintainers "winterchill-trading")

(authors "winterchill-trading")

(source
 (github winterchill-trading/sim-scorecard))

(package
 (name sim-scorecard)
 (synopsis
  "Scorecard comparing a simulator run with recorded market data: stylised facts, distances and pass bands")
 (depends
  (ocaml
   (>= 5.2))
  dune
  core
  core_unix
  async
  yojson
  fixed-decimal
  exchange-core
  exchange-core-engine
  market-data
  ppx_jane))

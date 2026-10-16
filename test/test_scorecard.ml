open! Core
open Sim_scorecard
module Engine = Exchange_core_engine

let btc = Exchange_core.Symbol.of_string "BTC"

(* A seeded Stepped run of ten simulated minutes, scored through its journal. *)
let run ~seed =
  let path = Filename_unix.temp_file "scorecard" ".journal" in
  let journal = Engine.Journal.create path in
  let sim = Engine.Market_sim.Config.randomize ~seed in
  let h =
    Engine.Stepped.create ~journal { Engine.Stepped.Config.default with sim = Some sim }
  in
  Engine.Stepped.run h ~steps:6000 ~f:(fun _ _ -> ());
  Engine.Journal.close journal;
  let series =
    ok_exn (Journal_source.load ~label:(sprintf "seed %d" seed) ~symbol:btc path)
  in
  Core_unix.unlink path;
  series
;;

let%expect_test "two seeded simulations, markdown and json" =
  let card = Scorecard.create ~sim:(run ~seed:1) ~recorded:(run ~seed:2) () in
  print_string (Scorecard.to_markdown card);
  [%expect
    {|
    - Simulator: `seed 1`, 10643 trades, 5752 book samples, 1970-01-01T00:00:00.300000000Z to 1970-01-01T00:10:00.000000000Z; from its journal: 2.092 orders per trade, 0.472 cancels per order
    - Recorded: `seed 2`, 12406 trades, 5994 book samples, 1970-01-01T00:00:00.100000000Z to 1970-01-01T00:10:00.000000000Z; from its journal: 2.800 orders per trade, 0.621 cancels per order
    - Passed 9 of 12 scored facts (0 not scored: too few samples)

    | Fact | Simulator | Recorded | Distance | Band | Verdict |
    | --- | ---: | ---: | --- | ---: | --- |
    | return_kurtosis | 0.706 | 1.614 | abs log ratio 0.219 | 0.250 | pass |
    | return_acf | 0.100 | 0.197 | mean abs diff 0.049 | 0.100 | pass |
    | abs_return_acf | 0.007 | 0.006 | mean abs diff 0.038 | 0.100 | pass |
    | vol_clustering | -0.031 | 0.022 | abs diff 0.053 | 0.300 | pass |
    | spread_bps | 2.176 | 0.322 | KS 0.442 (W1 2.938) | 0.250 | FAIL |
    | depth | 11148 | 18846 | KS 0.668 (W1 7318) | 0.300 | FAIL |
    | trade_size | 440.0 | 436.2 | KS 0.012 (W1 7.519) | 0.250 | pass |
    | inter_trade_time | 0.000 | 0.000 | KS 0.059 (W1 10.0) | 0.250 | pass |
    | variance_ratio | 1.189 | 1.422 | mean abs diff 0.305 | 0.250 | FAIL |
    | aggressor_imbalance_acf | 0.018 | 0.053 | mean abs diff 0.053 | 0.100 | pass |
    | order_to_trade | 1.073 | 1.334 | abs log ratio 0.218 | 0.693 | pass |
    | cancel_ratio | 0.550 | 0.619 | abs diff 0.068 | 0.200 | pass |
    |}];
  let json = Scorecard.to_json card in
  let open Yojson.Safe.Util in
  print_s
    [%sexp
      (List.map (json |> keys) ~f:Fn.id : string list)
      , (json |> member "passed" |> to_int : int)
      , (json |> member "scored" |> to_int : int)];
  print_endline (Yojson.Safe.pretty_to_string (json |> member "facts" |> index 0));
  print_endline (Yojson.Safe.pretty_to_string (json |> member "sim"));
  [%expect
    {|
    ((sim recorded config facts passed scored) 9 12)
    {
      "fact": "return_kurtosis",
      "description": "excess kurtosis of mid log returns (fat tails)",
      "sim": 0.7058080223270791,
      "recorded": 1.6138348862858836,
      "metric": "abs log ratio",
      "distance": 0.2191580490707127,
      "w1": null,
      "band": 0.25,
      "verdict": "pass",
      "n_sim": 599,
      "n_recorded": 599
    }
    {
      "label": "seed 1",
      "trades": 10643,
      "books": 5752,
      "first": "1970-01-01T00:00:00.300000000Z",
      "last": "1970-01-01T00:10:00.000000000Z",
      "orders": { "placed": 22260, "cancelled": 10512, "modified": 0 },
      "order_to_trade_exact": 2.091515550126844,
      "cancel_ratio_exact": 0.47223719676549863
    }
    |}]
;;

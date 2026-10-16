open! Core
open Sim_scorecard

let normal st =
  let u1 = Random.State.float st 1. +. 1e-12
  and u2 = Random.State.float st 1. in
  Float.sqrt (-2. *. Float.log u1) *. Float.cos (2. *. Float.pi *. u2)
;;

let second = 1_000_000_000

(* One book per second following [returns], 1 bp spread, and one trade per second whose
   side follows the return's sign with probability [persist]. *)
let series ~label ~returns ~seed =
  let st = Random.State.make [| seed |] in
  let b = Series.Builder.create ~label ~depth:5 in
  let mid = ref 100. in
  Array.iteri returns ~f:(fun i r ->
    mid := !mid *. Float.exp r;
    let half = !mid *. 0.00005 in
    let size = 1. +. Random.State.float st 4. in
    Series.Builder.add_levels
      b
      ~ts:(i * second)
      ~bids:[ !mid -. half, size; !mid -. (3. *. half), size ]
      ~asks:[ !mid +. half, size; !mid +. (3. *. half), size ];
    Series.Builder.add_trade
      b
      { ts = (i * second) + (second / 2)
      ; px = !mid
      ; size = Random.State.float st 2. +. 0.01
      ; side = (if Float.( >= ) r 0. then Buy else Sell)
      });
  Series.Builder.finish b
;;

let gaussian n ~seed =
  let st = Random.State.make [| seed |] in
  Array.init n ~f:(fun _ -> 0.0005 *. normal st)
;;

(* GARCH(1,1): fat tails and volatility clustering. *)
let garch n ~seed =
  let st = Random.State.make [| seed |] in
  let var = ref 2.5e-7 in
  let prev = ref 0. in
  Array.init n ~f:(fun _ ->
    var := 1e-8 +. (0.25 *. !prev *. !prev) +. (0.7 *. !var);
    prev := Float.sqrt !var *. normal st;
    !prev)
;;

let show facts =
  List.iter facts ~f:(fun (f : Fact.t) ->
    printf
      "%-24s %9.3f %9.3f %-11s %7.3f %5.2f %s\n"
      (Fact.Id.to_string f.id)
      f.sim
      f.recorded
      (Fact.Metric.to_string f.metric)
      f.distance
      f.band
      (Fact.Verdict.to_string f.verdict))
;;

let%expect_test "a series against itself passes everything" =
  let s = series ~label:"a" ~returns:(gaussian 2000 ~seed:1) ~seed:1 in
  show (Fact.compute Fact.Config.default ~sim:s ~recorded:s);
  [%expect
    {|
    return_kurtosis              0.207     0.207 |log ratio|   0.000  0.25 pass
    return_acf                  -0.012    -0.012 mean |diff|   0.000  0.10 pass
    abs_return_acf              -0.004    -0.004 mean |diff|   0.000  0.10 pass
    vol_clustering              -0.067    -0.067 |diff|        0.000  0.30 pass
    spread_bps                   1.000     1.000 KS            0.000  0.25 pass
    depth                     1205.041  1205.041 KS            0.000  0.30 pass
    trade_size                  99.586    99.586 KS            0.000  0.25 pass
    inter_trade_time          1000.000  1000.000 KS            0.000  0.25 pass
    variance_ratio               1.058     1.058 mean |diff|   0.000  0.25 pass
    aggressor_imbalance_acf      0.008     0.008 mean |diff|   0.000  0.10 pass
    order_to_trade               2.171     2.171 |log ratio|   0.000  0.69 pass
    cancel_ratio                 0.845     0.845 |diff|        0.000  0.20 pass
    |}]
;;

let%expect_test "a Gaussian walk against GARCH returns" =
  let sim = series ~label:"walk" ~returns:(gaussian 3000 ~seed:2) ~seed:2 in
  let recorded = series ~label:"garch" ~returns:(garch 3000 ~seed:3) ~seed:3 in
  show (Fact.compute Fact.Config.default ~sim ~recorded);
  [%expect
    {|
    return_kurtosis              0.013     2.328 |log ratio|   0.570  0.25 FAIL
    return_acf                   0.012    -0.033 mean |diff|   0.030  0.10 pass
    abs_return_acf              -0.004     0.223 mean |diff|   0.227  0.10 FAIL
    vol_clustering              -0.038     0.347 |diff|        0.385  0.30 FAIL
    spread_bps                   1.000     1.000 KS            0.020  0.25 pass
    depth                     1228.555  1190.053 KS            0.026  0.30 pass
    trade_size                 100.950   103.636 KS            0.026  0.25 pass
    inter_trade_time          1000.000  1000.000 KS            0.000  0.25 pass
    variance_ratio               0.888     1.128 mean |diff|   0.183  0.25 pass
    aggressor_imbalance_acf     -0.005     0.003 mean |diff|   0.018  0.10 pass
    order_to_trade               2.168     2.223 |log ratio|   0.025  0.69 pass
    cancel_ratio                 0.846     0.846 |diff|        0.000  0.20 pass
    |}]
;;

let%expect_test "too little data is not scored" =
  let s = series ~label:"short" ~returns:(gaussian 5 ~seed:4) ~seed:4 in
  show (Fact.compute Fact.Config.default ~sim:s ~recorded:s);
  [%expect
    {|
    return_kurtosis             -0.700    -0.700 |log ratio|   0.000  0.25 n/a
    return_acf                  -0.009    -0.009 mean |diff|   0.000  0.10 n/a
    abs_return_acf              -0.238    -0.238 mean |diff|   0.000  0.10 n/a
    vol_clustering                 nan       nan |diff|          nan  0.30 n/a
    spread_bps                   1.000     1.000 KS            0.000  0.25 n/a
    depth                     1595.500  1595.500 KS            0.000  0.30 n/a
    trade_size                  62.455    62.455 KS            0.000  0.25 n/a
    inter_trade_time          1000.000  1000.000 KS            0.000  0.25 n/a
    variance_ratio                 nan       nan mean |diff|   0.000  0.25 n/a
    aggressor_imbalance_acf     -0.100    -0.100 mean |diff|   0.000  0.10 n/a
    order_to_trade               1.600     1.600 |log ratio|   0.000  0.69 n/a
    cancel_ratio                 0.914     0.914 |diff|        0.000  0.20 n/a
    |}]
;;

let%expect_test "grid, returns and imbalances" =
  let b = Series.Builder.create ~label:"g" ~depth:1 in
  List.iter
    [ 0, 100.; 1_500_000_000, 101.; 2_200_000_000, 102. ]
    ~f:(fun (ts, mid) ->
      Series.Builder.add_levels b ~ts ~bids:[ mid -. 0.5, 1. ] ~asks:[ mid +. 0.5, 1. ]);
  List.iter
    [ 0, Exchange_core.Side.Buy, 1.; 100, Sell, 3.; 2_500_000_000, Buy, 2. ]
    ~f:(fun (ts, side, size) -> Series.Builder.add_trade b { ts; px = 100.; size; side });
  let s = Series.Builder.finish b in
  let interval = Time_ns.Span.second in
  print_s
    [%sexp
      (Array.map (Fact.grid_books s ~interval) ~f:Series.Book.mid : float array)
      , (Fact.returns s ~interval : float array)
      , (Fact.imbalances s ~interval : float array)];
  print_s [%sexp (List.map Fact.Id.all ~f:Fact.Id.to_string : string list)];
  print_s [%sexp (Fact.Id.of_string "spread_bps" : Fact.Id.t)];
  [%expect
    {|
    ((100 100 101) (0 0.009950330853168092) (-0.5 0 1))
    (return_kurtosis return_acf abs_return_acf vol_clustering spread_bps depth
     trade_size inter_trade_time variance_ratio aggressor_imbalance_acf
     order_to_trade cancel_ratio)
    Spread_bps
    |}]
;;

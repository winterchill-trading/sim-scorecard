open! Core
open Sim_scorecard

let rng () = Random.State.make [| 42 |]

(* Box-Muller. *)
let normal st =
  let u1 = Random.State.float st 1. +. 1e-12
  and u2 = Random.State.float st 1. in
  Float.sqrt (-2. *. Float.log u1) *. Float.cos (2. *. Float.pi *. u2)
;;

let normals n =
  let st = rng () in
  Array.init n ~f:(fun _ -> normal st)
;;

let p x = printf "%.3f\n" x

let%expect_test "moments" =
  p (Stats.mean [| 1.; 2.; 3.; 4. |]);
  p (Stats.variance [| 1.; 2.; 3.; 4. |]);
  (* Normal: excess kurtosis near 0; Laplace: near 3. *)
  p (Stats.excess_kurtosis (normals 200_000));
  let st = rng () in
  let laplace =
    Array.init 200_000 ~f:(fun _ ->
      let u = Random.State.float st 1. -. 0.5 in
      -.Float.copysign 1. u *. Float.log (1. -. (2. *. Float.abs u)))
  in
  p (Stats.excess_kurtosis laplace);
  p (Stats.excess_kurtosis [| 1.; 1.; 1.; 1. |]);
  [%expect {|
    2.500
    1.250
    -0.013
    2.973
    nan
    |}]
;;

let%expect_test "autocorrelation" =
  (* AR(1) with phi = 0.5: acf(k) = 0.5^k. *)
  let e = normals 200_000 in
  let x = Array.copy e in
  for i = 1 to Array.length x - 1 do
    x.(i) <- (0.5 *. x.(i - 1)) +. e.(i)
  done;
  Array.iter (Stats.acf_lags x ~max_lag:3) ~f:p;
  p (Stats.acf (normals 200_000) ~lag:1);
  p (Stats.acf [| 1.; 2. |] ~lag:1);
  [%expect {|
    0.500
    0.251
    0.129
    -0.001
    nan
    |}]
;;

let%expect_test "quantiles" =
  let a = [| 5.; 1.; 3.; 2.; 4.; Float.nan |] in
  p (Stats.median a);
  p (Stats.quantile a 0.25);
  p (Stats.quantile a 1.);
  [%expect {|
    3.000
    2.000
    5.000
    |}]
;;

let%expect_test "ks and wasserstein" =
  let a = normals 20_000 in
  let shifted = Array.map a ~f:(fun x -> x +. 1.) in
  p (Stats.ks a a);
  p (Stats.ks [| 1.; 2. |] [| 3.; 4. |]);
  (* Two normals one sd apart: KS = 2 * Phi(0.5) - 1 = 0.383. *)
  p (Stats.ks a shifted);
  p (Stats.wasserstein1 a shifted);
  p (Stats.ks a [| 0. |]);
  p (Stats.ks [||] a);
  [%expect {|
    0.000
    1.000
    0.386
    1.000
    0.500
    nan
    |}]
;;

let%expect_test "variance ratio" =
  p (Stats.variance_ratio (normals 100_000) ~k:10);
  (* Bid-ask bounce: alternating returns cancel out over any even horizon. *)
  p
    (Stats.variance_ratio
       (Array.init 1000 ~f:(fun i -> if i % 2 = 0 then 1. else -1.))
       ~k:2);
  (* Trend: positively correlated returns. *)
  let e = normals 100_000 in
  let x = Array.copy e in
  for i = 1 to Array.length x - 1 do
    x.(i) <- (0.5 *. x.(i - 1)) +. e.(i)
  done;
  p (Stats.variance_ratio x ~k:10);
  [%expect {|
    0.994
    0.000
    2.609
    |}]
;;

let%expect_test "standardize and mean_abs_diff" =
  let z = Stats.standardize [| 1.; 2.; 3. |] in
  Array.iter z ~f:p;
  print_s [%sexp (Array.length (Stats.standardize [| 2.; 2. |]) : int)];
  p (Stats.mean_abs_diff [| 1.; Float.nan; 3. |] [| 2.; 5.; 1. |]);
  [%expect {|
    -1.225
    0.000
    1.225
    0
    1.500
    |}]
;;

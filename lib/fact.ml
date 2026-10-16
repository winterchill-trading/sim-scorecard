open! Core

module Id = struct
  type t =
    | Return_kurtosis
    | Return_acf
    | Abs_return_acf
    | Vol_clustering
    | Spread_bps
    | Depth
    | Trade_size
    | Inter_trade_time
    | Variance_ratio
    | Aggressor_imbalance_acf
    | Order_to_trade
    | Cancel_ratio
  [@@deriving sexp, compare, equal, enumerate]

  let to_string t = String.lowercase (Sexp.to_string (sexp_of_t t))
  let of_string s = t_of_sexp (Sexp.Atom (String.capitalize s))

  let description = function
    | Return_kurtosis -> "excess kurtosis of mid log returns (fat tails)"
    | Return_acf -> "autocorrelation of returns, lags 1..L (near zero on real markets)"
    | Abs_return_acf ->
      "autocorrelation of absolute returns, lags 1..L (slow positive decay)"
    | Vol_clustering -> "lag-1 autocorrelation of realised variance per window"
    | Spread_bps -> "relative bid-ask spread in bps, time-weighted"
    | Depth -> "quote notional over the top levels, time-weighted"
    | Trade_size -> "trade notional"
    | Inter_trade_time -> "milliseconds between consecutive trades"
    | Variance_ratio -> "variance ratios over horizons (signature plot)"
    | Aggressor_imbalance_acf ->
      "autocorrelation of aggressor volume imbalance per bucket, lags 1..L"
    | Order_to_trade -> "book level additions per trade (L2 proxy for orders per trade)"
    | Cancel_ratio -> "share of removed depth not explained by trades (L2 proxy)"
  ;;
end

module Metric = struct
  type t =
    | Ks
    | Wasserstein
    | Mean_abs_diff
    | Abs_diff
    | Abs_log_ratio
  [@@deriving sexp, compare, equal]

  let to_string = function
    | Ks -> "KS"
    | Wasserstein -> "W1"
    | Mean_abs_diff -> "mean |diff|"
    | Abs_diff -> "|diff|"
    | Abs_log_ratio -> "|log ratio|"
  ;;
end

module Config = struct
  type t =
    { interval : Time_ns.Span.t
    ; max_lag : int
    ; vol_window : int
    ; horizons : int list
    ; imbalance_interval : Time_ns.Span.t
    ; min_samples : int
    ; bands : (Id.t * float) list
    }
  [@@deriving sexp]

  let default =
    { interval = Time_ns.Span.second
    ; max_lag = 10
    ; vol_window = 10
    ; horizons = [ 2; 5; 10; 30 ]
    ; imbalance_interval = Time_ns.Span.second
    ; min_samples = 10
    ; bands = []
    }
  ;;

  let metric : Id.t -> Metric.t = function
    | Spread_bps | Depth | Trade_size | Inter_trade_time -> Ks
    | Return_acf | Abs_return_acf | Variance_ratio | Aggressor_imbalance_acf ->
      Mean_abs_diff
    | Vol_clustering | Cancel_ratio -> Abs_diff
    | Return_kurtosis | Order_to_trade -> Abs_log_ratio
  ;;

  (* Starting points, not calibrated thresholds: KS 0.25 is a clearly visible but moderate
     shift; curve differences of 0.1 in correlation; a factor of two for ratios, 1.28 for
     kurtosis. *)
  let default_band : Id.t -> float = function
    | Return_kurtosis -> 0.25
    | Return_acf -> 0.1
    | Abs_return_acf -> 0.1
    | Vol_clustering -> 0.3
    | Spread_bps -> 0.25
    | Depth -> 0.3
    | Trade_size -> 0.25
    | Inter_trade_time -> 0.25
    | Variance_ratio -> 0.25
    | Aggressor_imbalance_acf -> 0.1
    | Order_to_trade -> Float.log 2.
    | Cancel_ratio -> 0.2
  ;;

  let band t id =
    match List.Assoc.find t.bands id ~equal:Id.equal with
    | Some b -> b
    | None -> default_band id
  ;;
end

module Verdict = struct
  type t =
    | Pass
    | Fail
    | Insufficient
  [@@deriving sexp, compare, equal]

  let to_string = function
    | Pass -> "pass"
    | Fail -> "FAIL"
    | Insufficient -> "n/a"
  ;;
end

type t =
  { id : Id.t
  ; sim : float
  ; recorded : float
  ; metric : Metric.t
  ; distance : float
  ; band : float
  ; verdict : Verdict.t
  ; w1 : float
  ; n_sim : int
  ; n_recorded : int
  }
[@@deriving sexp_of]

let grid_books (s : Series.t) ~interval =
  let books = s.books in
  let n = Array.length books in
  if n = 0
  then [||]
  else (
    let step = Time_ns.Span.to_int_ns interval in
    let first = books.(0).ts
    and last = books.(n - 1).ts in
    let points = ((last - first) / step) + 1 in
    let j = ref 0 in
    Array.init points ~f:(fun k ->
      let t = first + (k * step) in
      while !j + 1 < n && books.(!j + 1).ts <= t do
        incr j
      done;
      books.(!j)))
;;

let returns s ~interval =
  let g = grid_books s ~interval in
  if Array.length g < 2
  then [||]
  else
    Array.init
      (Array.length g - 1)
      ~f:(fun i -> Float.log (Series.Book.mid g.(i + 1) /. Series.Book.mid g.(i)))
;;

let imbalances (s : Series.t) ~interval =
  let trades = s.trades in
  let n = Array.length trades in
  if n = 0
  then [||]
  else (
    let step = Time_ns.Span.to_int_ns interval in
    let first = trades.(0).ts in
    let buckets = ((trades.(n - 1).ts - first) / step) + 1 in
    let buy = Array.create ~len:buckets 0.
    and sell = Array.create ~len:buckets 0. in
    Array.iter trades ~f:(fun (tr : Series.Trade.t) ->
      let b = (tr.ts - first) / step in
      match tr.side with
      | Buy -> buy.(b) <- buy.(b) +. tr.size
      | Sell -> sell.(b) <- sell.(b) +. tr.size);
    Array.init buckets ~f:(fun b ->
      let total = buy.(b) +. sell.(b) in
      if Float.( > ) total 0. then (buy.(b) -. sell.(b)) /. total else 0.))
;;

(* Per-window realised variance (sum of squared returns). *)
let realised_variance r ~window =
  Array.init
    (Array.length r / window)
    ~f:(fun w ->
      let s = ref 0. in
      for i = w * window to (w * window) + window - 1 do
        s := !s +. (r.(i) *. r.(i))
      done;
      !s)
;;

let trade_notional (s : Series.t) =
  Array.map s.trades ~f:(fun (t : Series.Trade.t) -> t.px *. t.size)
;;

let inter_trade_ms (s : Series.t) =
  let t = s.trades in
  if Array.length t < 2
  then [||]
  else
    Array.init
      (Array.length t - 1)
      ~f:(fun i -> Float.of_int (t.(i + 1).ts - t.(i).ts) /. 1e6)
;;

let order_to_trade (s : Series.t) =
  let trades = Array.length s.trades in
  if trades = 0 then Float.nan else Float.of_int s.level_increases /. Float.of_int trades
;;

let cancel_ratio (s : Series.t) =
  let traded = Array.sum (module Float) s.trades ~f:(fun t -> t.size) in
  if Float.( <= ) s.decreased_size 0.
  then Float.nan
  else Float.clamp_exn (1. -. (traded /. s.decreased_size)) ~min:0. ~max:1.
;;

let mean_finite a =
  let a = Array.filter a ~f:Float.is_finite in
  Stats.mean a
;;

let compute (c : Config.t) ~(sim : Series.t) ~(recorded : Series.t) =
  let both f = f sim, f recorded in
  let r_sim, r_rec = both (returns ~interval:c.interval) in
  let g_sim, g_rec = both (grid_books ~interval:c.interval) in
  let fact id ~value ~distance ~n:(n_sim, n_recorded) ~min =
    let sim, recorded = value in
    let band = Config.band c id in
    let verdict : Verdict.t =
      if n_sim < min || n_recorded < min || not (Float.is_finite distance)
      then Insufficient
      else if Float.( <= ) distance band
      then Pass
      else Fail
    in
    { id
    ; sim
    ; recorded
    ; metric = Config.metric id
    ; distance
    ; band
    ; verdict
    ; w1 = Float.nan
    ; n_sim
    ; n_recorded
    }
  in
  let len (a, b) = Array.length a, Array.length b in
  let distribution id (a, b) ~value =
    { (fact
         id
         ~value:(value a, value b)
         ~distance:(Stats.ks a b)
         ~n:(len (a, b))
         ~min:c.min_samples)
      with
      w1 = Stats.wasserstein1 a b
    }
  in
  let curve id (a, b) ~series ~f ~min =
    let ca = f a
    and cb = f b in
    fact
      id
      ~value:(mean_finite ca, mean_finite cb)
      ~distance:(Stats.mean_abs_diff ca cb)
      ~n:(len series)
      ~min
  in
  let acf a = Stats.acf_lags a ~max_lag:c.max_lag in
  let abs a = Array.map a ~f:Float.abs in
  let rv_sim, rv_rec =
    ( realised_variance r_sim ~window:c.vol_window
    , realised_variance r_rec ~window:c.vol_window )
  in
  let lag1 a = Stats.acf a ~lag:1 in
  let spread g = Array.map g ~f:Series.Book.spread_bps in
  let depth g = Array.map g ~f:(fun (b : Series.Book.t) -> b.depth) in
  let vr r =
    Array.of_list (List.map c.horizons ~f:(fun k -> Stats.variance_ratio r ~k))
  in
  let imb_sim, imb_rec = both (imbalances ~interval:c.imbalance_interval) in
  let ratio id f ~metric_distance =
    let a = f sim
    and b = f recorded in
    fact
      id
      ~value:(a, b)
      ~distance:(metric_distance a b)
      ~n:(Array.length sim.trades, Array.length recorded.trades)
      ~min:c.min_samples
  in
  (* Kurtosis is compared as a ratio of raw kurtosis ([excess + 3], always positive): a KS
     test on standardised returns barely sees the tails, which carry little mass. *)
  let k_sim, k_rec = Stats.excess_kurtosis r_sim, Stats.excess_kurtosis r_rec in
  [ fact
      Return_kurtosis
      ~value:(k_sim, k_rec)
      ~distance:(Float.abs (Float.log ((k_sim +. 3.) /. (k_rec +. 3.))))
      ~n:(len (r_sim, r_rec))
      ~min:c.min_samples
  ; (* Headline: lag 1; distance over every lag. *)
    { (curve Return_acf (r_sim, r_rec) ~series:(r_sim, r_rec) ~f:acf ~min:c.min_samples) with
      sim = lag1 r_sim
    ; recorded = lag1 r_rec
    }
  ; curve
      Abs_return_acf
      (abs r_sim, abs r_rec)
      ~series:(r_sim, r_rec)
      ~f:acf
      ~min:c.min_samples
  ; fact
      Vol_clustering
      ~value:(lag1 rv_sim, lag1 rv_rec)
      ~distance:(Float.abs (lag1 rv_sim -. lag1 rv_rec))
      ~n:(len (rv_sim, rv_rec))
      ~min:(Int.max 4 (c.min_samples / 2))
  ; distribution Spread_bps (spread g_sim, spread g_rec) ~value:Stats.median
  ; distribution Depth (depth g_sim, depth g_rec) ~value:Stats.median
  ; distribution Trade_size (both trade_notional) ~value:Stats.median
  ; distribution Inter_trade_time (both inter_trade_ms) ~value:Stats.median
  ; (* Headline: the middle horizon. *)
    (let horizon = List.nth_exn c.horizons (List.length c.horizons / 2) in
     { (curve
          Variance_ratio
          (r_sim, r_rec)
          ~series:(r_sim, r_rec)
          ~f:vr
          ~min:c.min_samples)
       with
       sim = Stats.variance_ratio r_sim ~k:horizon
     ; recorded = Stats.variance_ratio r_rec ~k:horizon
     })
  ; curve
      Aggressor_imbalance_acf
      (imb_sim, imb_rec)
      ~series:(imb_sim, imb_rec)
      ~f:acf
      ~min:c.min_samples
  ; ratio Order_to_trade order_to_trade ~metric_distance:(fun a b ->
      Float.abs (Float.log (a /. b)))
  ; ratio Cancel_ratio cancel_ratio ~metric_distance:(fun a b -> Float.abs (a -. b))
  ]
;;

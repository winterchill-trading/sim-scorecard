open! Core

module Side = struct
  type t =
    { label : string
    ; trades : int
    ; books : int
    ; first : Time_ns.t option
    ; last : Time_ns.t option
    ; orders : Series.Orders.t option
    }
  [@@deriving sexp_of]

  let of_series (s : Series.t) =
    let span = Series.span s in
    let time f = Option.map span ~f:(fun p -> Time_ns.of_int_ns_since_epoch (f p)) in
    { label = s.label
    ; trades = Array.length s.trades
    ; books = Array.length s.books
    ; first = time fst
    ; last = time snd
    ; orders = s.orders
    }
  ;;

  let exact_ratios t =
    Option.bind t.orders ~f:(fun (o : Series.Orders.t) ->
      if t.trades = 0 || o.placed = 0
      then None
      else
        Some
          ( Float.of_int o.placed /. Float.of_int t.trades
          , Float.of_int o.cancelled /. Float.of_int o.placed ))
  ;;
end

type t =
  { sim : Side.t
  ; recorded : Side.t
  ; config : Fact.Config.t
  ; facts : Fact.t list
  }
[@@deriving sexp_of]

let create ?(config = Fact.Config.default) ~sim ~recorded () =
  { sim = Side.of_series sim
  ; recorded = Side.of_series recorded
  ; config
  ; facts = Fact.compute config ~sim ~recorded
  }
;;

let count t v = List.count t.facts ~f:(fun (f : Fact.t) -> Fact.Verdict.equal f.verdict v)
let passed t = count t Pass
let scored t = passed t + count t Fail
let num x : Yojson.Safe.t = if Float.is_finite x then `Float x else `Null

let time = function
  | None -> `Null
  | Some t -> `String (Time_ns.to_string_iso8601_basic t ~zone:Time_float.Zone.utc)
;;

let side_json (s : Side.t) : Yojson.Safe.t =
  `Assoc
    ([ "label", `String s.label
     ; "trades", `Int s.trades
     ; "books", `Int s.books
     ; "first", time s.first
     ; "last", time s.last
     ]
     @
     match s.orders, Side.exact_ratios s with
     | None, _ -> []
     | Some o, ratios ->
       [ ( "orders"
         , `Assoc
             [ "placed", `Int o.placed
             ; "cancelled", `Int o.cancelled
             ; "modified", `Int o.modified
             ] )
       ]
       @ Option.value_map ratios ~default:[] ~f:(fun (ott, cancel) ->
         [ "order_to_trade_exact", num ott; "cancel_ratio_exact", num cancel ]))
;;

let to_json t : Yojson.Safe.t =
  `Assoc
    [ "sim", side_json t.sim
    ; "recorded", side_json t.recorded
    ; ( "config"
      , `Assoc
          [ "interval_ms", `Float (Time_ns.Span.to_ms t.config.interval)
          ; "max_lag", `Int t.config.max_lag
          ; "vol_window", `Int t.config.vol_window
          ; "horizons", `List (List.map t.config.horizons ~f:(fun h -> `Int h))
          ; ( "imbalance_interval_ms"
            , `Float (Time_ns.Span.to_ms t.config.imbalance_interval) )
          ; "min_samples", `Int t.config.min_samples
          ] )
    ; ( "facts"
      , `List
          (List.map t.facts ~f:(fun (f : Fact.t) ->
             `Assoc
               [ "fact", `String (Fact.Id.to_string f.id)
               ; "description", `String (Fact.Id.description f.id)
               ; "sim", num f.sim
               ; "recorded", num f.recorded
               ; "metric", `String (Fact.Metric.to_string f.metric)
               ; "distance", num f.distance
               ; "w1", num f.w1
               ; "band", num f.band
               ; "verdict", `String (Fact.Verdict.to_string f.verdict)
               ; "n_sim", `Int f.n_sim
               ; "n_recorded", `Int f.n_recorded
               ])) )
    ; "passed", `Int (passed t)
    ; "scored", `Int (scored t)
    ]
;;

(* Significant figures that keep both small correlations and large notionals readable. *)
let fmt x =
  if not (Float.is_finite x)
  then "n/a"
  else if Float.( >= ) (Float.abs x) 1000.
  then sprintf "%.0f" x
  else if Float.( >= ) (Float.abs x) 10.
  then sprintf "%.1f" x
  else sprintf "%.3f" x
;;

let side_line name (s : Side.t) =
  let span =
    match s.first, s.last with
    | Some a, Some b ->
      sprintf
        "%s to %s"
        (Time_ns.to_string_iso8601_basic a ~zone:Time_float.Zone.utc)
        (Time_ns.to_string_iso8601_basic b ~zone:Time_float.Zone.utc)
    | _ -> "empty"
  in
  let exact =
    match Side.exact_ratios s with
    | None -> ""
    | Some (ott, cancel) ->
      sprintf
        "; from its journal: %s orders per trade, %s cancels per order"
        (fmt ott)
        (fmt cancel)
  in
  sprintf
    "- %s: `%s`, %d trades, %d book samples, %s%s\n"
    name
    s.label
    s.trades
    s.books
    span
    exact
;;

let to_markdown t =
  let b = Buffer.create 2048 in
  Buffer.add_string b (side_line "Simulator" t.sim);
  Buffer.add_string b (side_line "Recorded" t.recorded);
  Buffer.add_string
    b
    (sprintf
       "- Passed %d of %d scored facts (%d not scored: too few samples)\n\n"
       (passed t)
       (scored t)
       (List.length t.facts - scored t));
  Buffer.add_string
    b
    "| Fact | Simulator | Recorded | Distance | Band | Verdict |\n\
     | --- | ---: | ---: | --- | ---: | --- |\n";
  List.iter t.facts ~f:(fun (f : Fact.t) ->
    Buffer.add_string
      b
      (sprintf
         "| %s | %s | %s | %s %s%s | %s | %s |\n"
         (Fact.Id.to_string f.id)
         (fmt f.sim)
         (fmt f.recorded)
         (Fact.Metric.to_string f.metric)
         (fmt f.distance)
         (if Float.is_finite f.w1 then sprintf " (W1 %s)" (fmt f.w1) else "")
         (fmt f.band)
         (Fact.Verdict.to_string f.verdict)));
  Buffer.contents b
;;

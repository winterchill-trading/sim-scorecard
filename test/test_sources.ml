open! Core
open! Async
open Sim_scorecard
module Md = Market_data
module Engine = Exchange_core_engine

let summary (s : Series.t) =
  print_s
    [%sexp
      { label = (s.label : string)
      ; trades = (Array.length s.trades : int)
      ; books = (Array.length s.books : int)
      ; increases = (s.level_increases : int)
      ; decreases = (s.level_decreases : int)
      ; orders = (s.orders : Series.Orders.t option)
      }]
;;

let%expect_test "a seeded Stepped run, through its journal" =
  let path = Filename_unix.temp_file "scorecard" ".journal" in
  let journal = Engine.Journal.create path in
  let h = Engine.Stepped.create ~journal Engine.Stepped.Config.default in
  Engine.Stepped.run h ~steps:600 ~f:(fun _ _ -> ());
  Engine.Journal.close journal;
  let btc = Exchange_core.Symbol.of_string "BTC" in
  let s = ok_exn (Journal_source.load ~symbol:btc path) in
  summary s;
  (* A window of the exchange clock: the first 30 of the 60 seconds. *)
  let half = ok_exn (Journal_source.load ~symbol:btc ~to_:30_000_000_000 path) in
  summary half;
  print_s
    [%sexp
      (Journal_source.load ~symbol:(Exchange_core.Symbol.of_string "DOGE") path
       |> Or_error.is_error
       : bool)];
  Core_unix.unlink path;
  [%expect
    {|
    ((label BTC) (trades 224) (books 600) (increases 735) (decreases 821)
     (orders (((placed 1900) (cancelled 1599) (modified 0)))))
    ((label BTC) (trades 110) (books 299) (increases 384) (decreases 411)
     (orders (((placed 963) (cancelled 783) (modified 0)))))
    true
    |}];
  return ()
;;

let instrument = Md.Instrument.create Hyperliquid "BTC"
let t0 = Time_ns.of_string_with_utc_offset "2026-10-12 13:34:00Z"
let at s = Time_ns.add t0 (Time_ns.Span.of_sec s)

let level p s : Md.L2_update.Level.t =
  { price = Md.Price.of_string p; size = Md.Size.of_string s }
;;

let l2 ?(kind = Md.L2_update.Kind.Snapshot) s bids asks : Md.Event.t =
  L2 { instrument; exch_ts = at s; recv_ts = at s; kind; bids; asks }
;;

let trade s p z side : Md.Event.t =
  Trade
    { instrument
    ; exch_ts = at s
    ; recv_ts = at s
    ; price = Md.Price.of_string p
    ; size = Md.Size.of_string z
    ; side
    ; trade_id = Float.to_string s
    }
;;

let%expect_test "a norm directory, windowed by venue time" =
  let dir = Filename_unix.temp_dir "scorecard" "norm" in
  let w = Md.Event_log.Writer.create ~dir () in
  List.iter
    ~f:(Md.Event_log.Writer.append w)
    [ l2 0. [ level "99" "1"; level "98" "2" ] [ level "101" "1"; level "102" "2" ]
    ; trade 1. "101" "0.5" Buy
    ; l2 ~kind:Delta 1. [] [ level "101" "0.5" ]
    ; trade 2. "99" "1" Sell
    ; l2 ~kind:Delta 2. [ level "99" "0"; level "98.5" "3" ] []
    ; trade 70. "98.5" "1" Sell
    ];
  let%bind () = Md.Event_log.Writer.close w in
  let%bind all = Norm_source.load ~dir instrument ~from:t0 ~to_:(at 3600.) () in
  summary all;
  print_s [%sexp (all.books : Series.Book.t array)];
  let%bind first_minute = Norm_source.load ~dir instrument ~from:t0 ~to_:(at 60.) () in
  summary first_minute;
  print_s [%sexp (Norm_source.dates ~from:(at (-1.)) ~to_:(at 60.) : Date.t list)];
  [%expect
    {|
    ((label hyperliquid:BTC) (trades 3) (books 3) (increases 1) (decreases 2)
     (orders ()))
    (((ts 1791812040000000000) (bid 99) (ask 101) (depth 600))
     ((ts 1791812041000000000) (bid 99) (ask 101) (depth 549.5))
     ((ts 1791812042000000000) (bid 98.5) (ask 101) (depth 746)))
    ((label hyperliquid:BTC) (trades 2) (books 3) (increases 1) (decreases 2)
     (orders ()))
    (2026-10-12)
    |}];
  return ()
;;

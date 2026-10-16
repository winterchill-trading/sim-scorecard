open! Core
open! Async
module Md = Market_data

let dates ~from ~to_ =
  if Time_ns.( >= ) from to_
  then []
  else (
    let date t =
      Date.of_time (Time_ns.to_time_float_round_nearest t) ~zone:Time_float.Zone.utc
    in
    let first = date from
    and last = date (Time_ns.sub to_ Time_ns.Span.nanosecond) in
    Date.dates_between ~min:first ~max:last)
;;

let existing paths = Deferred.List.filter paths ~how:`Sequential ~f:Sys.file_exists_exn
let ns t = Time_ns.to_int_ns_since_epoch t
let px p = Md.Price.to_float p
let size s = Md.Size.to_float s

let levels l =
  List.map l ~f:(fun (lv : Md.L2_update.Level.t) -> px lv.price, size lv.size)
;;

let load ?(depth = 10) ?label ~dir instrument ~from ~to_ () =
  let label = Option.value label ~default:(Md.Instrument.to_string instrument) in
  let b = Series.Builder.create ~label ~depth in
  let dates = dates ~from ~to_ in
  let paths stream = List.map dates ~f:(Md.Event_log.path ~dir instrument stream) in
  let%bind l2 = existing (paths L2) in
  let%bind trades = existing (paths Trades) in
  let%bind bbo = if List.is_empty l2 then existing (paths Bbo) else return [] in
  let in_window ts = Time_ns.( >= ) ts from && Time_ns.( < ) ts to_ in
  let book = ref Md.L2_book.empty in
  let%map () =
    Pipe.iter_without_pushback
      (Md.Event_log.read_merged (l2 @ trades @ bbo))
      ~f:(fun (event : Md.Event.t) ->
        match event with
        | Trade t ->
          if in_window t.exch_ts
          then
            Series.Builder.add_trade
              b
              { ts = ns t.exch_ts; px = px t.price; size = size t.size; side = t.side }
        | L2 u ->
          (* Every update goes into the book; only samples inside the window count. *)
          book := Md.L2_book.apply !book u;
          if in_window u.exch_ts && Md.L2_book.has_snapshot !book
          then
            Series.Builder.add_levels
              b
              ~ts:(ns u.exch_ts)
              ~bids:(levels (Md.L2_book.bids ~depth !book))
              ~asks:(levels (Md.L2_book.asks ~depth !book))
        | Bbo q ->
          if in_window q.exch_ts
          then
            Series.Builder.add_bbo
              b
              ~ts:(ns q.exch_ts)
              ~bid:(px q.bid_price)
              ~bid_size:(size q.bid_size)
              ~ask:(px q.ask_price)
              ~ask_size:(size q.ask_size)
        | Funding _ -> ())
  in
  Series.Builder.finish b
;;

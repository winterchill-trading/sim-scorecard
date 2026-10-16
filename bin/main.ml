open! Core
open! Async
open Sim_scorecard
module Md = Market_data

(* A time is an ISO 8601 time with a zone ("2026-10-12T13:34:00Z"), or for an engine
   journal an offset of its clock ("90s"), whose runs often start at zero. *)
let time_arg =
  Command.Arg_type.create (fun s ->
    match Time_ns.Span.of_string s with
    | span -> Time_ns.of_span_since_epoch span
    | exception _ -> Time_ns.of_string_with_utc_offset s)
;;

let band_arg =
  Command.Arg_type.create (fun s ->
    match String.lsplit2 s ~on:'=' with
    | Some (fact, band) -> Fact.Id.of_string fact, Float.of_string band
    | None -> failwithf "expected FACT=MAX_DISTANCE, got %s" s ())
;;

let instrument_arg = Command.Arg_type.create Md.Instrument.of_string
let ns t = Time_ns.to_int_ns_since_epoch t

let is_journal path =
  match%map Sys.is_file path with
  | `Yes -> true
  | `No | `Unknown -> false
;;

let load_norm ~depth ~dir instrument ~from ~to_ =
  let%bind window =
    match from, to_ with
    | Some f, Some t -> return (Some (f, t))
    | _ ->
      let%map available = Norm_source.available_window ~dir instrument in
      Option.map available ~f:(fun (f, t) ->
        Option.value from ~default:f, Option.value to_ ~default:t)
  in
  match window with
  | None -> failwithf !"no event logs for %{Md.Instrument} under %s" instrument dir ()
  | Some (from, to_) -> Norm_source.load ~depth ~dir instrument ~from ~to_ ()
;;

let compare_command =
  Command.async
    ~summary:"Score a simulator run against recorded data over a window"
    ~readme:(fun () ->
      "-sim is an engine input journal (replayed with the default exchange \
       configuration) or a recorder data directory holding the simulator's norm logs. \
       -recorded is a recorder data directory. Writes the markdown table to stdout \
       unless -markdown is given.")
    (let%map_open.Command sim =
       flag "-sim" (required string) ~doc:"PATH journal file or norm data directory"
     and sim_symbol =
       flag
         "-sim-symbol"
         (optional string)
         ~doc:
           "SYM journal: engine symbol (default BTC); norm: venue:SYMBOL (default \
            -instrument)"
     and sim_from = flag "-sim-from" (optional time_arg) ~doc:"TIME start on the sim side"
     and sim_to = flag "-sim-to" (optional time_arg) ~doc:"TIME end on the sim side"
     and sim_journal =
       flag
         "-sim-journal"
         (optional string)
         ~doc:"FILE the simulator's input journal, for exact order and cancel counts"
     and recorded = flag "-recorded" (required string) ~doc:"DIR recorder data directory"
     and instrument =
       flag
         "-instrument"
         (required instrument_arg)
         ~doc:"VENUE:SYMBOL recorded instrument, e.g. hyperliquid:BTC"
     and from = flag "-from" (optional time_arg) ~doc:"TIME start of the recorded window"
     and to_ = flag "-to" (optional time_arg) ~doc:"TIME end of the recorded window"
     and interval_ms =
       flag
         "-interval-ms"
         (optional_with_default 1000 int)
         ~doc:"MS return sampling grid (default 1000)"
     and depth =
       flag
         "-depth"
         (optional_with_default 10 int)
         ~doc:"N book levels per side (default 10)"
     and bands =
       flag "-band" (listed band_arg) ~doc:"FACT=MAX override a fact's pass band"
     and json = flag "-json" (optional string) ~doc:"FILE write the scorecard as JSON"
     and markdown =
       flag "-markdown" (optional string) ~doc:"FILE write the markdown table"
     in
     fun () ->
       let%bind sim_series =
         match%bind is_journal sim with
         | true ->
           let symbol =
             Exchange_core.Symbol.of_string (Option.value sim_symbol ~default:"BTC")
           in
           return
             (ok_exn
                (Journal_source.load
                   ~depth
                   ?from:(Option.map sim_from ~f:ns)
                   ?to_:(Option.map sim_to ~f:ns)
                   ~label:
                     (sprintf
                        "%s (%s)"
                        (Filename.basename sim)
                        (Exchange_core.Symbol.to_string symbol))
                   ~symbol
                   sim))
         | false ->
           let sim_instrument =
             Option.value_map sim_symbol ~default:instrument ~f:Md.Instrument.of_string
           in
           load_norm ~depth ~dir:sim sim_instrument ~from:sim_from ~to_:sim_to
       in
       let sim_series =
         match sim_journal with
         | None -> sim_series
         | Some path ->
           let symbol =
             match sim_symbol with
             | Some s when not (String.mem s ':') -> s
             | Some s -> Md.Symbol.to_string (Md.Instrument.of_string s).symbol
             | None -> Md.Symbol.to_string instrument.symbol
           in
           { sim_series with
             orders =
               Some
                 (ok_exn
                    (Journal_source.orders_of_file
                       ~symbol:(Exchange_core.Symbol.of_string symbol)
                       path))
           }
       in
       let%bind recorded_series = load_norm ~depth ~dir:recorded instrument ~from ~to_ in
       let config =
         { Fact.Config.default with interval = Time_ns.Span.of_int_ms interval_ms; bands }
       in
       let card = Scorecard.create ~config ~sim:sim_series ~recorded:recorded_series () in
       Option.iter json ~f:(fun path ->
         Out_channel.write_all
           path
           ~data:(Yojson.Safe.pretty_to_string (Scorecard.to_json card) ^ "\n"));
       (match markdown with
        | Some path -> Out_channel.write_all path ~data:(Scorecard.to_markdown card)
        | None -> print_string (Scorecard.to_markdown card));
       return ())
;;

let facts_command =
  Command.basic
    ~summary:"List the facts, their metric and default band"
    (Command.Param.return (fun () ->
       List.iter Fact.Id.all ~f:(fun id ->
         (* Core's printf: Async's writer is never flushed in a non-Async command. *)
         Core.printf
           "%-24s %-14s %.3f  %s\n"
           (Fact.Id.to_string id)
           (Fact.Metric.to_string (Fact.Config.metric id))
           (Fact.Config.band Fact.Config.default id)
           (Fact.Id.description id))))
;;

let () =
  Command_unix.run
    (Command.group
       ~summary:"Compare simulator runs with recorded market data"
       [ "compare", compare_command; "facts", facts_command ])
;;

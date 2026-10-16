open! Core
open! Exchange_core
open! Exchange_core_engine

let in_window ?from ?to_ ts =
  Option.value_map from ~default:true ~f:(fun f -> ts >= f)
  && Option.value_map to_ ~default:true ~f:(fun t -> ts < t)
;;

let orders ?from ?to_ ~symbol inputs =
  let is s = Symbol.equal s symbol in
  (* The clock is only known through [Step] inputs: a request counts at the time of the
     last step before it. *)
  let now = ref 0 in
  List.fold
    inputs
    ~init:{ Series.Orders.placed = 0; cancelled = 0; modified = 0 }
    ~f:(fun (acc : Series.Orders.t) (input : Input.t) ->
      let inside = in_window ?from ?to_ !now in
      match input with
      | Step { now = t } ->
        now := t;
        acc
      | (Place { request; _ } | Place_trigger { request; _ })
        when inside && is request.symbol -> { acc with placed = acc.placed + 1 }
      | (Cancel { symbol = s; _ } | Cancel_by_client_order_id { symbol = s; _ })
        when inside && is s -> { acc with cancelled = acc.cancelled + 1 }
      | (Modify { request; _ } | Modify_trigger { request; _ })
        when inside && is request.symbol -> { acc with modified = acc.modified + 1 }
      | _ -> acc)
;;

let orders_of_file ?from ?to_ ~symbol path =
  Or_error.map (Journal.load path) ~f:(fun inputs -> orders ?from ?to_ ~symbol inputs)
;;

let levels l =
  List.map l ~f:(fun (lv : L2.Level.t) -> Price.to_float lv.px, Size.to_float lv.sz)
;;

let load ?config ?(depth = 10) ?from ?to_ ?label ~symbol path =
  let open Or_error.Let_syntax in
  let%bind header, inputs = Journal.load_with_header path in
  let ex =
    Exchange.create
      ?config
      ~self_trade:header.self_trade
      ?book_liquidation:header.book_liquidation
      ()
  in
  let%map () =
    match Exchange.instrument ex symbol with
    | Some _ -> Ok ()
    | None ->
      Or_error.error_s
        [%message "Symbol not in the replay configuration" (symbol : Symbol.t)]
  in
  let label = Option.value label ~default:(Symbol.to_string symbol) in
  let b = Series.Builder.create ~label ~depth in
  let in_window = in_window ?from ?to_ in
  List.iter inputs ~f:(fun (input : Input.t) ->
    Exchange.apply ex input;
    List.iter (Exchange.drain_events ex) ~f:(function
      | Fill { fill; _ } when Symbol.equal fill.symbol symbol && in_window fill.time ->
        Series.Builder.add_trade
          b
          { ts = fill.time
          ; px = Price.to_float fill.px
          ; size = Size.to_float fill.sz
          ; side = fill.taker_side
          }
      | _ -> ());
    match input with
    | Step { now } when in_window now ->
      Option.iter (Exchange.l2 ~n_levels:depth ex symbol) ~f:(fun (l2 : L2.t) ->
        Series.Builder.add_levels b ~ts:now ~bids:(levels l2.bids) ~asks:(levels l2.asks))
    | _ -> ());
  Series.Builder.set_orders b (orders ?from ?to_ ~symbol inputs);
  Series.Builder.finish b
;;

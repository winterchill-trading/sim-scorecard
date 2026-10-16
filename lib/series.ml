open! Core
open! Exchange_core

module Trade = struct
  type t =
    { ts : int
    ; px : float
    ; size : float
    ; side : Side.t
    }
  [@@deriving sexp_of]
end

module Book = struct
  type t =
    { ts : int
    ; bid : float
    ; ask : float
    ; depth : float
    }
  [@@deriving sexp_of]

  let mid t = (t.bid +. t.ask) /. 2.
  let spread_bps t = (t.ask -. t.bid) /. mid t *. 10_000.
end

module Orders = struct
  type t =
    { placed : int
    ; cancelled : int
    ; modified : int
    }
  [@@deriving sexp_of]
end

type t =
  { label : string
  ; trades : Trade.t array
  ; books : Book.t array
  ; level_increases : int
  ; level_decreases : int
  ; decreased_size : float
  ; orders : Orders.t option
  }
[@@deriving sexp_of]

let span t =
  let first_last a ~ts =
    if Array.is_empty a then None else Some (ts a.(0), ts (Array.last_exn a))
  in
  let trades = first_last t.trades ~ts:(fun (x : Trade.t) -> x.ts) in
  let books = first_last t.books ~ts:(fun (x : Book.t) -> x.ts) in
  match trades, books with
  | None, x | x, None -> x
  | Some (a, b), Some (c, d) -> Some (Int.min a c, Int.max b d)
;;

type series = t

module Builder = struct
  type t =
    { label : string
    ; depth : int
    ; trades : Trade.t Queue.t
    ; books : Book.t Queue.t
    ; mutable prev : ((float * float) list * (float * float) list) option
    ; mutable increases : int
    ; mutable decreases : int
    ; mutable decreased_size : float
    ; mutable orders : Orders.t option
    }

  let create ~label ~depth =
    { label
    ; depth
    ; trades = Queue.create ()
    ; books = Queue.create ()
    ; prev = None
    ; increases = 0
    ; decreases = 0
    ; decreased_size = 0.
    ; orders = None
    }
  ;;

  let add_trade t trade = Queue.enqueue t.trades trade
  let notional levels = List.sum (module Float) levels ~f:(fun (px, size) -> px *. size)

  let add_book t ~ts ~bid ~ask ~depth =
    if Float.( > ) bid 0. && Float.( < ) bid ask
    then Queue.enqueue t.books { Book.ts; bid; ask; depth }
  ;;

  (* Size changes of one side between two samples, over the price range both cover:
     [inside px] says whether a price lies within it. *)
  let count_side t ~old ~new_ ~inside =
    let table = Float.Table.create () in
    List.iter old ~f:(fun (px, size) ->
      if inside px then Hashtbl.set table ~key:px ~data:(size, 0.));
    List.iter new_ ~f:(fun (px, size) ->
      if inside px
      then
        Hashtbl.update table px ~f:(function
          | None -> 0., size
          | Some (o, _) -> o, size));
    Hashtbl.iter table ~f:(fun (o, n) ->
      if Float.( > ) n o
      then t.increases <- t.increases + 1
      else if Float.( < ) n o
      then (
        t.decreases <- t.decreases + 1;
        t.decreased_size <- t.decreased_size +. (o -. n)))
  ;;

  let worst levels ~default =
    match List.last levels with
    | Some (px, _) -> px
    | None -> default
  ;;

  let add_levels t ~ts ~bids ~asks =
    let bids = List.take bids t.depth
    and asks = List.take asks t.depth in
    (match t.prev with
     | None -> ()
     | Some (old_bids, old_asks) ->
       (* Bids: prices at or above the higher of the two deepest bids; asks mirrored. *)
       let bid_floor =
         Float.max
           (worst old_bids ~default:Float.infinity)
           (worst bids ~default:Float.infinity)
       in
       let ask_ceiling =
         Float.min
           (worst old_asks ~default:Float.neg_infinity)
           (worst asks ~default:Float.neg_infinity)
       in
       count_side t ~old:old_bids ~new_:bids ~inside:(fun px -> Float.( >= ) px bid_floor);
       count_side t ~old:old_asks ~new_:asks ~inside:(fun px ->
         Float.( <= ) px ask_ceiling));
    t.prev <- Some (bids, asks);
    match bids, asks with
    | (bid, _) :: _, (ask, _) :: _ ->
      add_book t ~ts ~bid ~ask ~depth:(notional bids +. notional asks)
    | _ -> ()
  ;;

  let add_bbo t ~ts ~bid ~bid_size ~ask ~ask_size =
    add_book t ~ts ~bid ~ask ~depth:((bid *. bid_size) +. (ask *. ask_size))
  ;;

  let set_orders t orders = t.orders <- Some orders

  let finish t : series =
    (* Sources deliver by receive time; venue timestamps can be slightly out of order. *)
    let by_ts q ~ts =
      let a = Queue.to_array q in
      Array.stable_sort a ~compare:(fun x y -> Int.compare (ts x) (ts y));
      a
    in
    { label = t.label
    ; trades = by_ts t.trades ~ts:(fun (x : Trade.t) -> x.ts)
    ; books = by_ts t.books ~ts:(fun (x : Book.t) -> x.ts)
    ; level_increases = t.increases
    ; level_decreases = t.decreases
    ; decreased_size = t.decreased_size
    ; orders = t.orders
    }
  ;;
end

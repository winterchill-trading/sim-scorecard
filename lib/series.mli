(** What the scorecard observes of one market over a window, the same whether it comes
    from a recorded venue or from a simulator: trades, two-sided book samples, and counts
    of level changes in the book (the order-flow proxy available from L2 data on both
    sides).

    Times are nanoseconds; prices and sizes are floats, for statistics only. *)

open! Core
open! Exchange_core

module Trade : sig
  type t =
    { ts : int
    ; px : float
    ; size : float
    ; side : Side.t (** aggressor *)
    }
  [@@deriving sexp_of]
end

module Book : sig
  type t =
    { ts : int
    ; bid : float
    ; ask : float
    ; depth : float (** quote notional of both sides over the top levels *)
    }
  [@@deriving sexp_of]

  val mid : t -> float

  (** [(ask - bid) / mid] in basis points. *)
  val spread_bps : t -> float
end

(** Exact order counts, from a simulator's input journal. *)
module Orders : sig
  type t =
    { placed : int (** orders sent, trigger orders included *)
    ; cancelled : int (** cancel requests *)
    ; modified : int
    }
  [@@deriving sexp_of]
end

type t =
  { label : string
  ; trades : Trade.t array (** by time *)
  ; books : Book.t array (** by time; two-sided books only *)
  ; level_increases : int (** price levels whose size grew between book samples *)
  ; level_decreases : int (** price levels whose size shrank *)
  ; decreased_size : float (** total size removed from levels *)
  ; orders : Orders.t option
  }
[@@deriving sexp_of]

(** First and last observation time, if any. *)
val span : t -> (int * int) option

module Builder : sig
  type series := t
  type t

  (** [depth] is the number of levels per side kept for depth and change counting. *)
  val create : label:string -> depth:int -> t

  val add_trade : t -> Trade.t -> unit

  (** A book state, levels [(price, size)] best first (bids descending, asks ascending).
      Level changes are counted against the previous book, over the price range both books
      cover, so levels entering or leaving the top [depth] are not counted. *)
  val add_levels
    :  t
    -> ts:int
    -> bids:(float * float) list
    -> asks:(float * float) list
    -> unit

  (** A top-of-book sample without levels: no change counting, depth from the top level. *)
  val add_bbo
    :  t
    -> ts:int
    -> bid:float
    -> bid_size:float
    -> ask:float
    -> ask_size:float
    -> unit

  val set_orders : t -> Orders.t -> unit
  val finish : t -> series
end

(** Observations of one symbol from an exchange-core input journal
    ({!Exchange_core_engine.Journal}), by replaying it.

    The replay needs the journalled exchange's configuration: the default
    ({!Exchange_core_engine.Exchange.Config.default}) fits journals of [Stepped] and
    [Market_sim] runs on a default exchange. A venue simulator with its own universe
    (fees, ticks, margin tiers) replays faithfully only with its own configuration; for
    those, record the simulator with the recorder and score its norm directory, and pass
    the journal to {!orders} for exact order counts.

    Trades are the fills in the symbol, timed by the exchange clock. The book is sampled
    after every [Step] input, the simulator's clock tick. *)

open! Core
open! Exchange_core
open! Exchange_core_engine

val load
  :  ?config:Exchange.Config.t
  -> ?depth:int (** default 10 *)
  -> ?from:int (** exchange clock, nanoseconds; inclusive *)
  -> ?to_:int (** exclusive *)
  -> ?label:string
  -> symbol:Symbol.t
  -> string
  -> Series.t Or_error.t

(** Order requests in [symbol] counted from the inputs alone (no replay, so any
    configuration): placed (orders and trigger orders), cancel requests, modifies. A
    request is timed by the last [Step] before it. *)
val orders : ?from:int -> ?to_:int -> symbol:Symbol.t -> Input.t list -> Series.Orders.t

(** [orders] of a journal file. *)
val orders_of_file
  :  ?from:int
  -> ?to_:int
  -> symbol:Symbol.t
  -> string
  -> Series.Orders.t Or_error.t

(** Observations of one instrument from a directory of normalized event logs, as written
    by the recorder ([<dir>/<venue>/<symbol>/norm/<stream>/<YYYY-MM-DD>.bin], see
    {!Market_data.Event_log}).

    Trades come from the trades stream. Books come from the L2 stream (the book rebuilt
    from snapshots and deltas, sampled after every update once a snapshot has arrived), or
    from the BBO stream when there is no L2 log in the window. Events are timed by the
    venue timestamp ([exch_ts]) and kept when it lies in [\[from, to_)]. *)

open! Core
open! Async

val load
  :  ?depth:int (** levels per side for depth and change counting (default 10) *)
  -> ?label:string
  -> dir:string
  -> Market_data.Instrument.t
  -> from:Time_ns.t
  -> to_:Time_ns.t
  -> unit
  -> Series.t Deferred.t

(** The UTC dates whose files can hold events in [\[from, to_)]. *)
val dates : from:Time_ns.t -> to_:Time_ns.t -> Date.t list

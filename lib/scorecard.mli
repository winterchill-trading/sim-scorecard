(** A comparison of a simulator run with recorded data: every {!Fact} with both values,
    the distance and the verdict, plus what each side contained. The facts are the primary
    result; the pass count is a summary, not a weighted score. *)

open! Core

module Side : sig
  type t =
    { label : string
    ; trades : int
    ; books : int
    ; first : Time_ns.t option
    ; last : Time_ns.t option
    ; orders : Series.Orders.t option (** exact counts, from a journal *)
    }
  [@@deriving sexp_of]

  val of_series : Series.t -> t

  (** Orders placed per trade and cancel requests per order placed, when the counts are
      known. *)
  val exact_ratios : t -> (float * float) option
end

type t =
  { sim : Side.t
  ; recorded : Side.t
  ; config : Fact.Config.t
  ; facts : Fact.t list
  }
[@@deriving sexp_of]

val create : ?config:Fact.Config.t -> sim:Series.t -> recorded:Series.t -> unit -> t
val passed : t -> int

(** Facts with a verdict (pass or fail). *)
val scored : t -> int

(** Non-finite numbers are written as [null]. *)
val to_json : t -> Yojson.Safe.t

(** A markdown table, one row per fact, with a short header on each side. *)
val to_markdown : t -> string

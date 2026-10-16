(** The stylised facts the scorecard compares, each computed the same way on both series.

    Returns are log returns of the mid sampled on a fixed grid ([Config.interval]); book
    distributions (spread, depth) are taken on the same grid, so they are time-weighted.
    Order-to-trade and cancel ratios come from book level changes (an L2 proxy available
    for recorded venues and simulators alike); exact counts from a simulator's journal are
    reported separately by {!Scorecard}. *)

open! Core

module Id : sig
  type t =
    | Return_kurtosis
    (** excess kurtosis of returns (fat tails), compared as the log ratio of raw kurtosis *)
    | Return_acf (** autocorrelation of returns, lags 1..max_lag *)
    | Abs_return_acf (** autocorrelation of absolute returns, lags 1..max_lag *)
    | Vol_clustering (** lag-1 autocorrelation of realised variance per window *)
    | Spread_bps (** relative spread distribution *)
    | Depth (** quote notional over the top levels *)
    | Trade_size (** trade notional distribution *)
    | Inter_trade_time (** milliseconds between trades *)
    | Variance_ratio (** signature plot: variance ratios over horizons *)
    | Aggressor_imbalance_acf
    (** autocorrelation of the per-bucket aggressor volume imbalance *)
    | Order_to_trade (** level additions per trade (L2 proxy) *)
    | Cancel_ratio (** share of removed depth not explained by trades (L2 proxy) *)
  [@@deriving sexp, compare, equal, enumerate]

  (** Snake case, e.g. ["return_kurtosis"]. *)
  val to_string : t -> string

  val of_string : string -> t
  val description : t -> string
end

module Metric : sig
  type t =
    | Ks (** two-sample Kolmogorov-Smirnov statistic, in [0, 1] *)
    | Wasserstein (** Wasserstein-1, in the unit of the samples *)
    | Mean_abs_diff (** mean absolute difference of two curves (lags, horizons) *)
    | Abs_diff
    | Abs_log_ratio (** [|ln (sim / recorded)|]; ln 2 is a factor of two *)
  [@@deriving sexp, compare, equal]

  val to_string : t -> string
end

module Config : sig
  type t =
    { interval : Time_ns.Span.t (** return and book sampling grid *)
    ; max_lag : int
    ; vol_window : int (** returns per realised-variance window *)
    ; horizons : int list (** variance-ratio horizons, in grid steps *)
    ; imbalance_interval : Time_ns.Span.t (** aggressor imbalance buckets *)
    ; min_samples : int (** fewer samples on either side: not scored *)
    ; bands : (Id.t * float) list (** maximum distance to pass, overriding defaults *)
    }
  [@@deriving sexp]

  (** 1 s grid, lags 1..10, 10-return windows, horizons 2, 5, 10, 30, 1 s imbalance
      buckets, 10 samples minimum, default bands. *)
  val default : t

  val band : t -> Id.t -> float
  val metric : Id.t -> Metric.t
end

module Verdict : sig
  type t =
    | Pass
    | Fail
    | Insufficient (** too few samples, or a degenerate (constant) series *)
  [@@deriving sexp, compare, equal]

  val to_string : t -> string
end

type t =
  { id : Id.t
  ; sim : float (** the fact's headline value on the simulator *)
  ; recorded : float
  ; metric : Metric.t
  ; distance : float
  ; band : float
  ; verdict : Verdict.t
  ; w1 : float
  (** for distribution facts, the Wasserstein-1 distance as well, in the unit of the
      samples; [nan] for the others *)
  ; n_sim : int (** samples behind the value *)
  ; n_recorded : int
  }
[@@deriving sexp_of]

val compute : Config.t -> sim:Series.t -> recorded:Series.t -> t list

(** {2 Building blocks, exposed for tests} *)

(** Grid samples of the book: the last sample at or before each grid time. *)
val grid_books : Series.t -> interval:Time_ns.Span.t -> Series.Book.t array

(** Log returns of the mid between consecutive grid samples. *)
val returns : Series.t -> interval:Time_ns.Span.t -> float array

(** Aggressor imbalance [(buy - sell) / (buy + sell)] volume per bucket, 0 for buckets
    without trades, over the span of the trades. *)
val imbalances : Series.t -> interval:Time_ns.Span.t -> float array

(** Sample statistics used by the scorecard. Every function takes a [float array] sample
    and returns [Float.nan] when the sample is too small for the statistic (or degenerate,
    such as a constant series for a correlation). *)

open! Core

val mean : float array -> float

(** Population variance (divides by [n]). *)
val variance : float array -> float

(** Excess kurtosis, [m4 / m2^2 - 3]: 0 for a normal distribution, positive for fat tails. *)
val excess_kurtosis : float array -> float

(** Sample autocorrelation at [lag], [sum (x_t - m)(x_{t+lag} - m) / sum (x_t - m)^2]. *)
val acf : float array -> lag:int -> float

(** [acf] at lags [1 .. max_lag]. *)
val acf_lags : float array -> max_lag:int -> float array

(** Linear-interpolated quantile, [q] in [0, 1]. *)
val quantile : float array -> float -> float

val median : float array -> float

(** Two-sample Kolmogorov-Smirnov statistic: the largest gap between the two empirical
    distribution functions, in [0, 1]. *)
val ks : float array -> float array -> float

(** Wasserstein-1 (earth mover's) distance between the two empirical distributions, in the
    unit of the samples. *)
val wasserstein1 : float array -> float array -> float

(** [(x - mean) / sd]; empty when the standard deviation is zero. *)
val standardize : float array -> float array

(** Variance ratio at horizon [k] from one-step returns: the variance of non-overlapping
    sums of [k] returns over [k] times the one-step variance. 1 for a random walk, below 1
    for mean reversion (bid-ask bounce), above 1 for trending. *)
val variance_ratio : float array -> k:int -> float

(** Mean of [|a_i - b_i|] over positions where both are finite. *)
val mean_abs_diff : float array -> float array -> float

open! Core

let finite = Float.is_finite
let n_of a = Array.length a

let mean a =
  let n = n_of a in
  if n = 0 then Float.nan else Array.sum (module Float) a ~f:Fn.id /. Float.of_int n
;;

let central_moment a ~m ~k =
  let n = n_of a in
  Array.sum (module Float) a ~f:(fun x -> Float.int_pow (x -. m) k) /. Float.of_int n
;;

let variance a = if n_of a < 2 then Float.nan else central_moment a ~m:(mean a) ~k:2

let excess_kurtosis a =
  if n_of a < 4
  then Float.nan
  else (
    let m = mean a in
    let m2 = central_moment a ~m ~k:2 in
    if Float.( <= ) m2 0.
    then Float.nan
    else (central_moment a ~m ~k:4 /. (m2 *. m2)) -. 3.)
;;

let acf a ~lag =
  let n = n_of a in
  if lag < 1 || n < lag + 2
  then Float.nan
  else (
    let m = mean a in
    let denom = Array.sum (module Float) a ~f:(fun x -> (x -. m) *. (x -. m)) in
    if Float.( <= ) denom 0.
    then Float.nan
    else (
      let num = ref 0. in
      for i = 0 to n - 1 - lag do
        num := !num +. ((a.(i) -. m) *. (a.(i + lag) -. m))
      done;
      !num /. denom))
;;

let acf_lags a ~max_lag = Array.init max_lag ~f:(fun i -> acf a ~lag:(i + 1))

let sorted a =
  let a = Array.filter a ~f:finite in
  Array.sort a ~compare:Float.compare;
  a
;;

let quantile_sorted s q =
  let n = n_of s in
  if n = 0
  then Float.nan
  else (
    let pos = q *. Float.of_int (n - 1) in
    let i = Float.iround_down_exn pos in
    if i >= n - 1
    then s.(n - 1)
    else (
      let frac = pos -. Float.of_int i in
      s.(i) +. (frac *. (s.(i + 1) -. s.(i)))))
;;

let quantile a q = quantile_sorted (sorted a) q
let median a = quantile a 0.5

let ks a b =
  let a = sorted a
  and b = sorted b in
  let na = n_of a
  and nb = n_of b in
  if na = 0 || nb = 0
  then Float.nan
  else (
    (* Walk both sorted samples; ties advance together so equal values count as one step. *)
    let i = ref 0
    and j = ref 0
    and d = ref 0. in
    while !i < na && !j < nb do
      let x = Float.min a.(!i) b.(!j) in
      while !i < na && Float.( = ) a.(!i) x do
        incr i
      done;
      while !j < nb && Float.( = ) b.(!j) x do
        incr j
      done;
      let fa = Float.of_int !i /. Float.of_int na
      and fb = Float.of_int !j /. Float.of_int nb in
      d := Float.max !d (Float.abs (fa -. fb))
    done;
    !d)
;;

let wasserstein1 a b =
  let a = sorted a
  and b = sorted b in
  if n_of a = 0 || n_of b = 0
  then Float.nan
  else (
    (* Integral of |F_a^-1(u) - F_b^-1(u)| du over a common grid of quantiles. *)
    let steps = Int.max 1000 (Int.max (n_of a) (n_of b)) in
    let total = ref 0. in
    for k = 0 to steps - 1 do
      let u = (Float.of_int k +. 0.5) /. Float.of_int steps in
      total := !total +. Float.abs (quantile_sorted a u -. quantile_sorted b u)
    done;
    !total /. Float.of_int steps)
;;

let standardize a =
  let a = Array.filter a ~f:finite in
  let m = mean a in
  let v = variance a in
  if (not (finite v)) || Float.( <= ) v 0.
  then [||]
  else (
    let sd = Float.sqrt v in
    Array.map a ~f:(fun x -> (x -. m) /. sd))
;;

let variance_ratio r ~k =
  let n = n_of r in
  let v1 = variance r in
  if k < 1 || n / k < 2 || (not (finite v1)) || Float.( <= ) v1 0.
  then Float.nan
  else (
    let sums =
      Array.init (n / k) ~f:(fun b ->
        let s = ref 0. in
        for i = b * k to (b * k) + k - 1 do
          s := !s +. r.(i)
        done;
        !s)
    in
    variance sums /. (Float.of_int k *. v1))
;;

let mean_abs_diff a b =
  let n = Int.min (n_of a) (n_of b) in
  let total = ref 0.
  and count = ref 0 in
  for i = 0 to n - 1 do
    if finite a.(i) && finite b.(i)
    then (
      total := !total +. Float.abs (a.(i) -. b.(i));
      incr count)
  done;
  if !count = 0 then Float.nan else !total /. Float.of_int !count
;;

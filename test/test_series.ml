open! Core
open Sim_scorecard

let show (s : Series.t) =
  print_s
    [%sexp
      { books = (Array.length s.books : int)
      ; increases = (s.level_increases : int)
      ; decreases = (s.level_decreases : int)
      ; decreased_size = (s.decreased_size : float)
      ; span = (Series.span s : (int * int) option)
      }]
;;

let%expect_test "level changes are counted over the range both books cover" =
  let b = Series.Builder.create ~label:"t" ~depth:3 in
  Series.Builder.add_levels
    b
    ~ts:1
    ~bids:[ 99., 1.; 98., 1.; 97., 1.; 96., 5. ]
    ~asks:[ 101., 1.; 102., 1.; 103., 1. ];
  (* Bid 99 shrinks, 98 grows, 97 leaves the window when 98.5 arrives (not counted: below
     the new deepest bid 98); ask 101 is taken, 104 enters at the edge. *)
  Series.Builder.add_levels
    b
    ~ts:2
    ~bids:[ 99., 0.5; 98.5, 2.; 98., 3. ]
    ~asks:[ 102., 1.; 103., 1.; 104., 1. ];
  show (Series.Builder.finish b);
  [%expect
    {| ((books 2) (increases 2) (decreases 2) (decreased_size 1.5) (span ((1 2)))) |}]
;;

let%expect_test "crossed or one-sided books are not sampled" =
  let b = Series.Builder.create ~label:"t" ~depth:5 in
  Series.Builder.add_levels b ~ts:1 ~bids:[] ~asks:[ 101., 1. ];
  Series.Builder.add_bbo b ~ts:2 ~bid:101. ~bid_size:1. ~ask:100. ~ask_size:1.;
  Series.Builder.add_bbo b ~ts:3 ~bid:100. ~bid_size:2. ~ask:101. ~ask_size:1.;
  Series.Builder.add_trade b { ts = 0; px = 100.; size = 1.; side = Buy };
  let s = Series.Builder.finish b in
  show s;
  print_s [%sexp (s.books : Series.Book.t array)];
  printf "%.2f\n" (Series.Book.spread_bps s.books.(0));
  [%expect
    {|
    ((books 1) (increases 0) (decreases 0) (decreased_size 0) (span ((0 3))))
    (((ts 3) (bid 100) (ask 101) (depth 301)))
    99.50
    |}]
;;

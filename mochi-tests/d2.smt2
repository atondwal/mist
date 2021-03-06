(set-logic HORN)
(set-info :source |
  Benchmark: /home/atondwal/src/mist/mochi-tests/d2.ml
  Generated by MoCHi
|)
(set-info :status unknown)
(declare-fun |fail_15[0:0]| ( Int) Bool)
(declare-fun |app[0:0][0:0]| ( Int) Bool)
(declare-fun |app[0:1]| ( Int) Bool)
(assert (not (exists ((x0 Int)) (|fail_15[0:0]| x0))))
(assert (forall ((x0 Int)(x2 Int)) (=> (|app[0:0][0:0]| x2) (|fail_15[0:0]| x0))))
(assert (forall ((x1 Int)) (=> (|app[0:1]| x1) (|app[0:0][0:0]| x1))))
(assert (forall ((x0 Int)) (|app[0:1]| x0)))
(check-sat)
(get-model)
(exit)

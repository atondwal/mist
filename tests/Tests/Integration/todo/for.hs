for as rforall a, b.
  s:(Set >Int) ~>
  (set:(Set >Int) ~>
   x:a ->
   SetST
   <{v:Set >Int | v == set}
   >{v:Set >Int | setSubset set v}
   >b) ->
  List >a ->
  SetST
    <{v:Set >Int | v == s}
    >{v:Set >Int | setSubset s v}
    >b
-- We can implement for using Lists (see append.hs)
for = 0

f as forall a. fs:(Set >Int) ~> x:a -> SetST <{v:Set >Int | v == fs} >{v:Set >Int | setSubset fs v} >Int
f = 0

foo :: foos:(Set >Int) ~> acts:(List >Int) -> SetST <{v:Set >Int | v == foos} >{v:Set >Int | setSubset foos v} >Int
foo = \acts -> for f acts

pure as rforall a. x:a -> List >a
pure = 0

baz :: s:(Set >Int) ~> Int -> SetST <{v:Set >Int | v == s} >{v:Set >Int | setSubset s v} >Int
baz = \i -> for baz (pure i)

bar :: s:(Set >Int) ~> cur:{v:Int | v ∈ s} -> SetST <{v:Set >Int | v == s} >{v:Set >Int | setSubset s v} >Int
bar = \i -> for bar (pure i)

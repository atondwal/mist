-- tick and tock with session types in Mist

-- Message -> State -> State
measure updateRecv :: Int -> Int -> Int
measure updateSend :: Int -> Int -> Int

undefined as rforall a. a
undefined = 0

assert :: {v:Bool | v} -> Unit
assert = \tru -> Unit

unreachable :: forall s,t,p,q. {v:Int | False} -> ST <p >q >Int
unreachable = undefined

-- unreachable :: forall s,t,p,q. Int -> ST <p >q >Int
-- unreachable = undefined

----------------------------------------------------------------------------
-- | The ST Monad ----------------------------------------------------------
----------------------------------------------------------------------------
bind :: rforall a, b, p, q, r, s, t, u.
  ST <p >q >a ->
  (x:a -> ST <q >r >b) ->
  ST <p >r >b
bind = undefined

pure :: rforall a, p, q, s, t. x:a -> ST <p >q >a
pure = undefined

thenn :: rforall a, b, p, q, r, s, t, u.
  n:Int ~> m:Int ~>
  ST <p >q >a ->
  ST <q >r >b ->
  ST <p >r >b
thenn = \f g -> bind f (\underscore -> g)

fmap :: rforall a, b, p, q, s, t.
  n:Int ~>
  (underscore:a -> b) ->
  ST <p >q >a ->
  ST <p >q >b
fmap = \f x -> bind x (\xx -> pure (f xx))

----------------------------------------------------------------------------
-- | State Space
----------------------------------------------------------------------------

-- States
stale       :: { v : Int | v = 2 }
stale       =  2
error       :: { v : Int | v = 1 }
error       =  1
good        :: { v : Int | v = 3 }
good        =  3
done        :: { v : Int | v = 4 }
done        =  4

-----------------------------------------------------------------------------
-- | API for Channels, and sending things
-----------------------------------------------------------------------------
chan :: rforall a.
  n:Int ~>
  m : (Map <Int >Int) ~>
  ST <{v:Map <Int >Int | v == m}
     >{v:Map <Int >Int | v == store m n good}
     >{v:Int | v == n}
chan = undefined

-- nextPage :: m ~> c:{v:Int|select m v = good} -> c' <~ m':{v| select c' m = good \/ select c' m = done} <~ ST <{m} >{m'} >(String,c')
nextPage as rforall p,q,a.
  m : (Map <Int >Int) ~>
  token : {v: Int | select m v == good} ->
    ( mm : (Map <Int >Int) ~>
      tok : Int ~>
      (ST <{v:Map <Int >Int | v == m}
         >{v:Map <Int >Int | v = mm}
         >{v:Int | (((select mm v) = good) \/ ((select mm v) = done)) /\ (v = tok)}) ->
      ST <p >q >a)
   -> ST <p >q >a
nextPage = undefined

----------------------------------------------------------------------------
-- loop :: m ~> m' <~ c -> ST <{v:Map <Int >Int| v = m /\ select v c /= error} >{v:Map <Int >Int| v=m'} >Unit
client :: empty:(Map <Int >Int) ~> ST <{v:Map <Int >Int| v == empty} >(Map <Int >Int) >Int
client = bind chan (\c ->
         nextPage c (\c ->
         bind c (\c ->
         nextPage c (\c -> c))))

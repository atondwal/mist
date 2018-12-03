module Language.Mist.CGen ( generateConstraints ) where
-- TODO: Do we need to run a Uniqify pass before we run this module?
import           Language.Mist.Types
import           Control.Monad.State.Strict

data SubC a = SubC [(Id, RPoly a)] (RPoly a) (RPoly a)

data CGInfo a = CGInfo { subCs :: [SubC a] }
type CG a = State (CGInfo a)
type CGEnv a = [(Id, RPoly a)]

instance Semigroup (CGInfo a) where
  CGInfo a <> CGInfo b = CGInfo (a <> b)
instance Monoid (CGInfo a) where
  mempty = CGInfo mempty

addC :: CGEnv a -> RPoly a -> RPoly a -> CG a ()
addC γ t t' = modify (<> subC γ t t')
subC γ t t' = CGInfo { subCs = [SubC γ t t'] }

addBinds = flip (foldr addB)
addB (AnnBind x t _) γ = (x, t) : γ

generateConstraints :: Core a -> CGInfo a
generateConstraints = flip execState mempty . synth []

synth :: [(Id, RPoly a)] -> Core a -> CG a (RPoly a)
synth _ e@CNumber{}  = pure $ prim e
synth _ e@CBoolean{} = pure $ prim e
synth _ e@CPrim{}    = pure $ prim e
synth γ (CId x _   ) = pure $ single γ x

synth γ (CApp f y _) = do
  RForall [] (RFun x t t') <- synth γ f
  addC γ (single γ y) (RForall [] t)
  pure $ subst y x t'

synth γ (CTAbs as e _) = do
  RForall as' t <- synth γ e
  pure $ RForall (as' ++ as) t

synth γ (CTApp e tau _) = do
  RForall (a : as) t <- synth γ e
  pure $ RForall as $ subst tau a t

  -- Fake ADT stuff
synth _γ (CTuple _e1 _e2 _) = undefined
synth _γ (CIf _b _e1 _e2 _) = undefined

-- "Bidirectional" "portal" that's made redudant by the fact that we insert
-- all the KVARs at parse time
synth γ (CLam xs e _)
  = bindsRType xs <$>
    synth (addBinds xs γ) e
synth γ  (CLet b@(AnnBind _ t1 _) e1 e2 _)
  = synth γ e1 >>=
    flip (addC γ) t1 >>
    synth (addB b γ) e2

prim _e = undefined
  -- need to pass around a fresh variable supply...
  -- RForall [] $ RBase (Bind "" l) TInt (Prim2 Equal
single _γ _e = undefined
subst = undefined

{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE ConstraintKinds #-}

--------------------------------------------------------------------------------
-- | This module generates refinement type constraints
-- | (see Cosman and Jhala, ICFP '17)
--------------------------------------------------------------------------------

module Language.Mist.CGen
  ( generateConstraints
  , NNF (..)
  ) where

import Language.Mist.Types
import Language.Mist.Names
import Data.Bifunctor (second)
import qualified Data.Map.Strict as M

-------------------------------------------------------------------------------
-- Data Structures
-------------------------------------------------------------------------------
type Env r a = [(Id, RType r a)]

type CGenConstraints r a = (Predicate r, Show r, Show a, PPrint r, Eq r)

-------------------------------------------------------------------------------
-- | generateConstraints is our main entrypoint to this module
-------------------------------------------------------------------------------
generateConstraints :: CGenConstraints r a => ElaboratedExpr r a -> NNF r
generateConstraints = fst . runFresh . synth []

synth :: CGenConstraints r a =>
        Env r a -> ElaboratedExpr r a -> Fresh (NNF r, RType r a)
synth _ e@Unit{}    = (Head true,) <$> prim e
synth _ e@Number{}  = (Head true,) <$> prim e
synth _ e@Boolean{} = (Head true,) <$> prim e
synth _ e@Prim{}    = (Head true,) <$> prim e
synth env (Id x _)  = (Head true,) <$> single env x

synth env (If (Id y _) e1 e2 l) = do
    let rtT = RBase (Bind idT l) TBool $ var y
    let rtF = RBase (Bind idF l) TBool $ varNot y
    -- TODO make these check, after pulling the right thing out of l
    (c1, t1) <- synth ((idT,rtT):env) e1
    (c2, t2) <- synth ((idF,rtF):env) e2
    tHat <- fresh l (foBinds env) (eraseRType t1) -- could just as well be t2
    let c = CAnd [mkAll idT rtT (CAnd [c1, t1 <: tHat]),
                  mkAll idF rtF (CAnd [c2, t2 <: tHat])]
    pure (c, tHat)
  where idT = y<>"then"
        idF = y<>"else"
synth _ (If _ _ _ _) = error "INTERNAL ERROR: if not in ANF"

-- TODO: recursive let?
synth env (Let b e1 e2 _)
  -- Annotated with an assume
  | (AnnBind x (Just (ElabAssume tx)) _) <- b = synth ((x, tx):env) e2
  -- Annotated with an RType (Implicit Parameter)
  | (AnnBind x (Just (ElabRefined rt@(RIFun {}))) _) <- b = do
 let (ns, tx) = splitImplicits rt
 (c1, t1) <- synth (ns ++ env) e1
 (c2, t2) <- synth ((x, rt):env) e2
 tHat <- fresh (extractLoc e2) (foBinds env) (eraseRType t2)
 let c = mkAll x tx (CAnd [c2, t2 <: tHat])
 let c' = foldr (uncurry mkAll) (CAnd [c1, t1 <: tx]) ns
 pure (CAnd [c, c'], tHat)
  -- Annotated with an RType
  | (AnnBind x (Just (ElabRefined tx)) _) <- b = do
 c1 <- check env e1 tx
 -- (c1, t1) <- synth env e1
 (c2, t2) <- synth ((x, tx):env) e2
 tHat <- fresh (extractLoc e2) (foBinds env) (eraseRType t2)
 let c = mkAll x tx (CAnd [c2, t2 <: tHat])
 pure (CAnd [c1, c{-, t1 <: tx-}], tHat)
  -- Unrefined
  | (AnnBind x (Just (ElabUnrefined taux)) l) <- b = do
 t1 <- fresh l (foBinds env) taux
 c1 <- check env e1 t1
 -- (c1, t1) <- synth env e1
 (c2, t2) <- synth ((x, t1):env) e2
 tHat <- fresh (extractLoc e2) (foBinds env) (eraseRType t2)
 let c = mkAll x t1 (CAnd [c2, t2 <: tHat])
 pure (CAnd [c1, c], tHat)

synth env (App e (Id y _) _) =
  synth env e >>= \case
  (c, RFun x t t') -> do
    ty <- single env y
    let cy = ty <: t
    pure (CAnd [c, cy], substReftPred (bindId x |-> y) t')
  (c, rit@RIFun{}) -> do
    let (ns, rt) = splitImplicits rit
    ns' <- sequence [ (,rt) <$> refreshId n | (n,rt) <- ns]
    let RFun x t t' = substReftPred (M.fromList $ zip (fst <$> ns) (fst <$> ns')) rt
    ty <- single env y
    tHat <- fresh (extractLoc e) (foBinds env) (eraseRType t')
    -- let cy = mkExists ns' $ CAnd [ty <: t, substReftPred (y |-> bindId x) t' <: tHat]
    let cy = mkExists ns' $ CAnd [ty <: t, substReftPred (bindId x |-> y) t' <: tHat]
    pure (CAnd [c, cy], tHat)
  _ -> error "CGen App failed"

synth _ (App _ _ _) = error "argument is non-variable"

synth _ (Lam (AnnBind _ Nothing _) _ _) = error "should not occur"
synth _ (Lam (AnnBind _ (Just (ElabAssume tx)) _) _ _) = pure (CAnd [], tx)
synth _env (Lam (AnnBind _x (Just (ElabRefined _tx)) _l) _e _) = do
  error "Internal error, how did we half-annotate a lam with a refinement?"
  -- (c, t) <- synth ((x, tx):env) e
  -- pure (mkAll x tx c, RFun (Bind x l) tx t)

synth env (Lam (AnnBind x (Just (ElabUnrefined typ)) l) e _) = do
  tHat <- fresh l (foBinds env) typ
  (c, t) <- synth ((x, tHat):env) e
  pure (mkAll x tHat c, RFun (Bind x l) tHat t)

synth env (TApp e typ l) = do
  (c, RForall (TV alpha) t) <- synth env e
  tHat <- fresh l (foBinds env) typ
  pure (c, substReftReft (alpha |-> tHat) t)
synth env (TAbs tvar e _) = do
  (c, t) <- synth env e
  pure (c, RForall tvar t)

single :: (Predicate r, Show a, Show r) => Env r a -> Id -> Fresh (RType r a)
single env x = case lookup x env of
  Just (RBase (Bind _ l) baseType _) -> do
  -- `x` is already bound, so instead of "re-binding" x we should selfify
  -- (al la Ou et al. IFIP TCS '04)
    v <- refreshId $ "VV" ++ cSEPARATOR
    pure $ RBase (Bind v l) baseType (varsEqual v x)
  Just rt -> pure rt
  Nothing -> error $ "Unbound Variable " ++ show x ++ show env

fresh l _ (TVar alpha) = do
  x <- refreshId $ "karg" ++ cSEPARATOR
  pure $ RBase (Bind x l) (TVar alpha) true
fresh l env TUnit = freshBaseType env TUnit l
fresh l env TInt = freshBaseType env TInt l
fresh l env TBool = freshBaseType env TBool l
fresh l env (typ1 :=> typ2) = do
  rtype1 <- fresh l env typ1
  x <- refreshId $ "karg" ++ cSEPARATOR
  rtype2 <- fresh l ((x,typ1):env) typ2
  pure $ RFun (Bind x l) rtype1 rtype2
fresh l env (TCtor ctor types) = RApp ctor <$> mapM (sequence . second (fresh l env)) types
fresh l env (TForall tvar typ) = RForall tvar <$> fresh l env typ

-- filters out higher-order type binders in the environment
foTypes :: [(Id, Type)] -> [(Id, Type)]
foTypes ((_,TCtor{}):xs) = foTypes xs
foTypes ((_,_ :=> _):xs) = foTypes xs
foTypes ((x,t):xs) = (x,t):foTypes xs
foTypes [] = []

foBinds [] = []
foBinds ((x, RBase (Bind _ _) t _):ts) = (x,t) : foBinds ts
foBinds (_:ts) = foBinds ts

freshBaseType :: (Predicate r) => [(Id, Type)] -> Type -> a -> Fresh (RType r a)
freshBaseType env baseType l = do
  kappa <- refreshId $ "kvar" ++ cSEPARATOR
  v <- refreshId $ "VV" ++ cSEPARATOR
  let k = buildKvar kappa $ v : map fst (foTypes env)
  pure $ RBase (Bind v l) baseType k

rtype1 <: rtype2 = go (flattenRType rtype1) (flattenRType rtype2)
  where
    go (RBase (Bind x1 _) b1 p1) (RBase (Bind x2 _) b2 p2)
      -- TODO: check whether the guard is correct/needed
      | b1 == b2 = All x1 b1 p1 (Head $ varSubst (x2 |-> x1) p2)
      | otherwise = error $ "error?" ++ show b1 ++ show b2
    go (RFun (Bind x1 _) t1 t1') (RFun (Bind x2 _) t2 t2') = CAnd [c, mkAll x2 t2 c']
      where
        c = t2 <: t1
        c' = substReftPred (x1 |-> x2) t1' <: t2'
    go (RForall alpha t1) (RForall beta t2)
      | alpha == beta = t1 <: t2
      | otherwise = error "Constraint generation subtyping error"
    go (RApp c1 vts1) (RApp c2 vts2)
      | c1 == c2  = CAnd $ concat $ zipWith (<<:) vts1 vts2
      | otherwise = error "CGen: constructors don't match"
    go _ _ = error $ "CGen subtyping error. Got " ++ pprint rtype1 ++ " but expected " ++ pprint rtype2

(v, rt1) <<: (_,rt2) = case v of
                         -- AT: did I flip these twp ? I always fucking flip them...
                         -- TODO: write tests that over these two cases...
                         Invariant -> []
                         Bivariant -> [rt1 <: rt2, rt2 <: rt1]
                         Covariant -> [rt1 <: rt2]
                         Contravariant -> [rt2 <: rt1]


-- | (x :: t) => c
mkAll x rt c = case flattenRType rt of
                 (RBase (Bind y _) b p) -> All x b (varSubst (y |-> x) p) c
                 _ -> c
mkExists xts c = foldr mkExi c xts
  where mkExi (x,rt) c = case flattenRType rt of
                             (RBase (Bind y _) b p) -> Any x b (varSubst (y |-> x) p) c
                             _ -> c

flattenRType :: CGenConstraints r a => RType r a -> RType r a
flattenRType (RRTy b rtype reft) = strengthenRType (flattenRType rtype) b reft
flattenRType rtype = rtype

strengthenRType :: CGenConstraints r a => RType r a -> Bind t a -> r -> RType r a
strengthenRType (RBase b t reft) b' reft' = RBase b t (strengthen reft renamedReft')
  where
    renamedReft' = varSubst ((bindId b') |-> (bindId b)) reft'
strengthenRType (RFun _ _ _) _ _ = error "TODO"
strengthenRType (RIFun _ _ _) _ _ = error "TODO"
-- TODO
strengthenRType rt@RApp{} _b _r = rt
strengthenRType (RRTy b rtype reft) b' reft' = RRTy b rtype (strengthen reft renamedReft')
  where
    renamedReft' = varSubst ((bindId b') |-> (bindId b)) reft'
strengthenRType (RForall _ _) _ _ = error "TODO"


splitImplicits (RIFun b t t') = ((bindId b,t):bs, t'')
    where (bs,t'') = splitImplicits t'
splitImplicits rt = ([],rt)

check :: CGenConstraints r a => Env r a -> ElaboratedExpr r a -> RType r a -> Fresh (NNF r)
check env (Let b e1 e2 _) t2
  -- Annotated with an assume
  | (AnnBind x (Just (ElabAssume tx)) _) <- b = check ((x, tx):env) e2 t2
  -- Annotated with an RType (Implicit Parameter)
  | (AnnBind x (Just (ElabRefined rt@(RIFun {}))) _) <- b = do
 let (ns, tx) = splitImplicits rt
 c1 <- check (ns ++ env) e1 tx
 c2 <- check ((x, rt):env) e2 t2
 let c = mkAll x tx c2
 let c' = foldr (uncurry mkAll) c1 ns
 pure $ CAnd [c, c']
  -- Annotated with an RType
  | (AnnBind x (Just (ElabRefined tx)) _) <- b = do
 c1 <- check env e1 tx
 c2 <- check ((x, tx):env) e2 t2
 let c = mkAll x tx c2
 pure (CAnd [c1, c])
  -- Unrefined
  | (AnnBind x _ _) <- b = do
 (c1, t1) <- synth env e1
 c2 <- check ((x, t1):env) e2 t2
 let c = mkAll x t1 c2
 pure (CAnd [c1, c])

check env (App e (Id y _) _) tapp =
  synth env e >>= \case
  (c, RFun x t t') -> do
    ty <- single env y
    let cy = ty <: t
    pure (CAnd [c, cy, substReftPred (bindId x |-> y) t' <: tapp])
  (c, rit@RIFun{}) -> do
    let (ns, rt) = splitImplicits rit
    ns' <- sequence [ (,rt) <$> refreshId n | (n,rt) <- ns]
    let RFun x t t' = substReftPred (M.fromList $ zip (fst <$> ns) (fst <$> ns')) rt
    ty <- single env y
    let (_ns'', tapp') = splitImplicits tapp
--     traceM $ show ns''
    let cy = mkExists ns' $ CAnd [ty <: t, substReftPred (bindId x |-> y) t' <: tapp']
    pure (CAnd [c, cy])
  _ -> error "CGen App failed"

check _ (Lam (AnnBind _ (Just (ElabAssume _)) _) _ _) _ = pure (CAnd [])
check env (Lam (AnnBind x _ _) e _) (RFun y ty t) =
  mkAll x ty <$> check ((x, ty):env) e (substReftPred (bindId y |-> x) t)

-- this is INCORRECT for implicits
check env e t = do
  (c, t') <- synth env e
  -- traceM ("portal: " ++ pprint t' ++ " <: " ++ pprint t)
  pure $ CAnd [c, t' <: t]

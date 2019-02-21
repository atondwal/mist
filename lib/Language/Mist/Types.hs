{-# LANGUAGE DeriveFunctor        #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE MultiParamTypeClasses, FunctionalDependencies #-}
{-# LANGUAGE PatternSynonyms #-}

module Language.Mist.Types
  (
  -- * Re-Export SourceSpans
    module Language.Mist.UX

  -- * Aliases for various identifiers
  , Id

  -- * Types and Types
  , Type (..), TVar (..), Ctor (..)
  , RType (..)

  -- * Abstract syntax of Mist
  , Expr  (..)
  , Bind  (..)
  , Def

  , ParsedType (..)
  , ParsedExpr, ParsedAnnBind, ParsedDef

  , ElaboratedType
  , pattern ElabUnrefined, pattern ElabRefined
  , ElaboratedExpr, ElaboratedAnnBind

  , AnfType
  , AnfExpr, AnfAnnBind
  , ImmExpr
  , isAnf

  , Unannotated (..)

  , AnnBind (..)
  , aBindType
  , Binder (..)

  , Field (..)
  , Prim2 (..)

  , extract
  , unTV

  , bindsExpr
  , annotateBinding
  -- * Smart Constructors
  -- , bindsRType

  -- * Destructors
  -- , exprDefs

  -- , bkRType
  , eraseRType
  -- , reftRType
  -- , typeToCoreRType

  , Constraint (..)
  , Predicate (..)

  , MonadFresh (..)
  ) where

import GHC.Exts (IsString(..))
import Prelude
import qualified Data.List as L
import Text.Printf
import qualified Text.PrettyPrint as PP
import Language.Mist.UX
import Data.Bifunctor

import Control.Monad.State
import Control.Monad.Writer
import Control.Monad.Identity
import Control.Monad.Except
import Control.Monad.Reader
import Control.Monad.Cont

--------------------------------------------------------------------------------
-- | Abstract syntax of Mist
--------------------------------------------------------------------------------

-- | `Id` are program variables
type Id = Text

-- | `Prim2` are binary operations
data Prim2
  = Plus
  | Minus
  | Times
  | Less
  | Greater
  | Equal
  | And
  deriving (Show, Read)

-- | Mist expressions
-- Parameterized by the type of type annotations
-- and the extra data.
data Expr t a
  = Number  !Integer                               a
  | Boolean !Bool                                  a
  | Unit                                           a
  | Id      !Id                                    a
  | Prim2   !Prim2         !(Expr t a) !(Expr t a) a
  | If      !(Expr t a)    !(Expr t a) !(Expr t a) a
  | Let     !(AnnBind t a) !(Expr t a) !(Expr t a) a
  | App     !(Expr t a)    !(Expr t a)             a
  | Lam     !(AnnBind t a) !(Expr t a)             a
  | TApp    !(Expr t a)    !Type                   a
  | TAbs    TVar           !(Expr t a)             a

  -- | Tuple   !(Expr a t)    !(Expr a t)             a
  -- | GetItem !(Expr a t)    !Field                  a
  deriving (Show, Functor, Read)

-- | The type of Mist type annotations after parsing
-- r is the type of refinements
data ParsedType r a
  = ParsedCheck  !(RType r a)
  | ParsedAssume !(RType r a)
  | ParsedInfer
  deriving (Functor)

type ParsedExpr r a = Expr (ParsedType r a) a
type ParsedAnnBind r a = AnnBind (ParsedType r a) a
type ParsedDef r a = Def (ParsedType r a) a

-- | The type of Mist type annotations after elaboration
-- r is the type of refinements
type ElaboratedType r a = Either (RType r a) Type

pattern ElabRefined :: RType r a -> ElaboratedType r a
pattern ElabRefined r = Left r

pattern ElabUnrefined :: Type -> ElaboratedType r a
pattern ElabUnrefined t = Right t

type ElaboratedExpr r a = Expr (ElaboratedType r a) a
type ElaboratedAnnBind r a = AnnBind (ElaboratedType r a) a

type AnfType t a = Maybe t
type AnfAnnBind t a = AnnBind (AnfType t a ) a

data Field
  = Zero
  | One
  deriving (Show, Read)

data Prim
  = Pi0
  | Pi1
  deriving (Show, Read)

data Bind a = Bind
  { _bindId :: !Id
  , _bindLabel :: a
  }
  deriving (Show, Functor, Read)

-- | Annotated Bindings parameterized by the type of the type annotation
data AnnBind t a = AnnBind
  { _aBindId :: !Id
  , _aBindType :: t
  , _aBindLabel :: a
  }
  deriving (Show, Functor, Read)

aBindType = _aBindType

class Binder b where
  bindId :: b a -> Id
  bindLabel :: b a -> a

instance Binder Bind where
  bindId = _bindId
  bindLabel = _bindLabel

instance Binder (AnnBind t) where
  bindId = _aBindId
  bindLabel = _aBindLabel

type Def t a = (AnnBind t a, Expr t a)

-- TODO: better name
-- | A typeclass for filling in a missing annotation.
class Unannotated t where
  missingAnnotation :: t

instance Unannotated (ParsedType r a) where
  missingAnnotation = ParsedInfer

instance Unannotated (AnfType t a) where
  missingAnnotation = Nothing

-- | Constructing `Bare` from let-binds
bindsExpr :: (Unannotated t) => [(Bind a, (Expr t a))] -> Expr t a -> a -> Expr t a
bindsExpr bs e l = foldr (\(x, e1) e2 ->
                            Let (annotateBinding x missingAnnotation) e1 e2 l)
                   e bs

annotateBinding :: Bind a -> t -> AnnBind t a
annotateBinding bind typ =
  AnnBind { _aBindId = bindId bind
          , _aBindType = typ
          , _aBindLabel = bindLabel bind
          }

-- | Constructing a function declaration
-- dec :: Bind a -> Sig -> [Bind a] -> Expr a -> Expr a -> a -> Expr a
-- dec f t xs e e' l = Let f (Fun f t xs e l) e' l

-- | Constructing `RForall` from let-binds
-- bindsRType :: AnnBind a -> RType Core a -> RType Core a
-- bindsRType b t = mkPiCB b t

-- | makes a Pi type from a Core Binder and an RType
-- mkPiCB :: AnnBind a -> RType Core a -> RType Core a
-- mkPiCB (AnnBind x t l) (RForall a t') = RForall a (RFun (Bind x l) t t')
-- mkPiCB (AnnBind x t l) t' = RFun (Bind x l) t t'

-- | Destructing `Expr` into let-binds
-- exprDefs :: Expr a t -> ([Def a t], Expr a t)
-- exprDefs = go
--   where
--     go (Let x e e' _) = ((x, e) : bs, body)
--       where (bs, body) = go e'
--     go body = ([], body)

--------------------------------------------------------------------------------
extract :: Expr t a -> a
--------------------------------------------------------------------------------
extract (Number _ l)    = l
extract (Boolean _ l)   = l
extract (Id _ l)        = l
extract (Prim2 _ _ _ l) = l
extract (If _ _ _ l)    = l
extract (Let _ _ _ l)   = l
extract (App _ _ l)     = l
extract (Lam _ _ l)     = l
extract (Unit  l)       = l
extract (TApp _ _ l)    = l
extract (TAbs _ _ l)    = l

--------------------------------------------------------------------------------
-- | Dynamic Errors
--------------------------------------------------------------------------------

-- | DynError correspond to different kind of dynamic/run-time errors
data DynError
  = ArithOverflow
  | IndexLow
  | IndexHigh
  | ArityError
  deriving (Show)

--------------------------------------------------------------------------------
-- | Pretty Printer
--------------------------------------------------------------------------------
instance PPrint Prim2 where
  pprint Plus    = "+"
  pprint Minus   = "-"
  pprint Times   = "*"
  pprint Less    = "<"
  pprint Greater = ">"
  pprint Equal   = "=="
  pprint And     = "&&"

instance PPrint Bool where
  pprint True  = "True"
  pprint False = "False"

-- TODO: properly print annotations
instance PPrint (Bind a) where
  pprint (Bind x _) = x

instance PPrint (AnnBind t a) where
  pprint (AnnBind x _ _) = x

instance PPrint Field where
  pprint Zero  = "0"
  pprint One   = "1"

-- TODO: better instance
instance (Show t) => PPrint (Expr t a) where
  pprint (Number n _) = show n
  pprint (Boolean b _) = pprint b
  pprint (Unit _) = "()"
  pprint (Id x _) = x
  pprint (Prim2 o l r _) = printf "%s %s %s" (pprint l) (pprint o) (pprint r)
  pprint (If c t e _) = printf "(if %s then %s else %s)" (pprint c) (pprint t) (pprint e)
  -- pprint e@Let{} = printf "(let %s in %s)" (ppDefs ds) (pprint e')
  --   where (ds, e') = exprDefs e
  pprint (Let bind e1 e2 _) = printf "(let %s : %s = %s in %s)" (bindId bind) (show $ aBindType bind) (pprint e1) (pprint e2)-- TODO: make better
  pprint (App e1 e2 _) = printf "(%s %s)" (pprint e1) (pprint e2)
  pprint (Lam x e _) = printf "(\\ %s -> %s)" (pprint x) (pprint e)
  pprint (TApp e t _) = printf "(%s@%s)" (pprint e) (pprint t)
  pprint (TAbs alpha e _) = printf "(/\\%s . %s)" (pprint alpha) (pprint e)

_ppDefs :: [Def t a] -> Text
_ppDefs = L.intercalate "\n " . fmap ppDef

ppDef :: Def t a -> Text
ppDef _ = error "TODO"

_ppSig k b s = printf "%s %s %s\n" (pprint b) k (pprint s)
_ppEqn b e = printf "%s = \n" (pprint b)
            ++ nest 2 (pprint e)

nest :: Int -> Text -> Text
nest n = unlines . map pad . lines
  where
    pad s = blanks ++ s
    blanks = replicate n ' '

instance PPrint e => PPrint (RType e a) where
  pprint (RBase b t e) =
    printf "{%s:%s | %s}" (pprint b) (pprint t) (pprint e)
  pprint (RFun b t1 t2) =
    printf "%s:%s -> %s" (pprint b) (pprint t1) (pprint t2)
  pprint (RRTy b t e) =
    printf "{%s:%s || %s}" (pprint b) (pprint t) (pprint e)
  pprint (RForall tv t) = printf "forall %s. %s" (pprint tv) (pprint t)

--------------------------------------------------------------------------------
-- | `isAnf e` is True if `e` is an A-Normal Form
--------------------------------------------------------------------------------
{-@ measure isAnf @-}
isAnf :: Expr t a -> Bool
isAnf (Unit _)         = True
isAnf (Number  _ _)    = True
isAnf (Boolean _ _)    = True
isAnf (Id      _ _)    = True
isAnf (Prim2 _ e e' _) = isImm e && isImm e'
isAnf (If c t e _)     = isImm c && isAnf t && isAnf e
isAnf (Let _ e e' _)   = isAnf e && isAnf e'
isAnf (App e e' _)     = isAnf e  && isAnf e'
isAnf (Lam _ e _)      = isAnf e
isAnf (TApp e _ _)     = isAnf e
isAnf (TAbs _ e _)     = isAnf e

{-@ measure isImm @-}
isImm :: Expr t a -> Bool
isImm (Number  _ _) = True
isImm (Boolean _ _) = True
isImm (Id      _ _) = True
isImm _             = False

{-@ type AnfExpr a = {v:Expr a| isAnf v} @-}
type AnfExpr r a = Expr (AnfType r a) a

-- TODO: this should become VarExpr
{-@ type ImmExpr a = {v:Expr a | isImm v} @-}
type ImmExpr r a = Expr (AnfType r a) a

-- {-@ measure isVarAnf @-}
-- isVarAnf :: Expr t a -> Bool
-- isVarAnf (Unit _)         = True
-- isVarAnf (Number  _ _)    = True
-- isVarAnf (Boolean _ _)    = True
-- isVarAnf (Id      _ _)    = True
-- isVarAnf (Prim2 _ e e' _) = isVar e && isVar e'
-- isVarAnf (If c t e _)     = isVar c && isVarAnf t && isVarAnf e
-- isVarAnf (Let _ e e' _)   = isVarAnf e && isVarAnf e'
-- isVarAnf (App e e' _)     = isVarAnf e  && isVar e'
-- isVarAnf (Lam _ e _)      = isVarAnf e

-- {-@ measure isVar @-}
-- isVar :: Expr t a -> Bool
-- isVar (Id      _ _) = True
-- isVar _             = False

--------------------------------------------------------------------------------
-- | The `Parsed` types are for parsed ASTs.
--------------------------------------------------------------------------------

instance Located a => Located (Expr t a) where
  sourceSpan e = sourceSpan $ extract e

instance (Binder b, Located a) => Located (b a) where
  sourceSpan bind = sourceSpan $ bindLabel bind

--------------------------------------------------------------------------------
-- | Types ---------------------------------------------------------------------
--------------------------------------------------------------------------------

-- | Refinement types
-- | - refinements are expressions of type Bool
-- |
-- | ```
-- | τ ::= { v:τ | r }   -- a refinement on an RType
-- |     | { v:b | r }   -- a refinement on a base Type
-- |     | x:τ -> τ      -- a pi type
-- |     | ∀a.τ
-- | ```
-- |
-- | This allows us to bind functions as in LH `--higherorder`
-- |   {f : { v:_ | v < 0 } -> { v:_ | v > 0} | f 0 = 0}

data RType r a
  = RBase !(Bind a) Type !r
  | RFun !(Bind a) !(RType r a) !(RType r a)
  | RRTy !(Bind a) !(RType r a) r
  | RForall TVar !(RType r a)
  deriving (Show, Functor, Read)

data Type = TVar TVar           -- a
          | TUnit               -- 1
          | TInt                -- Int
          | TBool               -- Bool
          | Type :=> Type       -- t1 => t2
          -- | TPair Type Type     -- (t0, t1)
          | TCtor Ctor [Type]   -- Ctor [t1,...,tn]
          | TForall TVar Type   -- ∀a.t
          deriving (Eq, Ord, Show, Read)

newtype Ctor = CT Id deriving (Eq, Ord, Show, Read)

newtype TVar = TV Id deriving (Eq, Ord, Show, Read)

unTV :: TVar -> Id
unTV (TV t) = t

-- | Returns the base type for an RType
eraseRType :: RType e a -> Type
eraseRType (RBase _ t _) = t
eraseRType (RFun _ t1 t2) = eraseRType t1 :=> eraseRType t2
eraseRType (RRTy _ t _) = eraseRType t
eraseRType (RForall alphas t) = TForall alphas (eraseRType t)

instance PPrint Ctor where
  pprint = PP.render . prCtor

instance PPrint TVar where
  pprint = PP.render . prTVar

instance PPrint Type where
  pprint = PP.render . prType

instance IsString TVar where
  fromString = TV

instance IsString Type where
  fromString = TVar . TV

prType :: Type -> PP.Doc
prType TUnit        = PP.text "Unit"
prType (TVar a)     = prTVar a
prType TInt         = PP.text "Int"
prType TBool        = PP.text "Bool"
prType (t1 :=> t2)   = PP.parens (prType t1) PP.<+> PP.text "=>" PP.<+> prType t2
-- prType (TPair t s)  = PP.parens $ prType t PP.<> PP.text "," PP.<+> prType s
prType (TCtor c ts) = prCtor c PP.<> PP.brackets (prTypes ts)
prType (TForall a t)  = PP.text "Forall" PP.<+>
                          prTVar a
                          PP.<> PP.text "." PP.<+> prType t

prTypes           :: [Type] -> PP.Doc
prTypes ts         = PP.hsep $ PP.punctuate PP.comma (prType <$> ts)


prCtor :: Ctor -> PP.Doc
prCtor (CT c) = PP.text c

prTVar :: TVar -> PP.Doc
prTVar (TV a) = PP.text a


--------------------------------------------------------------------------------
-- | Horn Clause Structures ----------------------------------------------------
--------------------------------------------------------------------------------

-- | NNF Constraints
data Constraint r
  = Head r                             -- ^ p
  | CAnd [Constraint r]                -- ^ c1 /\ c2
  | All Id Type r (Constraint r)       -- ^ ∀x:τ.p => c
  deriving (Show, Functor)

-- | Type class to represent predicates
class Predicate r where
  true :: r
  false :: r
  varsEqual :: Id -> Id -> r -- ^ builds a refinement that the two variables are equivalent
  prim :: (MonadFresh m) => Expr t a -> m (RType r a) -- ^ Gives a specification to primitives
                                                      -- TODO: this is a partial function
  strengthen :: r -> r -> r
  varSubst :: Id -> Id -> r -> r -- ^ [x/y]r
  buildKvar :: Id -> [Id] -> r -- ^ k(x1, ..., xn)

--------------------------------------------------------------------------------
-- | A MonadFresh encompasses the operations for generating fresh, scoped names
--------------------------------------------------------------------------------
class Monad m => MonadFresh m where
  refreshId :: Id -> m Id

-- TODO: figure out how to put this back in Names.hs

-------------------------------------------------------------------------------
-- MonadFresh instances -------------------------------------------------------
-------------------------------------------------------------------------------

instance (Monoid w, MonadFresh m) => MonadFresh (WriterT w m) where
  refreshId = lift . refreshId

instance MonadFresh m => MonadFresh (IdentityT m) where
  refreshId = lift . refreshId

instance MonadFresh m => MonadFresh (ExceptT e m) where
  refreshId = lift . refreshId

instance MonadFresh m => MonadFresh (StateT s m) where
  refreshId = lift . refreshId

instance MonadFresh m => MonadFresh (ReaderT r m) where
  refreshId = lift . refreshId

instance MonadFresh m => MonadFresh (ContT r m) where
  refreshId = lift . refreshId

-------------------------------------------------------------------------------
-- Bifunctor instances --------------------------------------------------------
-------------------------------------------------------------------------------

instance Bifunctor Expr where
  second = fmap
  first _ (Number i l) = Number i l
  first _ (Boolean b l) = Boolean b l
  first _ (Unit l) = Unit l
  first _ (Id x l) = Id x l
  first f (Prim2 op e1 e2 l) = Prim2 op (first f e1) (first f e2) l
  first f (If e1 e2 e3 l) = If (first f e1) (first f e2) (first f e3) l
  first f (Let bind e1 e2 l) = Let (first f bind) (first f e1) (first f e2) l
  first f (App e1 e2 l) = App (first f e1) (first f e2) l
  first f (Lam bind e l) = Lam (first f bind) (first f e) l
  first f (TApp e t l) = TApp (first f e) t l
  first f (TAbs alpha e l) = TAbs alpha (first f e) l

instance Bifunctor AnnBind where
  second = fmap
  first f a@AnnBind{_aBindType = typ} = a{_aBindType = f typ}

instance Bifunctor ParsedType where
  second = fmap
  first f (ParsedCheck r) = ParsedCheck $ first f r
  first f (ParsedAssume r) = ParsedAssume $ first f r
  first _ ParsedInfer = ParsedInfer

instance Bifunctor RType where
  second = fmap
  first f (RBase b t r) = RBase b t (f r)
  first f (RFun b rt1 rt2) = RFun b (first f rt1) (first f rt2)
  first f (RRTy b rt r) = RRTy b (first f rt) (f r)
  first f (RForall tvar rt) = RForall tvar (first f rt)

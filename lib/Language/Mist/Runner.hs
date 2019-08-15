{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE LambdaCase #-}

module Language.Mist.Runner where

import System.IO
import Language.Mist.Types
import Language.Mist.Parser
import Language.Mist.Checker
import Language.Mist.CGen
import Language.Mist.Config
import Language.Mist.ToFixpoint
import Language.Mist.Normalizer
import Language.Mist.Names
import qualified Language.Fixpoint.Horn.Types as HC
import qualified Language.Fixpoint.Types as F

import Text.Megaparsec.Pos (initialPos) -- NOTE: just for debugging

type R = HC.Pred

{-
  0) parse
  1) unique
  2) convert refinements from mist `Expr`s to fixpoint `Expr`s
  3) elaborate
  4) annotate each node with its type
  5) anf
  6) constraint generation
-}

---------------------------------------------------------------------------
runMist :: Handle -> Config -> IO (Result ())
---------------------------------------------------------------------------
runMist h config = act h config >>= \case
  r@Right{} -> hPutStrLn h "SAFE" >> return r
  Left es -> esHandle h (return . Left) es

act :: Handle -> Config -> IO (Result ())
act h config = do
  let f = (srcFile config)
  s <- readFile f
  (measures, e) <-
    if (readInput config)
    then pure $ read s
    else parse f s
  let r = mist measures e
  case r of
    Right (measures', t) -> do
      -- !_ <- traceM $ pprint (anormal (annotate t TUnit))
      let c = generateConstraints (anormal (annotate t TUnit))
      solverResult <- solve measures' c
      hPrint h solverResult
      case F.resStatus solverResult of
        F.Safe -> return (Right ())
        _ -> return $ Left [mkError ("solver failed: " ++ show solverResult) (SS {ssBegin = initialPos f, ssEnd = initialPos f})] -- TODO: proper error
    Left l -> return (Left l)

esHandle :: Handle -> ([UserError] -> IO a) -> [UserError] -> IO a
esHandle h exitF es = renderErrors es >>= hPutStrLn h >> exitF es

-----------------------------------------------------------------------------------
mist :: Located a => Measures -> ParsedExpr a -> Result (Measures, ElaboratedExpr R a)
-----------------------------------------------------------------------------------
mist measures expr =
  case wellFormed (unParsedExpr expr) of
    [] -> do
      let (measures', uniqueExpr) = uniquify (measures, expr)
      let predExpr = parsedExprPredToFixpoint uniqueExpr
      result <- elaborate predExpr
      pure (measures', result)
    errors -> Left errors

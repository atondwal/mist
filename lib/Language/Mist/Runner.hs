{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}

module Language.Mist.Runner where

import qualified Control.Exception as Ex
import System.IO
import Language.Mist.Types
import Language.Mist.Parser
import Language.Mist.Checker
import Language.Mist.CGen
import Language.Mist.ToFixpoint
import Language.Mist.Normalizer
import Language.Mist.Names
import qualified Language.Fixpoint.Horn.Types as HC

type R = HC.Pred

deriving instance Show HC.Pred -- NOTE: just for debugging

---------------------------------------------------------------------------
runMist :: Handle -> FilePath -> IO (Result (ElaboratedExpr R SourceSpan))
---------------------------------------------------------------------------
runMist h f = act h f
                `Ex.catch`
                   esHandle h (return . Left)

act :: Handle -> FilePath -> IO (Result (ElaboratedExpr R SourceSpan))
act _h f = do
  s    <- readFile f
  e    <- parse f s
  let r = mist e
  case r of
    Right t -> do
      -- hPutStrLn h ("Elaborated: " ++ show t) >>
      --(print c >> solve c >>= print)
      let c = generateConstraints (anormal t) -- TODO: move this into the mist function
      print c >> solve c
      return r
    Left _ -> return r

esHandle :: Handle -> ([UserError] -> IO a) -> [UserError] -> IO a
esHandle h exitF es = renderErrors es >>= hPutStrLn h >> exitF es

-----------------------------------------------------------------------------------
mist :: BareExpr -> Result (ElaboratedExpr R SourceSpan)
-----------------------------------------------------------------------------------
mist expr = do
  let refreshedExpr = uniquify expr
  let predExpr = parsedExprPredToFixpoint refreshedExpr
  check predExpr

  -- check predExpr >>= fmap anormal
  -- pure >> fmap parsedExprPredToFixpoint -- >> check >> anormal

--------------------------------------------------------------------------------
check :: ParsedExpr r SourceSpan -> Result (ElaboratedExpr r SourceSpan)
--------------------------------------------------------------------------------
check expr =
  case wellFormed expr of
    [] -> elaborate expr
    errors -> Left errors

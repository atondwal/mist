# Mist 

A tiny language for teaching and experimenting with refinement types, in the style of 
[LiquidHaskell](https://github.com/ucsd-progsys/liquidhaskell).

## TODO

- [x] BUILD initial code
- [ ] STEAL make grammar more Haskelly
- [ ] PARSE in all Nano tests (but using Garter representation)
- [ ] PORT all the garter tests (using Haskelly syntax)
- [ ] PRINT all inferred (top-level) types
- [ ] ADD   elaboration @a @b etc. 
- [ ] PRINT "elaborated" expressions
- [ ] TYPE  refinement type constraints
- [ ] GEN   refinement type constraints 
- [ ] SOLVE refinement type constraints (with fixpoint)

## Modules

- `Language.Mist.Utils.Misc` 
- `Language.Mist.Utils.UX` 
- `Language.Mist.Utils.Test` 
- `Language.Mist.Basic.Types` 
- `Language.Mist.Basic.ANF` 
- `Language.Mist.Basic.WellFormed` 
- `Language.Mist.Basic.Check` 
- `Language.Mist.Liquid.Types` 
- `Language.Mist.Liquid.Check` 


{-# Language DataKinds #-}
{-# Language ScopedTypeVariables #-}

{- |
    Module: EVM.Traversals
    Description: Generic traversal functions for Expr datatypes
-}
module EVM.Traversals where

import Prelude hiding (Word, LT, GT)

import Control.Monad.Identity
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.List (foldl')

import EVM.Types

foldProp :: forall b . Monoid b => (forall a . Expr a -> b) -> b -> Prop -> b
foldProp f acc p = acc <> (go p)
  where
    go :: Prop -> b
    go = \case
      PBool _ -> mempty
      PEq a b -> (foldExpr f mempty a) <> (foldExpr f mempty b)
      PLT a b -> foldExpr f mempty a <> foldExpr f mempty b
      PGT a b -> foldExpr f mempty a <> foldExpr f mempty b
      PGEq a b -> foldExpr f mempty a <> foldExpr f mempty b
      PLEq a b -> foldExpr f mempty a <> foldExpr f mempty b
      PNeg a -> go a
      PAnd a b -> go a <> go b
      POr a b -> go a <> go b
      PImpl a b -> go a <> go b

foldEContract :: forall b . Monoid b => (forall a . Expr a -> b) -> b -> Expr EContract -> b
foldEContract f _ g@(GVar _) = f g
foldEContract f acc (C code storage balance _)
  =  acc
  <> foldCode f code
  <> foldExpr f mempty storage
  <> foldExpr f mempty balance

foldContract :: forall b . Monoid b => (forall a . Expr a -> b) -> b -> Contract -> b
foldContract f acc c
  =  acc
  <> foldCode f c.code
  <> foldExpr f mempty c.storage
  <> foldExpr f mempty c.origStorage
  <> foldExpr f mempty c.balance

foldCode :: forall b . Monoid b => (forall a . Expr a -> b) -> ContractCode -> b
foldCode f = \case
  RuntimeCode (ConcreteRuntimeCode _) -> mempty
  RuntimeCode (SymbolicRuntimeCode c) -> foldl' (foldExpr f) mempty c
  InitCode _ buf -> foldExpr f mempty buf
  UnknownCode addr -> foldExpr f mempty addr

foldTrace :: forall b . Monoid b => (forall a . Expr a -> b) -> b -> Trace -> b
foldTrace f acc t = acc <> (go t)
  where
    go :: Trace -> b
    go (Trace _ _ d) = case d of
      EventTrace a b c -> foldExpr f mempty a <> foldExpr f mempty b <> (foldl (foldExpr f) mempty c)
      FrameTrace a -> foldContext f mempty a
      ErrorTrace _ -> mempty
      EntryTrace _ -> mempty
      ReturnTrace a b -> foldExpr f mempty a <> foldContext f mempty b

foldContext :: forall b . Monoid b => (forall a . Expr a -> b) -> b -> FrameContext -> b
foldContext f acc = \case
  CreationContext a b c d -> acc
                          <> foldExpr f mempty a
                          <> foldExpr f mempty b
                          <> foldl' (foldExpr f) mempty (Map.keys c)
                          <> foldl' (foldContract f) mempty c
                          <> foldSubState f mempty d
  CallContext a b _ _ e _ g h i -> acc
                                <> foldExpr f mempty a
                                <> foldExpr f mempty b
                                <> foldExpr f mempty e
                                <> foldExpr f mempty g
                                <> foldl' (foldExpr f) mempty (Map.keys h)
                                <> foldl' (foldContract f) mempty h
                                <> foldSubState f mempty i

foldSubState :: forall b . Monoid b => (forall a . Expr a -> b) -> b -> SubState -> b
foldSubState f acc (SubState a b c d e) = acc
                                       <> foldl' (foldExpr f) mempty a
                                       <> foldl' (foldExpr f) mempty b
                                       <> foldl' (foldExpr f) mempty c
                                       <> foldl' (\r (addr, _) -> r <> foldExpr f mempty addr) mempty d
                                       <> foldl' (\r (addr, _) -> r <> foldExpr f mempty addr) mempty e

foldTraces :: forall b . Monoid b => (forall a . Expr a -> b) -> b -> Traces -> b
foldTraces f acc (Traces a _) = acc <> foldl (foldl (foldTrace f)) mempty a


-- | Recursively folds a given function over a given expression
-- Recursion schemes do this & a lot more, but defining them over GADT's isn't worth the hassle
foldExpr :: forall b c . Monoid b => (forall a . Expr a -> b) -> b -> Expr c -> b
foldExpr f acc expr = acc <> (go expr)
  where
    go :: forall a . Expr a -> b
    go = \case

      -- literals & variables

      e@(Lit _) -> f e
      e@(LitByte _) -> f e
      e@(Var _) -> f e
      e@(GVar _) -> f e

      -- contracts

      e@(C {}) -> foldEContract f acc e

      -- bytes

      e@(IndexWord a b) -> f e <> (go a) <> (go b)
      e@(EqByte a b) -> f e <> (go a) <> (go b)

      e@(JoinBytes
        zero one two three four five six seven
        eight nine ten eleven twelve thirteen fourteen fifteen
        sixteen seventeen eighteen nineteen twenty twentyone twentytwo twentythree
        twentyfour twentyfive twentysix twentyseven twentyeight twentynine thirty thirtyone)
        -> f e
        <> (go zero) <> (go one) <> (go two) <> (go three)
        <> (go four) <> (go five) <> (go six) <> (go seven)
        <> (go eight) <> (go nine) <> (go ten) <> (go eleven)
        <> (go twelve) <> (go thirteen) <> (go fourteen)
        <> (go fifteen) <> (go sixteen) <> (go seventeen)
        <> (go eighteen) <> (go nineteen) <> (go twenty)
        <> (go twentyone) <> (go twentytwo) <> (go twentythree)
        <> (go twentyfour) <> (go twentyfive) <> (go twentysix)
        <> (go twentyseven) <> (go twentyeight) <> (go twentynine)
        <> (go thirty) <> (go thirtyone)

      -- control flow

      e@(Success a b c d) -> f e
                          <> foldl (foldProp f) mempty a
                          <> foldTraces f mempty b
                          <> go c
                          <> foldl' (foldExpr f) mempty (Map.keys d)
                          <> foldl' (foldEContract f) mempty d
      e@(Failure a b _) -> f e <> (foldl (foldProp f) mempty a) <> foldTraces f mempty b
      e@(Partial a b _) -> f e <> (foldl (foldProp f) mempty a) <> foldTraces f mempty b
      e@(ITE a b c) -> f e <> (go a) <> (go b) <> (go c)

      -- integers

      e@(Add a b) -> f e <> (go a) <> (go b)
      e@(Sub a b) -> f e <> (go a) <> (go b)
      e@(Mul a b) -> f e <> (go a) <> (go b)
      e@(Div a b) -> f e <> (go a) <> (go b)
      e@(SDiv a b) -> f e <> (go a) <> (go b)
      e@(Mod a b) -> f e <> (go a) <> (go b)
      e@(SMod a b) -> f e <> (go a) <> (go b)
      e@(AddMod a b c) -> f e <> (go a) <> (go b) <> (go c)
      e@(MulMod a b c) -> f e <> (go a) <> (go b) <> (go c)
      e@(Exp a b) -> f e <> (go a) <> (go b)
      e@(SEx a b) -> f e <> (go a) <> (go b)
      e@(Min a b) -> f e <> (go a) <> (go b)
      e@(Max a b) -> f e <> (go a) <> (go b)

      -- booleans

      e@(LT a b) -> f e <> (go a) <> (go b)
      e@(GT a b) -> f e <> (go a) <> (go b)
      e@(LEq a b) -> f e <> (go a) <> (go b)
      e@(GEq a b) -> f e <> (go a) <> (go b)
      e@(SLT a b) -> f e <> (go a) <> (go b)
      e@(SGT a b) -> f e <> (go a) <> (go b)
      e@(Eq a b) -> f e <> (go a) <> (go b)
      e@(IsZero a) -> f e <> (go a)

      -- bits

      e@(And a b) -> f e <> (go a) <> (go b)
      e@(Or a b) -> f e <> (go a) <> (go b)
      e@(Xor a b) -> f e <> (go a) <> (go b)
      e@(Not a) -> f e <> (go a)
      e@(SHL a b) -> f e <> (go a) <> (go b)
      e@(SHR a b) -> f e <> (go a) <> (go b)
      e@(SAR a b) -> f e <> (go a) <> (go b)

      -- Hashes

      e@(Keccak a) -> f e <> (go a)
      e@(SHA256 a) -> f e <> (go a)

      -- block context

      e@(Origin) -> f e
      e@(Coinbase) -> f e
      e@(Timestamp) -> f e
      e@(BlockNumber) -> f e
      e@(PrevRandao) -> f e
      e@(GasLimit) -> f e
      e@(ChainId) -> f e
      e@(BaseFee) -> f e
      e@(BlockHash a) -> f e <> (go a)

      -- tx context

      e@(TxValue) -> f e

      -- frame context

      e@(Gas _ _) -> f e
      e@(Balance {}) -> f e

      -- code

      e@(CodeSize a) -> f e <> (go a)
      e@(CodeHash a) -> f e <> (go a)

      -- logs

      e@(LogEntry a b c) -> f e <> (go a) <> (go b) <> (foldl (<>) mempty (fmap f c))

      -- Contract Creation

      e@(Create a b c d g h)
        -> f e
        <> (go a)
        <> (go b)
        <> (go c)
        <> (go d)
        <> (foldl (<>) mempty (fmap go g))
        <> (go h)
      e@(Create2 a b c d g h i)
        -> f e
        <> (go a)
        <> (go b)
        <> (go c)
        <> (go d)
        <> (go g)
        <> (foldl (<>) mempty (fmap go h))
        <> (go i)

      -- Calls

      e@(Call a b c d g h i j k)
        -> f e
        <> (go a)
        <> (maybe mempty (go) b)
        <> (go c)
        <> (go d)
        <> (go g)
        <> (go h)
        <> (go i)
        <> (foldl (<>) mempty (fmap go j))
        <> (go k)

      e@(CallCode a b c d g h i j k)
        -> f e
        <> (go a)
        <> (go b)
        <> (go c)
        <> (go d)
        <> (go g)
        <> (go h)
        <> (go i)
        <> (foldl (<>) mempty (fmap go j))
        <> (go k)

      e@(DelegeateCall a b c d g h i j k)
        -> f e
        <> (go a)
        <> (go b)
        <> (go c)
        <> (go d)
        <> (go g)
        <> (go h)
        <> (go i)
        <> (foldl (<>) mempty (fmap go j))
        <> (go k)

      -- storage

      e@(LitAddr _) -> f e
      e@(WAddr a) -> f e <> go a
      e@(SymAddr _) -> f e

      -- storage

      e@(ConcreteStore a _) -> f e <> go a
      e@(AbstractStore _) -> f e
      e@(SLoad a b) -> f e <> (go a) <> (go b)
      e@(SStore a b c) -> f e <> (go a) <> (go b) <> (go c)

      -- buffers

      e@(ConcreteBuf _) -> f e
      e@(AbstractBuf _) -> f e
      e@(ReadWord a b) -> f e <> (go a) <> (go b)
      e@(ReadByte a b) -> f e <> (go a) <> (go b)
      e@(WriteWord a b c) -> f e <> (go a) <> (go b) <> (go c)
      e@(WriteByte a b c) -> f e <> (go a) <> (go b) <> (go c)

      e@(CopySlice a b c d g)
        -> f e
        <> (go a)
        <> (go b)
        <> (go c)
        <> (go d)
        <> (go g)
      e@(BufLength a) -> f e <> (go a)

mapProp :: (forall a . Expr a -> Expr a) -> Prop -> Prop
mapProp f = \case
  PBool b -> PBool b
  PEq a b -> PEq (mapExpr f (f a)) (mapExpr f (f b))
  PLT a b -> PLT (mapExpr f (f a)) (mapExpr f (f b))
  PGT a b -> PGT (mapExpr f (f a)) (mapExpr f (f b))
  PLEq a b -> PLEq (mapExpr f (f a)) (mapExpr f (f b))
  PGEq a b -> PGEq (mapExpr f (f a)) (mapExpr f (f b))
  PNeg a -> PNeg (mapProp f a)
  PAnd a b -> PAnd (mapProp f a) (mapProp f b)
  POr a b -> POr (mapProp f a) (mapProp f b)
  PImpl a b -> PImpl (mapProp f a) (mapProp f b)

mapTrace :: (forall a . Expr a -> Expr a) -> Trace -> Trace
mapTrace f (Trace x y z) = Trace x y (go z)
  where
    go :: TraceData -> TraceData
    go = \case
      EventTrace a b c -> EventTrace (f a) (f b) (fmap (mapExpr f) c)
      FrameTrace a -> FrameTrace (go' a)
      ErrorTrace a -> ErrorTrace a
      EntryTrace a -> EntryTrace a
      ReturnTrace a b -> ReturnTrace (f a) (go' b)

    go' :: FrameContext -> FrameContext
    go' = \case
      CreationContext a b c d -> CreationContext a (f b) c d
      CallContext a b c d e g h i j -> CallContext a b c d (f e) g (f h) (Map.mapKeys f . Map.map (mapContract f) $ i) j

-- | Recursively applies a given function to every node in a given expr instance
-- Recursion schemes do this & a lot more, but defining them over GADT's isn't worth the hassle
mapExpr :: (forall a . Expr a -> Expr a) -> Expr b -> Expr b
mapExpr f expr = runIdentity (mapExprM (Identity . f) expr)

mapContract :: (forall a . Expr a -> Expr a) -> Contract -> Contract
mapContract f expr = runIdentity (mapContractM (Identity . f) expr)


mapExprM :: Monad m => (forall a . Expr a -> m (Expr a)) -> Expr b -> m (Expr b)
mapExprM f expr = case expr of

  -- literals & variables

  Lit a -> f (Lit a)
  LitByte a -> f (LitByte a)
  Var a -> f (Var a)
  GVar s -> f (GVar s)

  -- addresses

  c@(C {}) -> mapEContractM f c

  -- addresses

  LitAddr a -> f (LitAddr a)
  SymAddr a -> f (SymAddr a)
  WAddr a -> WAddr <$> f a

  -- bytes

  IndexWord a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (IndexWord a' b')
  EqByte a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (EqByte a' b')

  JoinBytes zero one two three four five six seven eight nine
    ten eleven twelve thirteen fourteen fifteen sixteen seventeen
    eighteen nineteen twenty twentyone twentytwo twentythree twentyfour
    twentyfive twentysix twentyseven twentyeight twentynine thirty thirtyone -> do
    zero' <- mapExprM f zero
    one' <- mapExprM f one
    two' <- mapExprM f two
    three' <- mapExprM f three
    four' <- mapExprM f four
    five' <- mapExprM f five
    six' <- mapExprM f six
    seven' <- mapExprM f seven
    eight' <- mapExprM f eight
    nine' <- mapExprM f nine
    ten' <- mapExprM f ten
    eleven' <- mapExprM f eleven
    twelve' <- mapExprM f twelve
    thirteen' <- mapExprM f thirteen
    fourteen' <- mapExprM f fourteen
    fifteen' <- mapExprM f fifteen
    sixteen' <- mapExprM f sixteen
    seventeen' <- mapExprM f seventeen
    eighteen' <- mapExprM f eighteen
    nineteen' <- mapExprM f nineteen
    twenty' <- mapExprM f twenty
    twentyone' <- mapExprM f twentyone
    twentytwo' <- mapExprM f twentytwo
    twentythree' <- mapExprM f twentythree
    twentyfour' <- mapExprM f twentyfour
    twentyfive' <- mapExprM f twentyfive
    twentysix' <- mapExprM f twentysix
    twentyseven' <- mapExprM f twentyseven
    twentyeight' <- mapExprM f twentyeight
    twentynine' <- mapExprM f twentynine
    thirty' <- mapExprM f thirty
    thirtyone' <- mapExprM f thirtyone
    f (JoinBytes zero' one' two' three' four' five' six' seven' eight' nine'
         ten' eleven' twelve' thirteen' fourteen' fifteen' sixteen' seventeen'
         eighteen' nineteen' twenty' twentyone' twentytwo' twentythree' twentyfour'
         twentyfive' twentysix' twentyseven' twentyeight' twentynine' thirty' thirtyone')

  -- control flow

  Failure a b c -> do
    a' <- mapM (mapPropM f) a
    b' <- mapTracesM f b
    f (Failure a' b' c)
  Partial a b c -> do
    a' <- mapM (mapPropM f) a
    b' <- mapTracesM f b
    f (Partial a' b' c)
  Success a b c d -> do
    a' <- mapM (mapPropM f) a
    b' <- mapTracesM f b
    c' <- mapExprM f c
    d' <- do
      let x = Map.toList d
      x' <- forM x $ \(k,v) -> do
        k' <- f k
        v' <- mapEContractM f v
        pure (k',v')
      pure $ Map.fromList x'
    f (Success a' b' c' d')
  ITE a b c -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    c' <- mapExprM f c
    f (ITE a' b' c')

  -- integers

  Add a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (Add a' b')
  Sub a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (Sub a' b')
  Mul a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (Mul a' b')
  Div a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (Div a' b')
  SDiv a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (SDiv a' b')
  Mod a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (Mod a' b')
  SMod a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (SMod a' b')
  AddMod a b c -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    c' <- mapExprM f c
    f (AddMod a' b' c')
  MulMod a b c -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    c' <- mapExprM f c
    f (MulMod a' b' c')
  Exp a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (Exp a' b')
  SEx a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (SEx a' b')
  Min a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (Min a' b')
  Max a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (Max a' b')

  -- booleans

  LT a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (LT a' b')
  GT a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (GT a' b')
  LEq a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (LEq a' b')
  GEq a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (GEq a' b')
  SLT a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (SLT a' b')
  SGT a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (SGT a' b')
  Eq a b ->  do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (Eq a' b')
  IsZero a -> do
    a' <- mapExprM f a
    f (IsZero a')

  -- bits

  And a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (And a' b')
  Or a b ->  do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (Or a' b')
  Xor a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (Xor a' b')
  Not a -> do
    a' <- mapExprM f a
    f (Not a')
  SHL a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (SHL a' b')
  SHR a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (SHR a' b')
  SAR a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (SAR a' b')


  -- Hashes

  Keccak a -> do
    a' <- mapExprM f a
    f (Keccak a')

  SHA256 a -> do
    a' <- mapExprM f a
    f (SHA256 a')

  -- block context

  Origin -> f Origin
  Coinbase -> f Coinbase
  Timestamp -> f Timestamp
  BlockNumber -> f BlockNumber
  PrevRandao -> f PrevRandao
  GasLimit -> f GasLimit
  ChainId -> f ChainId
  BaseFee -> f BaseFee
  BlockHash a -> do
    a' <- mapExprM f a
    f (BlockHash a')

  -- tx context

  TxValue -> f TxValue

  -- frame context

  Gas a b -> f (Gas a b)
  Balance a -> do
    a' <- mapExprM f a
    f (Balance a')

  -- code

  CodeSize a -> do
    a' <- mapExprM f a
    f (CodeSize a')
  CodeHash a -> do
    a' <- mapExprM f a
    f (CodeHash a')

  -- logs

  LogEntry a b c -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    c' <- mapM (mapExprM f) c
    f (LogEntry a' b' c')

  -- Contract Creation

  Create a b c d e g -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    c' <- mapExprM f c
    d' <- mapExprM f d
    e' <- mapM (mapExprM f) e
    g' <- mapExprM f g
    f (Create a' b' c' d' e' g')
  Create2 a b c d e g h -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    c' <- mapExprM f c
    d' <- mapExprM f d
    e' <- mapExprM f e
    g' <- mapM (mapExprM f) g
    h' <- mapExprM f h
    f (Create2 a' b' c' d' e' g' h')

  -- Calls

  Call a b c d e g h i j -> do
    a' <- mapExprM f a
    b' <- mapM (mapExprM f) b
    c' <- mapExprM f c
    d' <- mapExprM f d
    e' <- mapExprM f e
    g' <- mapExprM f g
    h' <- mapExprM f h
    i' <- mapM (mapExprM f) i
    j' <- mapExprM f j
    f (Call a' b' c' d' e' g' h' i' j')
  CallCode a b c d e g h i j -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    c' <- mapExprM f c
    d' <- mapExprM f d
    e' <- mapExprM f e
    g' <- mapExprM f g
    h' <- mapExprM f h
    i' <- mapM (mapExprM f) i
    j' <- mapExprM f j
    f (CallCode a' b' c' d' e' g' h' i' j')
  DelegeateCall a b c d e g h i j -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    c' <- mapExprM f c
    d' <- mapExprM f d
    e' <- mapExprM f e
    g' <- mapExprM f g
    h' <- mapExprM f h
    i' <- mapM (mapExprM f) i
    j' <- mapExprM f j
    f (DelegeateCall a' b' c' d' e' g' h' i' j')

  -- storage

  ConcreteStore a b -> do
    a' <- mapExprM f a
    f (ConcreteStore a' b)
  AbstractStore a -> f (AbstractStore a)
  SLoad a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (SLoad a' b')
  SStore a b c -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    c' <- mapExprM f c
    f (SStore a' b' c')

  -- buffers

  ConcreteBuf a -> do
    f (ConcreteBuf a)
  AbstractBuf a -> do
    f (AbstractBuf a)
  ReadWord a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (ReadWord a' b')
  ReadByte a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    f (ReadByte a' b')
  WriteWord a b c -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    c' <- mapExprM f c
    f (WriteWord a' b' c')
  WriteByte a b c -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    c' <- mapExprM f c
    f (WriteByte a' b' c')

  CopySlice a b c d e -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    c' <- mapExprM f c
    d' <- mapExprM f d
    e' <- mapExprM f e
    f (CopySlice a' b' c' d' e')

  BufLength a -> do
    a' <- mapExprM f a
    f (BufLength a')


mapPropM :: Monad m => (forall a . Expr a -> m (Expr a)) -> Prop -> m Prop
mapPropM f = \case
  PBool b -> pure $ PBool b
  PEq a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    pure $ PEq a' b'
  PLT a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    pure $ PLT a' b'
  PGT a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    pure $ PGT a' b'
  PLEq a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    pure $ PLEq a' b'
  PGEq a b -> do
    a' <- mapExprM f a
    b' <- mapExprM f b
    pure $ PGEq a' b'
  PNeg a -> do
    a' <- mapPropM f a
    pure $ PNeg a'
  PAnd a b -> do
    a' <- mapPropM f a
    b' <- mapPropM f b
    pure $ PAnd a' b'
  POr a b -> do
    a' <- mapPropM f a
    b' <- mapPropM f b
    pure $ POr a' b'
  PImpl a b -> do
    a' <- mapPropM f a
    b' <- mapPropM f b
    pure $ PImpl a' b'

mapEContractM :: Monad m => (forall a . Expr a -> m (Expr a)) -> Expr EContract -> m (Expr EContract)
mapEContractM _ g@(GVar _) = pure g
mapEContractM f (C code storage balance nonce) = do
  code' <- mapCodeM f code
  storage' <- mapExprM f storage
  balance' <- mapExprM f balance
  pure $ C code' storage' balance' nonce

mapContractM :: Monad m => (forall a . Expr a -> m (Expr a)) -> Contract -> m (Contract)
mapContractM f c = do
  code' <- mapCodeM f c.code
  storage' <- mapExprM f c.storage
  origStorage' <- mapExprM f c.origStorage
  balance' <- mapExprM f c.balance
  pure $ c { code = code', storage = storage', origStorage = origStorage', balance = balance' }

mapCodeM :: Monad m => (forall a . Expr a -> m (Expr a)) -> ContractCode -> m (ContractCode)
mapCodeM f = \case
  UnknownCode a -> fmap UnknownCode (f a)
  c@(RuntimeCode (ConcreteRuntimeCode _)) -> pure c
  RuntimeCode (SymbolicRuntimeCode c) -> do
    c' <- mapM (mapExprM f) c
    pure . RuntimeCode $ SymbolicRuntimeCode c'
  InitCode bs buf -> do
    buf' <- mapExprM f buf
    pure $ InitCode bs buf'

mapTracesM :: forall m . Monad m => (forall a . Expr a -> m (Expr a)) -> Traces -> m Traces
mapTracesM f (Traces a b) = do
  a' <- mapM (mapM (mapTraceM f)) a
  pure $ Traces a' b

mapSubStateM :: forall m . Monad m => (forall a . Expr a -> m (Expr a)) -> SubState -> m SubState
mapSubStateM f s = do
  selfdestructs <- mapM f s.selfdestructs
  touchedAccs <- mapM f s.touchedAccounts
  accessedAddrs <- do
    let x = Set.toList s.accessedAddresses
    x' <- mapM f x
    pure $ Set.fromList x'
  accessedKeys <- do
    let x = Set.toList s.accessedStorageKeys
    x' <- forM x $ \(e,slot) -> do
      e' <- f e
      pure (e',slot)
    pure $ Set.fromList x'
  refunds <- forM s.refunds $ \(e,v) -> do
    e' <- f e
    pure (e',v)
  pure $ SubState selfdestructs touchedAccs accessedAddrs accessedKeys refunds

mapTraceM :: forall m . Monad m => (forall a . Expr a -> m (Expr a)) -> Trace -> m Trace
mapTraceM f (Trace x y z) = do
  z' <- go z
  pure $ Trace x y z'
  where
    go :: TraceData -> m TraceData
    go = \case
      EventTrace a b c -> do
        a' <- mapExprM f a
        b' <- mapExprM f b
        c' <- mapM (mapExprM f) c
        pure $ EventTrace a' b' c'
      FrameTrace a -> do
        a' <- go' a
        pure $ FrameTrace a'
      ReturnTrace a b -> do
        a' <- mapExprM f a
        b' <- go' b
        pure $ ReturnTrace a' b'
      a -> pure a

    go' :: FrameContext -> m FrameContext
    go' = \case
      CreationContext a b c d -> do
        a' <- f a
        b' <- mapExprM f b
        c' <- forM (Map.toList c) $ \(k,v) -> do
          k' <- f k
          v' <- mapContractM f v
          pure (k', v')
        d' <- mapSubStateM f d
        pure $ CreationContext a' b' (Map.fromList c') d'
      CallContext a b c d e g h i j -> do
        a' <- mapExprM f a
        b' <- mapExprM f b
        e' <- mapExprM f e
        h' <- mapExprM f h
        i' <- forM (Map.toList i) $ \(k,v) -> do
          k' <- f k
          v' <- mapContractM f v
          pure (k', v')
        j' <- mapSubStateM f j
        pure $ CallContext a' b' c d e' g h' (Map.fromList i') j'

-- | Generic operations over AST terms
class TraversableTerm a where
  mapTerm  :: (forall b. Expr b -> Expr b) -> a -> a
  foldTerm :: forall c. Monoid c => (forall b. Expr b -> c) -> c -> a -> c


instance TraversableTerm (Expr a) where
  mapTerm = mapExpr
  foldTerm = foldExpr

instance TraversableTerm Prop where
  mapTerm = mapProp
  foldTerm = foldProp

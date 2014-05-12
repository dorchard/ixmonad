{-# LANGUAGE TypeFamilies, MultiParamTypeClasses, FlexibleInstances, GADTs, 
             EmptyDataDecls, UndecidableInstances, RebindableSyntax, OverlappingInstances, 
             DataKinds, TypeOperators, PolyKinds, NoMonomorphismRestriction, FlexibleContexts,
             AllowAmbiguousTypes, ScopedTypeVariables, FunctionalDependencies, ConstraintKinds, 
             InstanceSigs, IncoherentInstances #-}

module Control.IxMonad.State (Set(..), get, put, IxState(..), (:->)(..), (:!)(..),
                                  Eff(..), Effect(..), Var(..), union, UnionS, 
                                     Reads(..), Writes(..), Unionable, Sortable, SetLike, 
                                      StateSet, 
                                          --- may not want to export these
                                          Intersectable, UpdateReads, Sort, Split) where

import Control.IxMonad
import Control.IxMonad.Helpers.Mapping 
import Control.IxMonad.Helpers.Set hiding (Unionable, union, SetLike, Nub, Nubable(..))
import Prelude hiding (Monad(..),reads)
import GHC.TypeLits
import Data.Proxy
import Debug.Trace

-- Distinguish reads, writes, and read-writes
data Eff = R | W | RW

data Effect (s :: Eff) = Eff

instance Show (Effect R) where
    show _ = "R"
instance Show (Effect W) where
    show _ = "W"
instance Show (Effect RW) where
    show _ = "RW"

data (:!) (a :: *) (s :: Eff) = a :! (Effect s) 

instance (Show (Effect f), Show a) => Show (a :! f) where
    show (a :! f) = show a ++ " ! " ++ show f

infixl 3 :!

type SetLike s = Nub (Sort s)
type UnionS s t = Nub (Sort (Append s t))
type Unionable s t = (Sortable (Append s t), Nubable (Sort (Append s t)) (Nub (Sort (Append s t))),
                      Split s t (Union s t))

union :: (Unionable s t) => Set s -> Set t -> Set (UnionS s t)
union s t = nub (bsort (append s t))

-- Remove duplicates from a type-level list and turn different sorts into 'RW'
type family Nub t where
            Nub '[]       = '[]
            Nub '[e]      = '[e]
            Nub ((k :-> a :! s) ': (k :-> b :! s) ': as) = Nub ((k :-> b :! s) ': as)
            Nub ((k :-> a :! s) ': (k :-> a :! t) ': as) = Nub ((k :-> a :! RW) ': as)
            Nub ((k :-> a :! s) ': (j :-> b :! t) ': as) = (k :-> a :! s) ': Nub ((j :-> b :! t) ': as)


class Nubable t v where
    nub :: Set t -> Set v

instance Nubable '[] '[] where
    nub Empty = Empty

instance Nubable '[e] '[e] where
    nub (Ext e Empty) = (Ext e Empty)

instance Nubable ((k :-> b :! s) ': as) as' => 
          Nubable ((k :-> a :! s) ': (k :-> b :! s) ': as) as' where
    nub (Ext _ (Ext x xs)) = nub (Ext x xs)

instance Nubable ((k :-> a :! RW) ': as) as' => 
           Nubable ((k :-> a :! s) ': (k :-> a :! t) ': as) as' where
    nub (Ext _ (Ext (k :-> (a :! _)) xs)) = nub (Ext (k :-> (a :! (Eff::(Effect RW)))) xs)

instance Nubable ((j :-> b :! t) ': as) as' => 
             Nubable ((k :-> a :! s) ': (j :-> b :! t) ': as) ((k :-> a :! s) ': as') where
    nub (Ext (k :-> (a :! s)) (Ext (j :-> (b :! t)) xs)) = Ext (k :-> (a :! s)) (nub (Ext (j :-> (b :! t)) xs))


class UpdateReads t v where
    updateReads :: Set t -> Set v

instance UpdateReads '[] '[] where
    updateReads Empty = Empty

instance UpdateReads '[k :-> (a :! W)] '[] where
    updateReads (Ext e Empty) = Empty

instance UpdateReads '[e] '[e] where 
    updateReads (Ext e Empty) = Ext e Empty

instance UpdateReads ((k :-> b :! R) ': as) as' => UpdateReads ((k :-> a :! s) ': (k :-> b :! s) ': as) as' where
    updateReads (Ext _ (Ext (k :-> (b :! _)) xs)) = updateReads (Ext (k :-> (b :! (Eff::(Effect R)))) xs)

instance UpdateReads ((k :-> a :! R) ': as) as' => UpdateReads ((k :-> a :! W) ': (k :-> b :! R) ': as) as' where
    updateReads (Ext (k :-> (a :! _)) (Ext _ xs)) = updateReads (Ext (k :-> (a :! (Eff::(Effect R)))) xs)

instance UpdateReads ((k :-> b :! R) ': as) as' => UpdateReads ((k :-> a :! s) ': (k :-> b :! W) ': as) as' where
    updateReads (Ext _ (Ext (k :-> (b :! _)) xs)) = updateReads (Ext (k :-> (b :! (Eff::(Effect R)))) xs)

instance UpdateReads ((k :-> a :! R) ': as) as' => UpdateReads ((k :-> a :! RW) ': (k :-> a :! R) ': as) as' where
    updateReads (Ext (k :-> (a :! _)) (Ext _ xs)) = updateReads (Ext (k :-> (a :! (Eff::(Effect R)))) xs)

instance UpdateReads ((k :-> b :! R) ': as) as' => UpdateReads ((k :-> a :! R) ': (k :-> b :! RW) ': as) as' where
    updateReads (Ext _ (Ext (k :-> (b :! _)) xs)) = updateReads (Ext (k :-> (b :! (Eff::(Effect R)))) xs)

instance UpdateReads ((j :-> b :! s) ': as) as' => UpdateReads ((k :-> a :! W) ': (j :-> b :! s) ': as) as' where
    updateReads (Ext _ (Ext e xs)) = updateReads (Ext e xs)

instance UpdateReads ((j :-> b :! s) ': as) as' => UpdateReads ((k :-> a :! R) ': (j :-> b :! s) ': as) ((k :-> a :! R) ': as') where
    updateReads (Ext e (Ext e' xs)) = Ext e $ updateReads (Ext e' xs)

type Intersectable s t = (Sortable (Append s t), UpdateReads (Sort (Append s t)) t)

intersectReads :: (Sortable (Append s t), Intersectable s t) => Set s -> Set t -> Set t
intersectReads s t = updateReads (bsort (append s t))

-- Effect-parameterised state type

data IxState s a = IxS { runState :: Set (Reads s) -> (a, (Set (Writes s))) }

type family Reads t where
    Reads '[]                    = '[]
    Reads ((k :-> a :! R) ': xs)  = (k :-> a :! R) ': (Reads xs)
    Reads ((k :-> a :! RW) ': xs) = (k :-> a :! R) ': (Reads xs)
    Reads ((k :-> a :! W) ': xs)  = Reads xs

type family Writes t where
    Writes '[]                     = '[]
    Writes ((k :-> a :! W) ': xs)  = (k :-> a :! W) ': (Writes xs)
    Writes ((k :-> a :! RW) ': xs) = (k :-> a :! W) ': (Writes xs)
    Writes ((k :-> a :! R) ': xs)  = Writes xs

-- 'get/put' monadic primitives

get :: Var k -> IxState '[k :-> a :! R] a
get _ = IxS $ \(Ext (k :-> (a :! _)) Empty) -> (a, Empty)

put :: Var k -> a -> IxState '[k :-> a :! W] ()
put _ a = IxS $ \Empty -> ((), Ext (Var :-> a :! Eff) Empty)

type StateSet f = (StateSetProperties f, StateSetProperties (Reads f), StateSetProperties (Writes f))
                   
type StateSetProperties f = (Intersectable f '[], Intersectable '[] f,
                             UnionS f '[] ~ f, Split f '[] f, 
                             UnionS '[] f ~ f, Split '[] f f, 
                             UnionS f f ~ f, Split f f f,
                             Unionable f '[], Unionable '[] f)
                   
-- Indexed monad instance
instance IxMonad IxState where
    type Inv IxState s t = (Split (Reads s) (Reads t) (Reads (UnionS s t)), 
                            Unionable (Writes s) (Writes t), 
                            Intersectable (Writes s) (Reads t), 
                            Writes (UnionS s t) ~ UnionS (Writes s) (Writes t))
    type Unit IxState = '[]
    type Plus IxState s t = UnionS s t

    return x = IxS $ \Empty -> (x, Empty)

    (IxS e) >>= k = 
        IxS $ \i -> let (sR, tR) = split i
                        (a, sW)  = e sR
                        (b, tW) = (runState $ k a) (sW `intersectReads` tR)
                    in  (b, sW `union` tW) 

{-
instance Subeffect IxState where
    type Join IxState s t = Union s t
    type SubInv IxState s t = Split s t (Union s t)
    subEffect p (IxR e) = IxR $ \st -> let (s, t) = split st 
                                           _ = ReflP p t 
                                       in e s

-- Equality proof between a set and a proxy
data EqT a b where
    ReflP :: Proxy t -> Set t -> EqT t -}
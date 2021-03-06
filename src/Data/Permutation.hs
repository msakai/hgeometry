{-# LANGUAGE TemplateHaskell #-}
module Data.Permutation where

import           Control.Lens
import           Control.Monad.ST(runST)
import           Control.Monad(forM)
import           Data.Maybe(catMaybes)
import qualified Data.Vector as V
import qualified Data.Vector.Generic as GV
import qualified Data.Vector.Unboxed as UV
import qualified Data.Vector.Unboxed.Mutable as UMV
import qualified Data.Traversable as T
import qualified Data.Foldable as F

--------------------------------------------------------------------------------

-- | Orbits (Cycles) are represented by vectors
type Orbit a = V.Vector a

-- | Cyclic representation of a permutation
data Permutation a = Permutation { _orbits  :: V.Vector (Orbit a)
                                 , _indexes :: UV.Vector (Int,Int)
                                 }
                   deriving (Show,Eq)
makeLenses ''Permutation

instance Functor Permutation where
  fmap = T.fmapDefault

instance F.Foldable Permutation where
  foldMap = T.foldMapDefault

instance T.Traversable Permutation where
  traverse f (Permutation os is) = flip Permutation is <$> T.traverse (T.traverse f) os


elems :: Permutation a -> V.Vector a
elems = GV.concat . GV.toList . _orbits

size      :: Permutation a -> Int
size perm = GV.length (perm^.indexes)

-- | The cycle containing a given item
cycleOf        :: Enum a => Permutation a -> a -> Orbit a
cycleOf perm x = perm^.orbits.ix' (perm^.indexes.ix' (fromEnum x)._1)


-- | Next item in a cyclic permutation
next     :: GV.Vector v a => v a -> Int -> a
next v i = let n = GV.length v in v GV.! ((i+1) `mod` n)

-- | Lookup the indices of an element, i.e. in which orbit the item is, and the
-- index within the orbit.
lookupIdx        :: Enum a => Permutation a -> a -> (Int,Int)
lookupIdx perm x = perm^.indexes.ix' (fromEnum x)

-- | Apply the permutation, i.e. consider the permutation as a function.
apply        :: Enum a => Permutation a -> a -> a
apply perm x = let (c,i) = lookupIdx perm x
               in next (perm^.orbits.ix' c) i


-- | Find the cycle in the permutation starting at element s
orbitFrom     :: Eq a => a -> (a -> a) -> [a]
orbitFrom s p = s : (takeWhile (/= s) . tail $ iterate p s)

-- Given a vector with items in the permutation, and a permutation (by its
-- functional representation) construct the cyclic representation of the
-- permutation.
cycleRep        :: (GV.Vector v a, Enum a, Eq a) => v a -> (a -> a) -> Permutation a
cycleRep v perm = toCycleRep n $ runST $ do
    bv    <- UMV.replicate n False -- bit vector of marks
    morbs <- forM [0..(n - 1)] $ \i -> do
               m <- UMV.read bv (fromEnum $ v GV.! i)
               if m then pure Nothing -- already visited
                    else do
                      let xs = orbitFrom (v GV.! i) perm
                      markAll bv $ map fromEnum xs
                      pure . Just $ xs
    pure . catMaybes $ morbs
  where
    n  = GV.length v

    mark    bv i = UMV.write bv i True
    markAll bv   = mapM_ (mark bv)


-- | Given the size n, and a list of Cycles, turns the cycles into a
-- cyclic representation of the Permutation.
toCycleRep      :: Enum a => Int -> [[a]] -> Permutation a
toCycleRep n os = Permutation (V.fromList . map V.fromList $ os) ixes
  where
    f i c = zipWith (\x j -> (fromEnum x,(i,j))) c [0..]

    ixes' = concat $ zipWith f [0..] os
    ixes = UV.create $ do
             v <- UMV.new n
             mapM_ (uncurry $ UMV.write v) ixes'
             pure v

--------------------------------------------------------------------------------
-- * Helper stuff

-- | lens indexing into a vector
ix'   :: (GV.Vector v a, Index (v a) ~ Int, IxValue (v a) ~ a, Ixed (v a))
      => Int -> Lens' (v a) a
ix' i = singular (ix i)

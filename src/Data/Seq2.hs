module Data.Seq2 where

import           Prelude hiding (foldr,foldl,head,tail,last,length)

import           Control.Applicative
import qualified Data.List.NonEmpty as NonEmpty
import           Data.Semigroup


import qualified Data.Traversable as T
import qualified Data.Foldable as F
import qualified Data.Sequence as S

--------------------------------------------------------------------------------

-- | Basically Data.Sequence but with the guarantee that the list contains at
-- least two elements.
data Seq2 a = Seq2 a (S.Seq a) a
                deriving (Eq,Ord,Show,Read)


instance T.Traversable Seq2 where
  -- Applicative f => (a -> f b) -> t a -> f (t b)
  traverse f ~(Seq2 l s r) = Seq2 <$> f l <*> T.traverse f s <*>  f r

instance Functor Seq2 where
  fmap = T.fmapDefault

instance F.Foldable Seq2 where
  foldMap = T.foldMapDefault
  length ~(Seq2 _ s _) = 2 + S.length s

instance Semigroup (Seq2 a) where
  l <> r = l >< r

duo     :: a -> a -> Seq2 a
duo a b = Seq2 a S.empty b

length :: Seq2 a -> Int
length = F.length


-- | get the element with index i, counting from the left and starting at 0.
-- O(log(min(i,n-i)))
index                 :: Seq2 a -> Int -> a
index ~(Seq2 l s r) i
  | i == 0      = l
  | i < 1 + sz  = S.index s (i+1)
  | i == sz + 1 = r
  | otherwise   = error "index: index out of bounds."
    where
      sz = S.length s


(<|) :: a -> Seq2 a -> Seq2 a
x <| ~(Seq2 l s r) = Seq2 x (l S.<| s) r


(|>) :: Seq2 a -> a -> Seq2 a
~(Seq2 l s r) |> x = Seq2 l (s S.|> r) x


-- | Concatenate two sequences. O(log(min(n1,n2)))
(><) :: Seq2 a -> Seq2 a -> Seq2 a
s >< l = fromSeqUnsafe $ toSeq s S.>< toSeq l


-- | pre: the list contains at least two elements
fromList          :: [a] -> Seq2 a
fromList (a:b:xs) = F.foldl' (\s x -> s |> x) (duo a b) xs
fromList _        = error "Seq2.fromList: Not enough values"



-- | fmap but with an index
mapWithIndex                  :: (Int -> a -> b) -> Seq2 a -> Seq2 b
mapWithIndex f s@(Seq2 a m b) = Seq2 (f 0 a) (S.mapWithIndex f' m) (f l b)
  where
    l    = length s - 1
    f' i = f (i+1)


take   :: Int -> Seq2 a -> S.Seq a
take i = S.take i . toSeq


drop   :: Int -> Seq2 a -> S.Seq a
drop i = S.drop i . toSeq


toSeq               :: Seq2 a -> S.Seq a
toSeq ~(Seq2 a m b) = ((a S.<| m) S.|> b)


-- | Convert a Seq into a Seq2. It is not checked that the length is at least two
fromSeqUnsafe   :: S.Seq a -> Seq2 a
fromSeqUnsafe s = Seq2 a m b
  where
    ~(a S.:< s') = S.viewl s
    ~(m S.:> b)  = S.viewr s'


--------------------------------------------------------------------------------
-- | Left views

data ViewL2 a = a :<< ViewR1 a deriving (Show,Read,Eq,Ord)

-- | At least two elements
instance T.Traversable ViewL2 where
  traverse f ~(a :<< s) = (:<<) <$> f a <*> T.traverse f s

instance Functor ViewL2 where
  fmap = T.fmapDefault

instance F.Foldable ViewL2 where
  foldMap = T.foldMapDefault
  length ~(_ :<< s) = 1 + F.length s



-- | At least one element
data ViewL1 a = a :< S.Seq a deriving (Show,Read,Eq,Ord)

instance T.Traversable ViewL1 where
  traverse f ~(a :< s) = (:<) <$> f a <*> T.traverse f s

instance Functor ViewL1 where
  fmap = T.fmapDefault

instance F.Foldable ViewL1 where
  foldMap = T.foldMapDefault
  length ~(_ :< s) = 1 + S.length s

-- | We throw away information here; namely that the combined list contains two elements.
instance Semigroup (ViewL1 a) where
  ~(a :< s) <> ~(b :< t) = a :< (s <> S.singleton b <> t)


toNonEmpty           :: ViewL1 a -> NonEmpty.NonEmpty a
toNonEmpty ~(a :< s) = (a NonEmpty.:| F.toList s)

viewL1FromNonEmpty                     :: NonEmpty.NonEmpty a -> ViewL1 a
viewL1FromNonEmpty ~(x NonEmpty.:| xs) = x :< S.fromList xs


-- | O(1) get a left view
viewl                 :: Seq2 a -> ViewL2 a
viewl ~(Seq2 l s r) = l :<< (s :> r)


l1Singleton :: a -> ViewL1 a
l1Singleton = (:< S.empty)

viewL1toR1           :: ViewL1 a -> ViewR1 a
viewL1toR1 ~(l :< s) = let (s' S.:> r) = S.viewr (l S.<| s) in s' :> r


--------------------------------------------------------------------------------
-- | Right views

-- | A view of the right end of the seq, with the guarantee that it
-- has at least two elements
data ViewR2 a = ViewL1 a :>> a deriving (Show,Read,Eq,Ord)

instance T.Traversable ViewR2 where
  traverse f ~(s :>> a) = (:>>) <$> T.traverse f s <*> f a

instance Functor ViewR2 where
  fmap = T.fmapDefault

instance F.Foldable ViewR2 where
  foldMap = T.foldMapDefault
  length (s :>> _) = 1 + F.length s

-- | A view of the right end of the sequence, with the guarantee that it has at
-- least one element.
data ViewR1 a = S.Seq a :> a deriving (Show,Read,Eq,Ord)

instance T.Traversable ViewR1 where
  traverse f ~(s :> a) = (:>) <$> T.traverse f s <*> f a

instance Functor ViewR1 where
  fmap = T.fmapDefault

instance F.Foldable ViewR1 where
  foldMap = T.foldMapDefault
  length (s :> _) = 1 + S.length s


-- | O(1) get a right view
viewr                 :: Seq2 a -> ViewR2 a
viewr ~(Seq2 l s r) = (l :< s) :>> r

r1Singleton :: a -> ViewR1 a
r1Singleton = (S.empty :>)

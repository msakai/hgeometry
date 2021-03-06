module Algorithms.Geometry.DelaunayTriangulation.Naive where

import Algorithms.Geometry.DelaunayTriangulation.Types

import Control.Applicative
import Control.Monad(forM_)
import Control.Lens
import Data.Function(on)
import qualified Data.Foldable as F
import qualified Data.Vector as V
import qualified Data.Vector.Mutable as MV
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map as M
import qualified Data.CircularList as C
import Data.Ext
import Data.Geometry
import Data.Geometry.Ball(disk, insideBall)
import qualified Data.List as L


-- | Naive O(n^4) time implementation of the delaunay triangulation. Simply
-- tries each triple (p,q,r) and tests if it is delaunay, i.e. if there are no
-- other points in the circle defined by p, q, and r.
--
-- pre: the input is a *SET*, i.e. contains no duplicate points. (If the
-- input does contain duplicate points, the implementation throws them away)
delaunayTriangulation     :: (Ord r, Fractional r,       Show r, Show p)
                          => NonEmpty.NonEmpty (Point 2 r :+ p) -> Triangulation p r
delaunayTriangulation pts = Triangulation ptIds ptsV adjV
  where
    ptsV   = V.fromList . F.toList . NonEmpty.nubBy ((==) `on` (^.core)) $ pts
    ptIds  = M.fromList $ zip (map (^.core) . V.toList $ ptsV) [0..]
    adjV   = toAdjLists (ptIds,ptsV) . extractEdges $ fs
    n      = V.length ptsV - 1

    -- construct the list of faces/triangles in the delaunay triangulation
    fs = [ (p,q,r)
         | p <- [0..n], q <- [p..n], r <- [q..n], isDelaunay (ptIds,ptsV) p q r
         ]

-- | Given a list of edges, as vertexId pairs, construct a vector with the
-- adjacency lists, each in CW sorted order.
toAdjLists             :: (Num r, Ord r) => Mapping p r -> [(VertexID,VertexID)]
                       -> V.Vector (C.CList VertexID)
toAdjLists m@(_,ptsV) es = V.imap toCList $ V.create $ do
    v <- MV.replicate (V.length ptsV) []
    forM_ es $ \(i,j) -> do
      addAt v i j
      addAt v j i
    pure v
  where
    updateAt v i f = MV.read v i >>= \x -> MV.write v i (f x)
    addAt    v i j = updateAt v i (j:)

    -- convert to a CList, sorted in CCW order around point u
    toCList u = C.fromList . sortAround' m u

-- | Given a particular point u and a list of points vs, sort the points vs in
-- CW order around u.
-- running time: O(m log m), where m=|vs| is the number of vertices to sort.
sortAround'               :: (Num r, Ord r)
                          => Mapping p r -> VertexID -> [VertexID] -> [VertexID]
sortAround' (_,ptsV) u vs = reverse . map (^.extra) $ sortArround (f u) (map f vs)
  where
    f v = (ptsV V.! v)&extra .~ v

-- | Given a list of faces, construct a list of edges
extractEdges :: [(VertexID,VertexID,VertexID)] -> [(VertexID,VertexID)]
extractEdges = map head . L.group . L.sort
               . concatMap (\(p,q,r) -> [(p,q), (q,r), (p,r)])
               -- we encounter every edge twice. To get rid of the duplicates
               -- we sort, group, and take the head of the lists


-- | Test if the given three points form a triangle in the delaunay triangulation.
-- running time: O(n)
isDelaunay                :: (Fractional r, Ord r)
                          => Mapping p r -> VertexID -> VertexID -> VertexID -> Bool
isDelaunay (_,ptsV) p q r = case disk (pt p) (pt q) (pt r) of
    Nothing -> False -- if the points are colinear, we interpret this as: all
                     -- pts in the plane are in the circle.
    Just d  -> not $ any (`insideBall` d)
      [pt i | i <- [0..(V.length ptsV - 1)], i /= p, i /= q, i /= r]
   where
     pt i = (ptsV V.! i)^.core


myPoints :: NonEmpty.NonEmpty (Point 2 Rational :+ ())
myPoints = NonEmpty.fromList . map ext $
           [ point2 1  3
           , point2 4  26
           , point2 5  17
           , point2 6  7
           -- , point2 12 16
           -- , point2 19 4
           -- , point2 20 0
           -- , point2 20 11
           -- , point2 23 23
           -- , point2 31 14
           -- , point2 33 5
           ]

test = mapM_ print . edges . delaunayTriangulation $ myPoints

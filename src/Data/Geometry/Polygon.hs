{-# LANGUAGE ScopedTypeVariables  #-}
module Data.Geometry.Polygon where


import           Control.Applicative
import           Control.Lens hiding (Simple)
import           Data.Bifunctor
import           Data.Ext
import           Data.Semigroup
import qualified Data.Foldable as F
import           Data.Geometry.Box
import           Data.Geometry.Boundary
import           Data.Geometry.LineSegment
import           Data.Geometry.Point
import           Data.Geometry.Line
import           Data.Geometry.Properties
import           Data.Geometry.Transformation
import           Data.Maybe(mapMaybe)
import           Data.Proxy
import           Data.Range
import           Frames.CoRec(asA)
import qualified Data.CircularList as C
import           Linear.Vector(Additive(..), (^*), (^/))

--------------------------------------------------------------------------------
-- * Polygons

{- $setup
>>> :{
let simplePoly :: SimplePolygon () Rational
    simplePoly = SimplePolygon . C.fromList . map ext $ [ point2 0 0
                                                        , point2 10 0
                                                        , point2 10 10
                                                        , point2 5 15
                                                        , point2 1 11
                                                        ]
:} -}

-- | We distinguish between simple polygons (without holes) and Polygons with holes.
data PolygonType = Simple | Multi


data Polygon (t :: PolygonType) p r where
  SimplePolygon :: C.CList (Point 2 r :+ p)                         -> Polygon Simple p r
  MultiPolygon  :: C.CList (Point 2 r :+ p) -> [Polygon Simple p r] -> Polygon Multi  p r

type SimplePolygon = Polygon Simple

type MultiPolygon  = Polygon Multi

-- | Polygons are per definition 2 dimensional
type instance Dimension (Polygon t p r) = 2
type instance NumType   (Polygon t p r) = r

instance (Show p, Show r) => Show (Polygon t p r) where
  show (SimplePolygon vs)   = "SimplePolygon " <> show vs
  show (MultiPolygon vs hs) = "MultiPolygon " <> show vs <> " " <> show hs

instance (Eq p, Eq r) => Eq (Polygon t p r) where
  (SimplePolygon vs)   == (SimplePolygon vs')    = vs == vs'
  (MultiPolygon vs hs) == (MultiPolygon vs' hs') = vs == vs' && hs == hs'
  _                    == _                      = False

instance PointFunctor (Polygon t p) where
  pmap f (SimplePolygon vs)   = SimplePolygon (fmap (first f) vs)
  pmap f (MultiPolygon vs hs) = MultiPolygon  (fmap (first f) vs) (map (pmap f) hs)

instance Num r => IsTransformable (Polygon t p r) where
  transformBy = transformPointFunctor


-- * Functions on Polygons

outerBoundary :: forall t p r. Lens' (Polygon t p r) (C.CList (Point 2 r :+ p))
outerBoundary = lens get set
  where
    get                     :: Polygon t p r -> C.CList (Point 2 r :+ p)
    get (SimplePolygon vs)  = vs
    get (MultiPolygon vs _) = vs

    set                           :: Polygon t p r -> C.CList (Point 2 r :+ p) -> Polygon t p r
    set (SimplePolygon _)      vs = SimplePolygon vs
    set (MultiPolygon  _   hs) vs = MultiPolygon vs hs

holes :: forall p r. Lens' (Polygon Multi p r) [Polygon Simple p r]
holes = lens get set
  where
    get :: Polygon Multi p r -> [Polygon Simple p r]
    get (MultiPolygon _ hs) = hs
    set :: Polygon Multi p r -> [Polygon Simple p r] -> Polygon Multi p r
    set (MultiPolygon vs _) hs = MultiPolygon vs hs


-- | Get all holes in a polygon
holeList                     :: Polygon t p r -> [Polygon Simple p r]
holeList (SimplePolygon _)   = []
holeList (MultiPolygon _ hs) = hs


-- | The vertices in the polygon. No guarantees are given on the order in which
-- they appear!
vertices :: Polygon t p r -> [Point 2 r :+ p]
vertices (SimplePolygon vs)   = C.toList vs
vertices (MultiPolygon vs hs) = C.toList vs ++ concatMap vertices hs



fromPoints :: [Point 2 r :+ p] -> SimplePolygon p r
fromPoints = SimplePolygon . C.fromList

-- | The edges along the outer boundary of the polygon. The edges are half open.
outerBoundaryEdges :: Polygon t p r -> C.CList (LineSegment 2 p r)
outerBoundaryEdges = toEdges . (^.outerBoundary)


-- | Given the vertices of the polygon. Produce a list of edges. The edges are
-- half-open.
toEdges    :: C.CList (Point 2 r :+ p) -> C.CList (LineSegment 2 p r)
toEdges vs = let vs' = C.toList vs in
  C.fromList $ zipWith (\p q -> LineSegment (Closed p) (Open q)) vs' (tail vs' ++ vs')


-- | Test if q lies on the boundary of the polygon. Running time: O(n)
--
-- >>> point2 1 1 `onBoundary` simplePoly
-- False
-- >>> point2 0 0 `onBoundary` simplePoly
-- True
-- >>> point2 10 0 `onBoundary` simplePoly
-- True
-- >>> point2 5 13 `onBoundary` simplePoly
-- False
-- >>> point2 5 10 `onBoundary` simplePoly
-- False
-- >>> point2 10 5 `onBoundary` simplePoly
-- True
-- >>> point2 20 5 `onBoundary` simplePoly
-- False
--
-- TODO: testcases multipolygon
onBoundary        :: (Fractional r, Ord r) => Point 2 r -> Polygon t p r -> Bool
q `onBoundary` pg = any (q `onSegment`) es
  where
    out = SimplePolygon $ pg^.outerBoundary
    es = concatMap (C.toList . outerBoundaryEdges) $ out : holeList pg

-- | Check if a point lies inside a polygon, on the boundary, or outside of the polygon.
-- Running time: O(n).
--
-- >>> point2 1 1 `inPolygon` simplePoly
-- Inside
-- >>> point2 0 0 `inPolygon` simplePoly
-- OnBoundary
-- >>> point2 10 0 `inPolygon` simplePoly
-- OnBoundary
-- >>> point2 5 13 `inPolygon` simplePoly
-- Inside
-- >>> point2 5 10 `inPolygon` simplePoly
-- Inside
-- >>> point2 10 5 `inPolygon` simplePoly
-- OnBoundary
-- >>> point2 20 5 `inPolygon` simplePoly
-- Outside
--
-- TODO: Add some testcases with multiPolygons
-- TODO: Add some more onBoundary testcases
inPolygon                                :: forall t p r. (Fractional r, Ord r)
                                         => Point 2 r -> Polygon t p r
                                         -> PointLocationResult
q `inPolygon` pg
    | q `onBoundary` pg                             = OnBoundary
    | odd kl && odd kr && not (any (q `inHole`) hs) = Inside
    | otherwise                                     = Outside
  where
    l = horizontalLine $ q^.yCoord

    -- Given a line segment, compute the intersection point (if a point) with the
    -- line l
    intersectionPoint = asA (Proxy :: Proxy (Point 2 r)) . (`intersect` l)

    -- Count the number of intersections that the horizontal line through q
    -- maxes with the polygon, that are strictly to the left and strictly to
    -- the right of q. If these numbers are both odd the point lies within the polygon.
    --
    --
    -- note that: - by the asA (Point 2 r) we ignore horizontal segments (as desired)
    --            - by the filtering, we effectively limit l to an open-half line, starting
    --               at the (open) point q.
    --            - by using half-open segments as edges we avoid double counting
    --               intersections that coincide with vertices.
    --            - If the point is outside, and on the same height as the
    --              minimum or maximum coordinate of the polygon. The number of
    --              intersections to the left or right may be one. Thus
    --              incorrectly classifying the point as inside. To avoid this,
    --              we count both the points to the left *and* to the right of
    --              p. Only if both are odd the point is inside.  so that if
    --              the point is outside, and on the same y-coordinate as one
    --              of the extermal vertices (one ofth)
    --
    -- See http://geomalgorithms.com/a03-_inclusion.html for more information.
    SP kl kr = count (\p -> (p^.xCoord) `compare` (q^.xCoord))
             . mapMaybe intersectionPoint . C.toList . outerBoundaryEdges $ pg

    -- For multi polygons we have to test if we do not lie in a hole .
    inHole = insidePolygon
    hs     = holeList pg

    count   :: (a -> Ordering) -> [a] -> SP Int Int
    count f = foldr (\x (SP lts gts) -> case f x of
                             LT -> SP (lts + 1) gts
                             EQ -> SP lts       gts
                             GT -> SP lts       (gts + 1)) (SP 0 0)




data SP a b = SP !a !b


-- | Test if a point lies strictly inside the polgyon.
insidePolygon        :: (Fractional r, Ord r) => Point 2 r -> Polygon t p r -> Bool
q `insidePolygon` pg = q `inPolygon` pg == Inside


-- testQ = map (`inPolygon` testPoly) [ point2 1 1    -- Inside
--                                    , point2 0 0    -- OnBoundary
--                                    , point2 5 14   -- Inside
--                                    , point2 5 10   -- Inside
--                                    , point2 10 5   -- OnBoundary
--                                    , point2 20 5   -- Outside
--                                    ]

-- testPoly :: SimplePolygon () Rational
-- testPoly = SimplePolygon . C.fromList . map ext $ [ point2 0 0
--                                                   , point2 10 0
--                                                   , point2 10 10
--                                                   , point2 5 15
--                                                   , point2 1 11
--                                                   ]

-- | Compute the area of a polygon
area                        :: Fractional r => Polygon t p r -> r
area poly@(SimplePolygon _) = abs $ signedArea poly
area (MultiPolygon vs hs)   = area (SimplePolygon vs) - sum [area h | h <- hs]


-- | Compute the signed area of a simple polygon. The the vertices are in
-- clockwise order, the signed area will be negative, if the verices are given
-- in counter clockwise order, the area will be positive.
signedArea      :: Fractional r => SimplePolygon p r -> r
signedArea poly = x / 2
  where
    x = sum [ p^.core.xCoord * q^.core.yCoord - q^.core.xCoord * p^.core.yCoord
            | LineSegment' p q <- C.toList $ outerBoundaryEdges poly  ]


-- | Compute the centroid of a simple polygon.
centroid      :: Fractional r => SimplePolygon p r -> Point 2 r
centroid poly = Point $ sum' xs ^/ (6 * signedArea poly)
  where
    xs = [ (toVec p ^+^ toVec q) ^* (p^.xCoord * q^.yCoord - q^.xCoord * p^.yCoord)
         | LineSegment' (p :+ _) (q :+ _) <- C.toList $ outerBoundaryEdges poly  ]

    sum' = F.foldl' (^+^) zero


-- | Test if the outer boundary of the polygon is in clockwise or counter
-- clockwise order.
isCounterClockwise :: (Eq r, Fractional r) => Polygon t p r -> Bool
isCounterClockwise = (\x -> x == abs x) . signedArea . asSimplePolygon

-- | Orient the outer boundary to clockwise order
toClockwiseOrder   :: (Eq r, Fractional r) => Polygon t p r -> Polygon t p r
toClockwiseOrder p
  | isCounterClockwise p = p&outerBoundary %~ C.reverseDirection
  | otherwise            = p

-- | Convert a Polygon to a simple polygon by forgetting about any holes.
asSimplePolygon                        :: Polygon t p r -> SimplePolygon p r
asSimplePolygon poly@(SimplePolygon _) = poly
asSimplePolygon (MultiPolygon vs _)    = SimplePolygon vs

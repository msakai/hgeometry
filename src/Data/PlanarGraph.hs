{-# LANGUAGE TemplateHaskell #-}
module Data.PlanarGraph where

import Data.Ext
import Data.Permutation
import Data.Maybe
import Control.Monad(join, forM)
import Control.Lens
import qualified Data.Vector as V
import qualified Data.Vector.Generic as GV
import qualified Data.Vector.Unboxed.Mutable as UMV
import qualified Data.CircularList as C

--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- $setup
-- >>> :{
--  let
--    (aA:aB:aC:aD:aE:aG:_) = take 6 [Arc 0..]
--    myEmbedding = toCycleRep 12 [ [ Dart aA Negative
--                                  , Dart aC Positive
--                                  , Dart aB Positive
--                                  , Dart aA Positive
--                                  ]
--                                , [ Dart aE Negative
--                                  , Dart aB Negative
--                                  , Dart aD Negative
--                                  , Dart aG Positive
--                                  ]
--                                , [ Dart aE Positive
--                                  , Dart aD Positive
--                                  , Dart aC Negative
--                                  ]
--                                , [ Dart aG Negative
--                                  ]
--                                ]
--    myGraph = planarGraph myEmbedding
--    dart i s = Dart (Arc i) (read s)
-- :}

-- TODO: Add a fig. of the Graph


--------------------------------------------------------------------------------

newtype Arc s = Arc { _unArc :: Int } deriving (Eq,Ord,Enum,Bounded)
makeLenses ''Arc

instance Show (Arc s) where
  show (Arc i) = "Arc " ++ show i

data Direction = Negative | Positive deriving (Eq,Ord,Bounded,Enum)

instance Show Direction where
  show Positive = "+1"
  show Negative = "-1"

instance Read Direction where
  readsPrec _ "-1" = [(Negative,"")]
  readsPrec _ "+1" = [(Positive,"")]
  readsPrec _ _    = []

-- | Reverse the direcion
rev          :: Direction -> Direction
rev Negative = Positive
rev Positive = Negative

-- | A dart represents a bi-directed edge. I.e. a dart has a direction, however
-- the dart of the oposite direction is always present in the planar graph as
-- well.
data Dart s = Dart { _arc       :: !(Arc s)
                   , _direction :: !Direction
                   } deriving (Eq,Ord)
makeLenses ''Dart



instance Show (Dart s) where
  show (Dart a d) = "Dart (" ++ show a ++ ") " ++ show d

-- | Get the twin of this dart (edge)
--
-- >>> twin (dart 0 "+1")
-- Dart (Arc 0) -1
-- >>> twin (dart 0 "-1")
-- Dart (Arc 0) +1
twin            :: Dart s -> Dart s
twin (Dart a d) = Dart a (rev d)

-- | test if a dart is Positive
isPositive   :: Dart s -> Bool
isPositive d = d^.direction == Positive


instance Enum (Dart s) where
  toEnum x
    | even x    = Dart (Arc $ x `div` 2)       Positive
    | otherwise = Dart (Arc $ (x `div` 2) + 1) Negative
  -- get the back edge by adding one

  fromEnum (Dart (Arc i) d) = case d of
                                Positive -> 2*i
                                Negative -> 2*i + 1


-- | The space in which the graph lives
data World = Primal_ | Dual_ deriving (Show,Eq)

type family Dual (sp :: World) where
  Dual Primal_ = Dual_
  Dual Dual_   = Primal_


newtype VertexId s (w :: World) = VertexId { _unVertexId :: Int } deriving (Eq,Ord)

instance Show (VertexId s w) where
  show (VertexId i) = "VertexId " ++ show i






-- | A *connected* Planar graph with bidirected edges. I.e. the edges (darts) are
-- directed, however, for every directed edge, the edge in the oposite
-- direction is also in the graph.
--
-- The orbits in the embedding are assumed to be in counterclockwise order.
data PlanarGraph s (w :: World) v e f = PlanarGraph { _embedding  :: Permutation (Dart s)
                                                    , _vertexData :: V.Vector v
                                                    , _edgeData   :: V.Vector e
                                                    , _faceData   :: V.Vector f
                                                    }
                                      deriving (Show,Eq)
makeLenses ''PlanarGraph

-- | Construct a planar graph
planarGraph      :: Permutation (Dart s) -> PlanarGraph s Primal_ () () ()
planarGraph perm = PlanarGraph perm vData eData fData
  where
    d = size perm
    e = d `div` 2
    v = V.length (perm^.orbits)
    f = e - v + 2

    vData  = V.replicate v ()
    eData  = V.replicate d ()
    fData  = V.replicate f ()


-- | Enumerate all vertices
vertices   :: PlanarGraph s w v e f -> V.Vector (VertexId s w)
vertices g = fmap VertexId $ V.enumFromN 0 (V.length (g^.embedding.orbits)-1)

-- | Enumerate all darts
darts :: PlanarGraph s w v e f -> V.Vector (Dart s)
darts = elems . _embedding

-- | Enumerate all edges. We report only the Positive darts
edges :: PlanarGraph s w v e f -> V.Vector (Dart s)
edges = V.filter isPositive . darts




-- | The tail of a dart, i.e. the vertex this dart is leaving from
--
tailOf     :: Dart s -> PlanarGraph s w v e f -> VertexId s w
tailOf d g = VertexId . fst $ lookupIdx (g^.embedding) d

-- | The vertex this dart is heading in to
headOf   :: Dart s -> PlanarGraph s w v e f -> VertexId s w
headOf d = tailOf (twin d)

-- | All edges incident to vertex v, in counterclockwise order around v.
incidentEdges                :: VertexId s w -> PlanarGraph s w v e f
                             -> V.Vector (Dart s)
incidentEdges (VertexId v) g = g^.embedding.orbits.ix' v

-- | All incoming edges incident to vertex v, in counterclockwise order around v.
incomingEdges     :: VertexId s w -> PlanarGraph s w v e f -> V.Vector (Dart s)
incomingEdges v g = V.filter (not . isPositive) $ incidentEdges v g

-- | All outgoing edges incident to vertex v, in counterclockwise order around v.
outgoingEdges     :: VertexId s w -> PlanarGraph s w v e f -> V.Vector (Dart s)
outgoingEdges v g = V.filter isPositive $ incidentEdges v g

--------------------------------------------------------------------------------
-- * Access data

-- | Get the vertex data associated with a node. Note that updating this data may be
-- expensive!!
vDataOf              :: VertexId s w -> Lens' (PlanarGraph s w v e f) v
vDataOf (VertexId i) = vertexData.ix' i

-- | Edge data of a given dart
eDataOf   :: Dart s -> Lens' (PlanarGraph s w v e f) e
eDataOf d = edgeData.ix' (fromEnum d)

-- | Data of a face of a given face
fDataOf                       :: FaceId s w -> Lens' (PlanarGraph s w v e f) f
fDataOf (FaceId (VertexId i)) = faceData.ix' i


--------------------------------------------------------------------------------
-- * The Dual graph

-- | The dual of this graph
--
-- >>> :{
--  let fromList = V.fromList
--      answer = fromList [ fromList [dart 0 "-1"]
--                        , fromList [dart 2 "+1",dart 4 "+1",dart 1 "-1",dart 0 "+1"]
--                        , fromList [dart 1 "+1",dart 3 "-1",dart 2 "-1"]
--                        , fromList [dart 4 "-1",dart 3 "+1",dart 5 "+1",dart 5 "-1"]
--                        ]
--  in (dual myGraph)^.embedding.orbits == answer
-- :}
-- True
dual   :: PlanarGraph s w v e f -> PlanarGraph s (Dual w) f e v
dual g = let perm = g^.embedding
         in PlanarGraph (cycleRep (elems perm) (apply perm . twin))
                        (g^.faceData)
                        (g^.edgeData)
                        (g^.vertexData)

--
newtype FaceId s w = FaceId { _unFaceId :: VertexId s (Dual w) } deriving (Eq,Ord)

instance Show (FaceId s w) where
  show (FaceId (VertexId i)) = "FaceId " ++ show i

-- | Enumerate all faces in the planar graph
faces :: PlanarGraph s w v e f -> V.Vector (FaceId s w)
faces = fmap FaceId . vertices . dual

-- | The face to the left of the dart
--
-- >>> leftFace (dart 1 "+1") myGraph
-- FaceId 1
-- >>> leftFace (dart 1 "-1") myGraph
-- FaceId 2
-- >>> leftFace (dart 2 "+1") myGraph
-- FaceId 2
-- >>> leftFace (dart 0 "+1") myGraph
-- FaceId 0
leftFace     :: Dart s -> PlanarGraph s w v e f -> FaceId s w
leftFace d g = FaceId . headOf d $ dual g


-- | The face to the right of the dart
--
-- >>> rightFace (dart 1 "+1") myGraph
-- FaceId 2
-- >>> rightFace (dart 1 "-1") myGraph
-- FaceId 1
-- >>> rightFace (dart 2 "+1") myGraph
-- FaceId 1
-- >>> rightFace (dart 0 "+1") myGraph
-- FaceId 1
rightFace     :: Dart s -> PlanarGraph s w v e f -> FaceId s w
rightFace d g = FaceId . tailOf d $ dual g


-- | The darts bounding this face, for internal faces in clockwise order, for
-- the outer face in counter clockwise order.
--
--
boundary     :: FaceId s w -> PlanarGraph s w v e f -> V.Vector (Dart s)
boundary (FaceId v) g = incidentEdges v $ dual g



-- testG = planarGraph testPerm
-- testG' = dual testG



testPerm = let (a:b:c:d:e:g:_) = take 6 [Arc 0..]
           in toCycleRep 12 [ [ Dart a Negative
                              , Dart c Positive
                              , Dart b Positive
                              , Dart a Positive
                              ]
                            , [ Dart e Negative
                              , Dart b Negative
                              , Dart d Negative
                              , Dart g Positive
                              ]
                            , [ Dart e Positive
                              , Dart d Positive
                              , Dart c Negative
                              ]
                            , [ Dart g Negative
                              ]
                            ]
-- testx = (myAns, myAns == answer)
--   where
--    myAns = (dual $ planarGraph myEmbedding)^.embedding.orbits

--    (aA:aB:aC:aD:aE:aG:_) = take 6 [Arc 0..]
--    myEmbedding = toCycleRep 12 [ [ Dart aA Negative
--                                  , Dart aC Positive
--                                  , Dart aB Positive
--                                  , Dart aA Positive
--                                  ]
--                                , [ Dart aE Negative
--                                  , Dart aB Negative
--                                  , Dart aD Negative
--                                  , Dart aG Positive
--                                  ]
--                                , [ Dart aE Positive
--                                  , Dart aD Positive
--                                  , Dart aC Negative
--                                  ]
--                                , [ Dart aG Negative
--                                  ]
--                                ]
--    dart i s = Dart (Arc i) (read s)
--    fromList = V.fromList
--    answer = fromList [ fromList [dart 0 "-1"]
--                      , fromList [dart 2 "+1",dart 4 "+1",dart 1 "-1",dart 0 "+1"]
--                      , fromList [dart 1 "+1",dart 3 "-1",dart 2 "-1"]
--                      , fromList [dart 4 "-1",dart 3 "+1",dart 5 "+1",dart 5 "-1"]
--                      ]

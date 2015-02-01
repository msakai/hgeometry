{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE TemplateHaskell #-}

{-# LANGUAGE OverloadedStrings #-}
module Data.Geometry.Ipe.Types where

import           Control.Applicative
import           Control.Lens
import           Data.Proxy
import           Data.Vinyl



import           Data.Ext
import           Data.Geometry.Point
import           Data.Geometry.Transformation(Matrix)
import           Data.Geometry.Box(Rectangle)
import           Data.Geometry.Line

import           Data.Geometry.Ipe.Attributes
import           Data.Text(Text)
import           Data.TypeLevel.Filter

import           GHC.Exts

import           GHC.TypeLits

import qualified Data.Sequence as S
import qualified Data.Seq2     as S2

--------------------------------------------------------------------------------


type XmlTree = Text


type Layer = Text


-- | The definition of a view
-- make active layer into an index ?
data View = View { _layerNames      :: [Layer]
                 , _activeLayer     :: Layer
                 }
          deriving (Eq, Ord, Show)
makeLenses ''View


-- | for now we pretty much ignore these
data IpeStyle = IpeStyle { _styleName :: Maybe Text
                         , _styleData :: XmlTree
                         }
              deriving (Eq,Show,Read,Ord)
makeLenses ''IpeStyle

-- | The maybe string is the encoding
data IpePreamble  = IpePreamble { _encoding     :: Maybe Text
                                , _preambleData :: XmlTree
                                }
                  deriving (Eq,Read,Show,Ord)
makeLenses ''IpePreamble

type IpeBitmap = XmlTree

--------------------------------------------------------------------------------
-- | Image Objects


data Image r = Image { _imageData :: ()
                     , _rect      :: Rectangle () r
                     } deriving (Show,Eq,Ord)
makeLenses ''Image

--------------------------------------------------------------------------------
-- | Text Objects

data TextLabel r = Label Text (Point 2 r)
                 deriving (Show,Eq,Ord)

data MiniPage r = MiniPage Text (Point 2 r) r
                 deriving (Show,Eq,Ord)

width                  :: MiniPage t -> t
width (MiniPage _ _ w) = w

--------------------------------------------------------------------------------
-- | Ipe Symbols, i.e. Points

-- | A symbol (point) in ipe
data IpeSymbol r = Symbol { _symbolPoint :: Point 2 r
                          , _symbolName  :: Text
                          }
                 deriving (Show,Eq,Ord)
makeLenses ''IpeSymbol

-- | Example of an IpeSymbol. I.e. A symbol that expresses that the size is 'large'
sizeSymbol :: SymbolAttribute Int Size
sizeSymbol = SymbolAttribute . IpeSize $ Named "large"

--------------------------------------------------------------------------------
-- | Paths

-- | Paths consist of Path Segments. PathSegments come in the following forms:
data PathSegment r = PolyLineSegment        (PolyLine 2 () r)
                     -- TODO
                   | PolygonPath
                   | CubicBezierSegment     -- (CubicBezier 2 r)
                   | QuadraticBezierSegment -- (QuadraticBezier 2 r)
                   | EllipseSegment
                   | ArcSegment
                   | SplineSegment          -- (Spline 2 r)
                   | ClosedSplineSegment    -- (ClosedSpline 2 r)
                   deriving (Show,Eq,Ord)
makePrisms ''PathSegment

-- | A path is a non-empty sequence of PathSegments.
newtype Path r = Path { _pathSegments :: S2.ViewL1 (PathSegment r) }
                 deriving (Show,Eq,Ord)
makeLenses ''Path


-- | type that represents a path in ipe.
data Operation r = MoveTo (Point 2 r)
                 | LineTo (Point 2 r)
                 | CurveTo (Point 2 r) (Point 2 r) (Point 2 r)
                 | QCurveTo (Point 2 r) (Point 2 r)
                 | Ellipse (Matrix 3 3 r)
                 | ArcTo (Matrix 3 3 r) (Point 2 r)
                 | Spline [Point 2 r]
                 | ClosedSpline [Point 2 r]
                 | ClosePath
                 deriving (Eq, Show)
makePrisms ''Operation

--------------------------------------------------------------------------------
-- | Group Attributes

-- | Now that we know what a Path is we can define the Attributes of a Group.
type family GroupAttrElf (s :: GroupAttributeUniverse) (r :: *) :: * where
  GroupAttrElf Clip r = Path r -- strictly we event want this to be a closed path I guess

newtype GroupAttribute r s = GroupAttribute (GroupAttrElf s r)

--------------------------------------------------------------------------------

-- | Poly kinded, type-level, tuples
data (a :: ka) :.: (b :: kb)

data IpeObjectType t = IpeGroup     t
                     | IpeImage     t
                     | IpeTextLabel t
                     | IpeMiniPage  t
                     | IpeUse       t
                     | IpePath      t
                     deriving (Show,Read,Eq)






type Group gt r = Rec (IpeObject r) gt


type family IpeObjectElF r (f :: IpeObjectType k) :: * where
  IpeObjectElF r (IpeGroup (gt :.: gs)) = Group gt r  :+ Rec (GroupAttribute     r) gs
  IpeObjectElF r (IpeImage is)          = Image r     :+ Rec (CommonAttribute    r) is
  IpeObjectElF r (IpeTextLabel ts)      = TextLabel r :+ Rec (TextLabelAttribute r) ts
  IpeObjectElF r (IpeMiniPage mps)      = MiniPage r  :+ Rec (MiniPageAttribute  r) mps
  IpeObjectElF r (IpeUse  ss)           = IpeSymbol r :+ Rec (SymbolAttribute    r) ss
  IpeObjectElF r (IpePath ps)           = Path r      :+ Rec (PathAttribute      r) ps


newtype IpeObject r (fld :: IpeObjectType k) =
  IpeObject { _ipeObject :: IpeObjectElF r fld }

makeLenses ''IpeObject



-- data IpeObject gt gs is ts mps ss ps r =
--     IpeGroup     (Group gt r  :+ Rec GroupAttrs     gs)
--   | IpeImage     (Image r     :+ Rec CommonAttrs    is)
--   | IpeTextLabel (TextLabel r :+ Rec TextLabelAttrs ts)
--   | IpeMiniPage  (MiniPage r  :+ Rec MiniPageAttrs  mps)
--   | IpeUse       (IpeSymbol r :+ Rec SymbolAttrs    ss)
--   | IpePath      (Path r      :+ Rec PathAttrs      ps)
    -- deriving (Show,Eq)

-- deriving instance (Show (Group gt r), Show (Rec GroupAttrs gs)) =>
--                   Show (IpeObject gt gs is ts mps ss ps r)

--------------------------------------------------------------------------------

-- | Poly kinded 7 tuple
-- data T7 (a :: ka) (b :: kb) (c :: kc) (d :: kd) (e :: ke) (f :: kf) (g :: kg) = T7
--         deriving (Show,Read,Eq,Ord)


symb'' :: IpeObjectElF Int (IpeUse '[Size])
symb'' = Symbol origin "myLargesymbol"  :+ ( sizeSymbol :& RNil )

symb :: IpeObjectElF Int (IpeUse ('[] :: [SymbolAttributeUniverse]))
symb = Symbol origin "foo" :+ RNil

symb' :: IpeObject Int (IpeUse '[Size])
symb' = IpeObject symb''

gr :: Group '[IpeUse '[Size]] Int
gr = symb' :& RNil

grr :: IpeObjectElF Int (IpeGroup ('[IpeUse '[Size]]
                                   :.:
                                   ('[] :: [GroupAttributeUniverse])
                                  )
                        )
grr = gr :+ RNil


grrr :: IpeObject Int (IpeGroup ('[IpeUse '[Size]] :.:
                                      ('[] :: [GroupAttributeUniverse])
                                )
                      )
grrr = IpeObject grr


points' :: forall gt r. Group gt r -> [Point 2 r]
points' = fmap (^.ipeObject.core.symbolPoint) . filterRec'

filterRec' :: forall gt r fld. (fld ~ IpeUse '[Size]) =>
              Rec (IpeObject r) gt -> [IpeObject r fld]
filterRec' = undefined
-- filterRec' = filterRec (Proxy :: Proxy fld)

--------------------------------------------------------------------------------

newtype Group' gs r = Group' (Group gs r)

-- | Represents a page in ipe
data IpePage gs r = IpePage { _layers :: [Layer]
                            , _views  :: [View]
                            , _pages  :: Group' gs r
                            }
              -- deriving (Eq, Show)
makeLenses ''IpePage

newtype Page r gs = Page { _unP :: Page gs r }

type IpePages gss r = Rec (Page r) gss



-- | A complete ipe file
data IpeFile gs r = IpeFile { _preamble :: Maybe IpePreamble
                            , _styles   :: [IpeStyle]
                            , _ipePages :: IpePages gs r
                            }
                  -- deriving (Eq,Show)

makeLenses ''IpeFile

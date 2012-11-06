{-# LANGUAGE TypeFamilies, BangPatterns #-}
module Data.Graph.PatriciaTree (
  DenseVertexGraph,
  SparseVertexGraph
  ) where

import Data.IntMap ( IntMap )
import qualified Data.IntMap as IM
import Data.Maybe ( fromMaybe )
import Data.Monoid

import Data.Graph.Interface
import Data.Graph.Marker.Dense
import Data.Graph.Marker.Sparse

data Ctx (k :: * -> *) a b = Ctx !(IntMap b) a !(IntMap b)
data Gr (k :: * -> *) a b = Gr { graphRepr :: IntMap (Ctx k a b) }

type DenseVertexGraph = Gr DenseMarker
type SparseVertexGraph = Gr SparseMarker

instance (MarksVertices k) => Graph (Gr k n e) where
  type VertexLabel (Gr k n e) = n
  type EdgeLabel (Gr k n e) = e
  type VertexMarker (Gr k n e) = k

  empty = Gr IM.empty
  isEmpty = IM.null . graphRepr

instance (MarksVertices k) => InspectableGraph (Gr k n e) where
  context (Gr g) v = do
    Ctx p l s <- IM.lookup v g
    return $! Context (toAdj p) v l (toAdj s)

toAdj :: IntMap b -> [(Vertex, b)]
toAdj = IM.toList

instance (MarksVertices k) => DecomposableGraph (Gr k n e) where
  match v g = do
    c <- context g v
    return (c, removeVertex v g)

instance (MarksVertices k) => IncidenceGraph (Gr k n e) where
  out g v = fromMaybe [] $ do
    Context _ src _ s <- context g v
    return $ map (toEdge src) s
    where
      toEdge src (dst, lbl) = Edge src dst lbl

instance (MarksVertices k) => BidirectionalGraph (Gr k n e) where
  inn g v = fromMaybe [] $ do
    Context p dst _ _ <- context g v
    return $ map (toEdge dst) p
    where
      toEdge dst (src, lbl) = Edge src dst lbl

instance (MarksVertices k) => AdjacencyGraph (Gr k n e) where
  foldSuc f seed (Gr gr) v = fromMaybe seed $ do
    Ctx _ _ s <- IM.lookup v gr
    return $ IM.foldrWithKey' f seed s

instance (MarksVertices k) => BidirectionalAdjacencyGraph (Gr k n e) where
  foldPre f seed (Gr gr) v = fromMaybe seed $ do
    Ctx p _ _ <- IM.lookup v gr
    return $ IM.foldrWithKey' f seed p

instance (MarksVertices k) => VertexListGraph (Gr k n e) where
  labeledVertices = IM.foldrWithKey' toLabV [] . graphRepr
    where
      toLabV vid (Ctx _ l _) acc = (vid, l) : acc
  vertices = IM.keys . graphRepr
  numVertices = IM.size . graphRepr

instance (MarksVertices k) => EdgeListGraph (Gr k n e) where
  edges = IM.foldrWithKey' toEdges [] . graphRepr
    where
      toEdges src (Ctx _ _ ss) acc =
        IM.foldrWithKey' (toEdge src) acc ss
      toEdge src dst lbl acc = Edge src dst lbl : acc

instance (MarksVertices k) => AdjacencyMatrix (Gr k n e) where
  edgeExists (Gr g) src dst =
    fromMaybe [] $ do
      Ctx _ _ ss <- IM.lookup src g
      lbl <- IM.lookup dst ss
      return [lbl]

instance (MarksVertices k) => MutableGraph (Gr k n e) where
  insertVertex v lbl (Gr g) =
    case IM.lookup v g of
      Nothing -> Just $ Gr (IM.insert v (Ctx mempty lbl mempty) g)
      Just _ -> Nothing

  insertEdge src dst lbl (Gr g) = do
    Ctx sps slbl sss <- IM.lookup src g
    Ctx dps dlbl dss <- IM.lookup dst g
    case IM.member dst sss of
      True -> Nothing
      False -> do
        let !sss' = IM.insert dst lbl sss
            !dps' = IM.insert src lbl dps
            !g1 = IM.insert src (Ctx sps slbl sss') g
            !g2 = IM.insert dst (Ctx dps' dlbl dss) g1
        return (Gr g2, Edge src dst lbl)

  removeVertex vid g =
    let Gr g1 = clearVertex vid g
        g2 = IM.delete vid g1
    in Gr g2

  clearVertex v g@(Gr g0) =
    fromMaybe g $ do
      Ctx ps lbl ss <- IM.lookup v g0
      let !g1 = foldr (IM.adjust (removeSucc v)) g0 (IM.keys ps)
          !g2 = foldr (IM.adjust (removePred v)) g1 (IM.keys ss)
          !g3 = IM.insert v (Ctx mempty lbl mempty) g2
      return (Gr g3)
    where
      removeSucc vid (Ctx ps lbl ss) = Ctx ps lbl (IM.delete vid ss)
      removePred vid (Ctx ps lbl ss) = Ctx (IM.delete vid ps) lbl ss

  removeEdge (Edge src dst lbl) g@(Gr gr) =
    fromMaybe g $ do
      Ctx ps slbl ss <- IM.lookup src gr
      Ctx pps dlbl pss <- IM.lookup dst gr
      elbl <- IM.lookup dst ss
      case elbl == lbl of
        False -> Nothing
        True -> do
          let !g1 = IM.insert src (Ctx ps slbl (IM.delete dst ss)) gr
              !g2 = IM.insert dst (Ctx (IM.delete src pps) dlbl pss) g1
          return (Gr g2)

  removeEdges src dst g@(Gr gr) =
    fromMaybe g $ do
      Ctx ps slbl ss <- IM.lookup src gr
      Ctx pps dlbl pss <- IM.lookup dst gr
      let !g1 = IM.insert src (Ctx ps slbl (IM.delete dst ss)) gr
          !g2 = IM.insert dst (Ctx (IM.delete src pps) dlbl pss) g1
      return (Gr g2)

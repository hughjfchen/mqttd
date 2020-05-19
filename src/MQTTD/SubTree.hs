module MQTTD.SubTree (
  SubTree, modify, add, find, findMap, flatten, fromList
  ) where

import           Data.Map.Strict    (Map)
import qualified Data.Map.Strict    as Map
import           Data.Text          (intercalate, splitOn)

import           Network.MQTT.Topic (Filter, Topic)

-- | MQTT Topic Subscription tree.
data SubTree a = SubTree {
  subs     :: Maybe a,
  children :: Map Filter (SubTree a)
  } deriving (Show, Eq)

instance Functor SubTree where
  fmap f SubTree{..} = SubTree (f <$> subs) ((fmap.fmap) f children)

instance Foldable SubTree where
  foldMap f SubTree{..} = maybe mempty f subs <> (foldMap.foldMap) f children

instance Traversable SubTree where
  traverse f SubTree{..} = SubTree <$> traverse f subs <*> (traverse.traverse) f children

instance Semigroup a => Semigroup (SubTree a) where
  a <> b = SubTree (subs a <> subs b) (Map.unionWith (<>) (children a) (children b))

instance Monoid a => Monoid (SubTree a) where
  mempty = SubTree mempty mempty

-- | Modify a subscription for the given filter.
--
-- This will create structure along the path and will not clean up any
-- unused structure.
modify :: Monoid a => Filter -> (Maybe a -> Maybe a) -> SubTree a -> SubTree a
modify top f = go (splitOn "/" top)
  where
    go [] n@SubTree{..}     = n{subs=f subs}
    go (x:xs) n@SubTree{..} = n{children=Map.alter (fmap (go xs) . maybe (Just mempty) Just) x children}

-- | Add a value at the given filter path.
add :: Monoid a => Filter -> a -> SubTree a -> SubTree a
add top i = modify top (Just . (i<>) . maybe mempty id)

-- | Find all matching subscribers
findMap :: Monoid m => Topic -> (a -> m) -> SubTree a -> m
findMap top f = go (splitOn "/" top)
  where
    go [] SubTree{subs} = maybe mempty f subs
    go (x:xs) SubTree{children} = maybe mempty (go xs)                 (Map.lookup x children)
                               <> maybe mempty (go xs)                 (Map.lookup "+" children)
                               <> maybe mempty (maybe mempty f . subs) (Map.lookup "#" children)

-- | Find subscribers of a given topic.
find :: Monoid a => Topic -> SubTree a -> a
find top = findMap top id

-- | flatten a SubTree to a list of (topic,a) pairs.
flatten :: SubTree a -> [(Filter, a)]
flatten = Map.foldMapWithKey (\k sn -> go [k] sn) . children
  where
    go ks SubTree{..} = [(intercalate "/" (reverse ks), s) | s <- maybe [] (:[]) subs]
                        <> Map.foldMapWithKey (\k sn -> go (k:ks) sn) children

-- | Construct a SubTree from a list of filters and subscribers.
fromList :: Monoid a => [(Filter, a)] -> SubTree a
fromList = foldr (uncurry add) mempty

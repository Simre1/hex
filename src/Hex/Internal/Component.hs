{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TemplateHaskell #-}

module Hex.Internal.Component where

-- import Data.HashTable.IO as H

import Control.Monad.IO.Class
-- import Data.Map.Strict qualified as M

import Data.Coerce
import Data.IORef
import Data.Kind
import Data.Map qualified as M
import Data.Proxy
import Data.SparseSet.Storable
import Data.SparseSet.Storable qualified as SV
import Data.Vector.Mutable qualified as V
import Data.Vector.Storable (Storable)
import Hex.Internal.Component.ComponentId
import Hex.Internal.Entity
import Type.Reflection
import Unsafe.Coerce

newtype ComponentId = ComponentId {unwrapComponentId :: Int} deriving (Show)

class (ComponentStore component (Store component), Typeable component) => Component component where
  type Store component :: Type -> Type

type Store' component = Store component component

class ComponentStore component store where
  makeStore :: MaxEntities -> IO (store component)
  storeContains :: store component -> Entity -> IO Bool
  storeGet :: store component -> Entity -> IO component
  storePut :: store component -> Entity -> component -> IO ()
  storeDelete :: store component -> Entity -> IO ()
  storeFor :: store component -> (Entity -> component -> IO ()) -> IO ()
  storeMembers :: store component -> IO Int

newtype WrappedStorage = WrappedStorage (forall component. Store' component)

unwrapWrappedStorage :: forall component. WrappedStorage -> Store' component
unwrapWrappedStorage (WrappedStorage s) = s @component

data Stores = Stores (IORef (V.IOVector WrappedStorage)) (IORef (M.Map SomeTypeRep ComponentId))

addStore :: forall component. Component component => Stores -> Store' component -> IO ComponentId
addStore (Stores storeVecRef mappingsRef) store = do
  mappings <- readIORef mappingsRef
  storeVec <- readIORef storeVecRef
  let rep = someTypeRep $ Proxy @component
      maybeMapping = M.lookup rep mappings
      wrappedStore = (WrappedStorage $ unsafeCoerce store)
  case maybeMapping of
    Nothing -> do
      let newId = M.size mappings
          storeSize = V.length storeVec
      if newId < storeSize
        then V.unsafeWrite storeVec newId wrappedStore
        else do
          newStoreVec <- V.grow storeVec (storeSize `quot` 2)
          V.unsafeWrite newStoreVec newId wrappedStore
          writeIORef storeVecRef newStoreVec
      modifyIORef mappingsRef $ M.insert rep (ComponentId newId)
      pure $ ComponentId newId
    Just i -> V.unsafeWrite storeVec (unwrapComponentId i) wrappedStore *> pure i

addComponentStore :: forall component. (Component component) => Stores -> MaxEntities -> IO ComponentId
addComponentStore stores@(Stores storeVec mappings) max = do
  store <- makeStore @component max
  addStore @component stores store

getStore :: forall component. Stores -> ComponentId -> IO (Store' component)
getStore (Stores storeVecRef _) componentId =
  readIORef storeVecRef >>= \vec -> unwrapWrappedStorage @component <$> V.unsafeRead vec (unwrapComponentId componentId)

getComponentId :: forall component. (ComponentStore component (Store component), Component component) => Stores -> MaxEntities -> IO ComponentId
getComponentId stores@(Stores _ mappingsRef) max = do
  maybeComponent <- M.lookup (someTypeRep $ Proxy @component) <$> readIORef mappingsRef
  case maybeComponent of
    Just componentId -> pure componentId
    Nothing -> do
      store <- makeStore @component max
      componentId <- addStore @component stores store
      pure componentId

newStores :: IO Stores
newStores = Stores <$> (V.new 10 >>= newIORef) <*> newIORef M.empty

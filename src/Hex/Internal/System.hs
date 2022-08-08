module Hex.Internal.System where

import Control.Monad.IO.Class
import Control.Monad.Trans.Class
import Control.Monad.Trans.Reader
import Hex.Internal.Component
import Hex.Internal.Entity
import Hex.Internal.Query
import Hex.Internal.World
import UnliftIO

newtype System m a = System (ReaderT World m a) deriving (Functor, Applicative, Monad, MonadIO, MonadTrans)

askWorld :: Monad m => System m World
askWorld = System ask
{-# INLINE askWorld #-}

askStore :: forall component m. (MonadIO m, Component component) => Monad m => System m (Store component)
askStore = askWorld >>= liftIO . worldComponentStorage @component
{-# INLINE askStore #-}

query :: (Monoid a, MonadIO m, MPS components) => (components -> QueryBody a) -> System m a
query f = askWorld >>= lift . flip worldQuery f
{-# INLINE query #-}

query_ :: (MonadIO m, MPS components) => (components -> QueryBody ()) -> System m ()
query_ f = askWorld >>= lift . flip worldQuery_ f
{-# INLINE query_ #-}

cMap :: (MPS a, MPS b, MonadIO m) => (a -> b) -> System m ()
cMap f = query_ $ \a -> qPut (f a)
{-# INLINE cMap #-}

cMapM :: (MPS a, MPS b, MonadIO m, MonadUnliftIO m) => (a -> m b) -> System m ()
cMapM f = do
  w <- askWorld
  lift $
    withRunInIO $ \unlift -> worldQuery_ w $ \a -> do
      b <- liftIO $ unlift $ f a
      qPut b
{-# INLINE cMapM #-}

cFold :: (Monoid r, MPS a, MonadIO m) => (a -> r) -> System m r
cFold f = query $ \a -> pure $ f a 

cFoldM :: (Monoid r, MPS a, MonadIO m, MonadUnliftIO m) => (a -> m r) -> System m r
cFoldM f = do
  w <- askWorld
  lift $ withRunInIO $ \unlift -> worldQuery w $ \a -> liftIO $ unlift (f a) 

newEntity' :: MonadIO m => System m Entity
newEntity' = askWorld >>= liftIO . worldNewEntity
{-# INLINE newEntity' #-}


newEntity :: (MPS a, MonadIO m) => a -> System m Entity
newEntity a = do
  e <- newEntity' 
  putEntity e a
  pure e
{-# INLINE newEntity #-}


putEntity :: forall a m. (MonadIO m, MPS a) => Entity -> a -> System m ()
putEntity entity a = do
  w <- askWorld
  liftIO $ multiPut @(S a) w entity a
{-# INLINE putEntity #-}

runSystem :: World -> System m a -> m a
runSystem w (System r) = runReaderT r w
{-# INLINE runSystem #-}

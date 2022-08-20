{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE UndecidableInstances #-}

module Hero.System.ComponentFunctions where

import Control.Arrow (Arrow (arr, (***)))
import Control.Category (Category (..))
import Control.Monad (void, when, (<$!>))
import Control.Monad.IO.Class (MonadIO (..))
import Data.Coerce (Coercible, coerce)
import Data.Functor ((<&>))
import Data.IORef
  ( modifyIORef,
    modifyIORef',
    newIORef,
    readIORef,
  )
import Hero.Component.Capabilities
    ( ComponentIterate(..),
      ComponentDelete(..),
      ComponentPut(..),
      ComponentGet(..) )
import Hero.Component.Component
    ( Store', Component(..), ComponentStore(componentEntityDelete) )
import Hero.Entity (Entity, entitiesAmount, entitiesDelete, entitiesFor)
import Hero.System.System (System (..))
import Hero.World qualified as World
import Prelude hiding ((.))
import Optics.Core
import qualified Hero.Component.Store.AllStores as AllStores

-- | Low-level store setup used when implementing a custom `withStoreConfig`. Each store may only be set up once!
addStore :: (Applicative m, Component component) => Store' component -> System m i i
addStore store = System $ \w -> do
  World.addStore w store
  pure $ pure

-- | Iterates over all entities with the requested components and sets the components calculated by the
-- given function
cmap ::
  forall a b m i.
  (QCI a, QCP b, MonadIO m) =>
  (a -> b) ->
  System m i ()
cmap f =
  System
    ( \w -> do
        for <- queryFor @(S a) @a w
        put <- queryPut @(S b) @b w
        pure $ \_ -> for $ \e a -> liftIO $ put e $! (f a)
    )

-- | Iterates over all entities with the requested components and sets the components calculated by the
-- given function
cmap' ::
  forall a b i m.
  (QCI a, QCP b, MonadIO m) =>
  (i -> a -> b) ->
  System m i ()
cmap' f =
  System
    ( \w -> do
        for <- queryFor @(S a) @a w
        put <- queryPut @(S b) @b w
        pure $ \i -> for $ \e a -> liftIO $ put e $! (f i a)
    )

-- | Iterates over all entities with the requested components and sets the components calculated by the
-- given monadic function
cmapM :: forall a b i m. (QCI a, QCP b, MonadIO m) => (a -> m b) -> System m i ()
cmapM f =
  System
    ( \w -> do
        for <- queryFor @(S a) @a w
        put <- queryPut @(S b) @b w
        pure $ \_ -> for $ \e a -> f a >>= liftIO . put e
    )

-- | Iterates over all entities with the requested components and sets the components calculated by the
-- given monadic function
cmapM' :: forall a b i m. (QCI a, QCP b, MonadIO m) => (i -> a -> m b) -> System m i ()
cmapM' f =
  System
    ( \w -> do
        for <- queryFor @(S a) @a w
        put <- queryPut @(S b) @b w
        pure $ \i -> for (\e a -> f i a >>= liftIO . put e)
    )

-- | Iterates over all entities with the requested components and folds the components.
cfold :: forall a o m i. (Monoid o, QCI a, MonadIO m) => (a -> o) -> System m i o
cfold f = System $ \w -> do
  for <- queryFor @(S a) @a w
  members <- queryMembers @(S a) @a w
  pure $! \i2 -> do
    ref <- liftIO $ newIORef (mempty :: o)
    for $! \e a -> do
      let o = f a
      liftIO $ modifyIORef' ref (<> o)
    liftIO $ readIORef ref

-- | Iterates over all entities with the requested components and folds the components.
cfold' :: forall a o m i. (Monoid o, QCI a, MonadIO m) => (i -> a -> o) -> System m i o
cfold' f = System $ \w -> do
  for <- queryFor @(S a) @a w
  members <- queryMembers @(S a) @a w
  pure $! \i -> do
    ref <- liftIO $ newIORef (mempty :: o)
    for $! \e a -> do
      let o = f i a
      liftIO $ modifyIORef' ref (<> o)
    liftIO $ readIORef ref

-- | Iterates over all entities with the requested components and monadically folds the components.
cfoldM :: forall a o i m. (Monoid o, QCI a, MonadIO m) => (a -> m o) -> System m i o
cfoldM f = System $ \w -> do
  for <- queryFor @(S a) @a w
  pure $! \i2 -> do
    ref <- liftIO $ newIORef (mempty :: o)
    for $! \e a -> do
      o <- f a
      liftIO $ modifyIORef ref (<> o)
    liftIO $ readIORef ref

-- | Iterates over all entities with the requested components and monadically folds the components.
cfoldM' :: forall a o i m. (Monoid o, QCI a, MonadIO m) => (i -> a -> m o) -> System m i o
cfoldM' f = System $ \w -> do
  for <- queryFor @(S a) @a w
  pure $! \i -> do
    ref <- liftIO $ newIORef (mempty :: o)
    for $! \e a -> do
      o <- f i a
      liftIO $ modifyIORef ref (<> o)
    liftIO $ readIORef ref

-- | Iterates over all entities with the requested components and folds the components.
-- The order of getting the components, so there is no real difference between cfoldr and cfoldl.
-- cfoldr is strict and early return is not possible.
cfoldr :: (QCI a, MonadIO m) => (a -> b -> b) -> b -> System m () b
cfoldr f = cfoldl (flip f)
{-# INLINE cfoldr #-}

-- | Iterates over all entities with the requested components and folds the components.
-- The order of getting the components, so there is no real difference between cfoldr and cfoldl.
-- cfoldl is strict and early return is not possible.
cfoldl :: forall a b m. (QCI a, MonadIO m) => (b -> a -> b) -> b -> System m () b
cfoldl f b = System $ \w -> do
  for <- queryFor @(S a) @a w
  pure $! \i2 -> do
    ref <- liftIO $ newIORef b
    for $! \e a -> do
      liftIO $ modifyIORef' ref $ \b -> f b a
    liftIO $ readIORef ref
{-# INLINE cfoldl #-}

-- | Puts the component to the entity
sput :: forall i m. (QCP i, MonadIO m) => System m (Entity, i) ()
sput = System $ \w -> do
  put <- queryPut @(S i) w
  pure $ \(e, i) -> liftIO $ put e i
{-# INLINE sput #-}

-- | Deletes the component from the entity
sdelete :: forall i m. (QCD i, MonadIO m) => System m Entity ()
sdelete = System $ \w -> do
  delete <- queryDelete @(S i) @i w
  pure $ \e -> liftIO $ delete e
{-# INLINE sdelete #-}

-- | Creates a new entity with the given components
newEntity :: forall a m. (QCP a, MonadIO m) => System m a Entity
newEntity = System $ \w -> do
  put <- queryPut @(S a) @a w
  pure $! \c -> do
    e <- liftIO $ World.createEntity w
    liftIO $ put e c
    pure e
{-# INLINE newEntity #-}

-- | Removes an entity and all its components
deleteEntity :: forall a m. (MonadIO m) => System m Entity ()
deleteEntity = System $ \w -> do
  let stores = w ^. #allStores
  let entities = w ^. #entities
  pure $! \e -> liftIO $ do
    AllStores.eachStore stores $ \store -> componentEntityDelete store e
    entitiesDelete entities e
{-# INLINE deleteEntity #-}

-- | A Query is a function which can operate on the components of a world. In contrast to
-- System, a query contains operations which operate on a single entity. System contains operations
-- which can operate on many entities.
newtype Query m i o = Query (World.World -> IO (Entity -> i -> m o))

-- | Execute a query on all matching entities
runQuery :: forall i1 i2 o m. (QCI i1, Monoid o, MonadIO m) => Query m (i1, i2) o -> System m i2 o
runQuery (Query makeQ) = System $ \w -> do
  q <- makeQ w
  for <- queryFor @(S i1) @i1 w
  pure $ \i2 -> do
    ref <- liftIO $ newIORef (mempty :: o)
    for $! \e i1 -> do
      o <- q e (i1, i2)
      liftIO $ modifyIORef' ref (<> o)
    liftIO $ readIORef ref
{-# INLINE runQuery #-}

-- | Execute a query on all matching entities
runQuery_ :: forall i o m. (QCI i, MonadIO m) => Query m i o -> System m () ()
runQuery_ (Query makeQ) = System $ \w -> do
  q <- makeQ w
  for <- queryFor @(S i) @i w
  pure $ \_ -> for (fmap (fmap void) q)
{-# INLINE runQuery_ #-}

-- | Execute a query on the given entity. If the entity does not have the
-- requested components, nothing is done.
singleQuery_ :: forall i o m. (QCG i, MonadIO m) => Query m i o -> System m Entity (Maybe o)
singleQuery_ (Query makeQ) = System $ \w -> do
  q <- makeQ w
  getValues <- queryGet @(S i) @i w
  contains <- queryContains @(S i) @i w
  pure $ \e -> do
    c <- liftIO $ contains e
    if c
      then fmap Just $ liftIO (getValues e) >>= q e
      else pure Nothing
{-# INLINE singleQuery_ #-}

-- | Execute a query on the given entity. If the entity does not have the
-- requested components, nothing is done.
singleQuery ::
  forall i1 i2 o m.
  (QCG i1, MonadIO m) =>
  Query m (i1, i2) o ->
  System m (Entity, i2) (Maybe o)
singleQuery (Query makeQ) = System $ \w -> do
  q <- makeQ w
  getValues <- queryGet @(S i1) @i1 w
  contains <- queryContains @(S i1) @i1 w
  pure $ \(e, i2) -> do
    c <- (liftIO $ contains e)
    if c
      then do
        values <- liftIO $ getValues e
        Just <$> q e (values, i2)
      else pure Nothing
{-# INLINE singleQuery #-}

-- Lifts a normal function into a Query
liftQuery :: Applicative m => (a -> m b) -> Query m a b
liftQuery f = Query $ \_ -> pure $ \_ a -> f a
{-# INLINE liftQuery #-}

instance Monad m => Category (Query m) where
  id = Query $ \_ -> pure $ \_ i -> pure i
  (Query makeS1) . (Query makeS2) = Query $ \w -> do
    s1 <- makeS1 w
    s2 <- makeS2 w
    pure $ \e i -> s2 e i >>= s1 e
  {-# INLINE id #-}
  {-# INLINE (.) #-}

instance Monad m => Arrow (Query m) where
  arr f = Query $ \_ -> pure $ \_ -> pure . f
  (Query makeS1) *** (Query makeS2) = Query $ \w -> do
    s1 <- makeS1 w
    s2 <- makeS2 w
    pure $ \e (i1, i2) -> (,) <$> s1 e i1 <*> s2 e i2
  {-# INLINE arr #-}
  {-# INLINE (***) #-}

-- | Set a component of the matching entity
qput :: forall i m. (QCP i, MonadIO m) => Query m i ()
qput = Query $ \w -> do
  put <- queryPut @(S i) @i w
  pure (fmap liftIO . put)
{-# INLINE qput #-}

-- | Delete the component of the matching entity
qdelete :: forall i m. (QCD i, MonadIO m) => Query m i ()
qdelete = Query $ \w -> do
  delete <- queryDelete @(S i) @i w
  pure $! \e _ -> liftIO $ delete e
{-# INLINE qdelete #-}

type family S a where
  S () = False
  S Entity = False
  S (a, b) = False
  S (a, b, c) = False
  S _ = True

-- | Gets components from the world
class QueryGet (f :: Bool) components where
  queryContains :: World.World -> IO (Entity -> IO Bool)
  queryGet :: World.World -> IO (Entity -> IO components)

-- | Puts components into the world
class QueryPut (f :: Bool) components where
  queryPut :: World.World -> IO (Entity -> components -> IO ())

-- | Removes components from the world
class QueryDelete (f :: Bool) components where
  queryDelete :: World.World -> IO (Entity -> IO ())

-- | Iterate over components from the world
class QueryGet f components => QueryIterate (f :: Bool) components where
  queryFor :: MonadIO m => World.World -> IO ((Entity -> components -> m ()) -> m ())
  queryMembers :: World.World -> IO (IO Int)

-- | Machinery for getting components
type QCG (a :: *) = QueryGet (S a) a

-- | Machinery for putting components
type QCP (a :: *) = QueryPut (S a) a

-- | Machinery for deleting components
type QCD (a :: *) = QueryDelete (S a) a

-- | Machinery for iterating over components
type QCI (a :: *) = QueryIterate (S a) a

instance QueryGet False () where
  queryContains w = pure $! \_ -> pure True
  queryGet w = pure $! \_ -> pure ()
  {-# INLINE queryContains #-}
  {-# INLINE queryGet #-}

instance QueryPut False () where
  queryPut w = pure $! \_ _ -> pure ()
  {-# INLINE queryPut #-}

instance QueryDelete False () where
  queryDelete w = pure $! \_ -> pure ()
  {-# INLINE queryDelete #-}

instance QueryIterate False () where
  queryFor w = do
    pure $! \f -> entitiesFor (w ^. #entities) $! \e -> f e ()
  queryMembers w = do
    pure $! entitiesAmount (w ^. #entities)
  {-# INLINE queryFor #-}
  {-# INLINE queryMembers #-}

instance QueryGet False Entity where
  queryContains w = pure $! \_ -> pure True
  queryGet w = pure $! \e -> pure e
  {-# INLINE queryContains #-}
  {-# INLINE queryGet #-}

instance QueryIterate False Entity where
  queryFor w = do
    pure $! \f -> entitiesFor (w ^. #entities) $! \e -> f e e
  queryMembers w = do
    pure $! entitiesAmount (w ^. #entities)
  {-# INLINE queryFor #-}
  {-# INLINE queryMembers #-}

instance (Component a, ComponentGet a (Store a)) => QueryGet True a where
  queryContains w = World.getStore @a w <&> \s !e -> componentContains s e
  queryGet w = World.getStore @a w <&> \s !e -> componentGet s e
  {-# INLINE queryContains #-}
  {-# INLINE queryGet #-}

instance (Component a, ComponentPut a (Store a)) => QueryPut True a where
  queryPut w = World.getStore w <&> \s !e c -> componentPut s e c
  {-# INLINE queryPut #-}

instance (Component a, ComponentDelete a (Store a)) => QueryDelete True a where
  queryDelete w = World.getStore @a w <&> \s !e -> componentDelete s e
  {-# INLINE queryDelete #-}

instance (Component a, ComponentIterate a (Store a)) => QueryIterate True a where
  queryFor w = World.getStore @a w <&> \s f -> componentIterate s f
  queryMembers w = World.getStore @a w <&> componentMembers
  {-# INLINE queryFor #-}
  {-# INLINE queryMembers #-}

instance (QCG a, QCG b) => QueryGet False (a, b) where
  queryContains w = (\p1 p2 e -> (&&) <$!> p1 e <*> p2 e) <$!> queryContains @(S a) @a w <*> queryContains @(S b) @b w
  queryGet w = (\f1 f2 e -> (,) <$!> f1 e <*> f2 e) <$!> queryGet @(S a) @a w <*> queryGet @(S b) @b w
  {-# INLINE queryContains #-}
  {-# INLINE queryGet #-}

instance (QCP a, QCP b) => QueryPut False (a, b) where
  queryPut w = do
    putA <- queryPut @(S a) w
    putB <- queryPut @(S b) w
    pure $! \e (a, b) -> putA e a *> putB e b
  {-# INLINE queryPut #-}

instance (QCD a, QCD b) => QueryDelete False (a, b) where
  queryDelete w = do
    deleteA <- queryDelete @(S a) @a w
    deleteB <- queryDelete @(S b) @b w
    pure $! \e -> deleteA e *> deleteB e
  {-# INLINE queryDelete #-}

instance (QCI a, QCI b) => QueryIterate False (a, b) where
  queryFor w = do
    membersA <- queryMembers @(S a) @a w
    membersB <- queryMembers @(S b) @b w
    forA <- queryFor @(S a) w
    forB <- queryFor @(S b) w
    containsA <- queryContains @(S a) @a w
    containsB <- queryContains @(S b) @b w
    getA <- queryGet @(S a) @a w
    getB <- queryGet @(S b) @b w
    pure $! \f -> do
      amountA <- liftIO $ membersA
      amountB <- liftIO $ membersB
      if amountA > amountB
        then
          forB $! \e bs -> do
            whenIO (liftIO $ containsA e) $! do
              as <- liftIO $ getA e
              f e (as, bs)
        else
          forA $! \e as -> do
            whenIO (liftIO $ containsA e) $! do
              bs <- liftIO $ getB e
              f e (as, bs)
  queryMembers w = do
    membersA <- queryMembers @(S a) @a w
    membersB <- queryMembers @(S b) @b w
    pure $! min <$!> membersA <*> membersB
  {-# INLINE queryFor #-}
  {-# INLINE queryMembers #-}

instance (QCG a, QCG b, QCG c) => QueryGet False (a, b, c) where
  queryContains w = do
    containsA <- queryContains @(S a) @a w
    containsB <- queryContains @(S b) @b w
    containsC <- queryContains @(S c) @c w
    pure $! \e -> (\a b c -> a && b && c) <$!> containsA e <*> containsB e <*> containsC e
  queryGet w = do
    getA <- queryGet @(S a) w
    getB <- queryGet @(S b) w
    getC <- queryGet @(S c) w
    pure $! \e -> (,,) <$!> getA e <*> getB e <*> getC e
  {-# INLINE queryContains #-}
  {-# INLINE queryGet #-}

instance (QCP a, QCP b, QCP c) => QueryPut False (a, b, c) where
  queryPut w = do
    putA <- queryPut @(S a) w
    putB <- queryPut @(S b) w
    putC <- queryPut @(S c) w
    pure $! \e (a, b, c) -> putA e a *> putB e b *> putC e c
  {-# INLINE queryPut #-}

instance (QCD a, QCD b, QCD c) => QueryDelete False (a, b, c) where
  queryDelete w = do
    deleteA <- queryDelete @(S a) @a w
    deleteB <- queryDelete @(S b) @b w
    deleteC <- queryDelete @(S c) @c w
    pure $! \e -> deleteA e *> deleteB e *> deleteC e
  {-# INLINE queryDelete #-}

instance (QCI a, QCI b, QCI c) => QueryIterate False (a, b, c) where
  queryFor w = do
    membersA <- queryMembers @(S a) @a w
    membersB <- queryMembers @(S b) @b w
    membersC <- queryMembers @(S c) @c w
    forA <- queryFor @(S a) w
    forB <- queryFor @(S b) w
    forC <- queryFor @(S c) w
    containsA <- queryContains @(S a) @a w
    containsB <- queryContains @(S b) @b w
    containsC <- queryContains @(S c) @c w
    getA <- queryGet @(S a) @a w
    getB <- queryGet @(S b) @b w
    getC <- queryGet @(S c) @c w
    pure $! \f -> do
      amountA <- liftIO $ membersA
      amountB <- liftIO $ membersB
      amountC <- liftIO $ membersC
      if amountA > amountB
        then
          if amountB > amountC
            then
              forC $! \e cs -> do
                whenIO (liftIO $ containsA e)
                  $! whenIO (liftIO $ containsB e)
                  $! do
                    as <- liftIO $ getA e
                    bs <- liftIO $ getB e
                    f e (as, bs, cs)
            else
              forB $! \e bs -> do
                whenIO (liftIO $ containsA e)
                  $! whenIO (liftIO $ containsC e)
                  $! do
                    as <- liftIO $ getA e
                    cs <- liftIO $ getC e
                    f e (as, bs, cs)
        else
          if amountA > amountC
            then
              forC $! \e cs -> do
                whenIO (liftIO $ containsA e)
                  $! whenIO (liftIO $ containsB e)
                  $! do
                    as <- liftIO $ getA e
                    bs <- liftIO $ getB e
                    f e (as, bs, cs)
            else
              forA $! \e as -> do
                whenIO (liftIO $ containsB e)
                  $! whenIO (liftIO $ containsC e)
                  $! do
                    cs <- liftIO $ getC e
                    bs <- liftIO $ getB e
                    f e (as, bs, cs)
  queryMembers w = do
    membersA <- queryMembers @(S a) @a w
    membersB <- queryMembers @(S b) @b w
    membersC <- queryMembers @(S c) @c w
    pure $! (\a b c -> min (min a b) c) <$!> membersA <*> membersB <*> membersC

  {-# INLINE queryFor #-}
  {-# INLINE queryMembers #-}

whenIO :: Monad m => m Bool -> m () -> m ()
whenIO action f = do
  b <- action
  when b f
{-# INLINE whenIO #-}

(#.) :: Coercible b c => (b -> c) -> (a -> b) -> (a -> c)
(#.) _f = coerce
{-# INLINE (#.) #-}
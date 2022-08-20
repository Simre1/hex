{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE RoleAnnotations #-}
{-# LANGUAGE UndecidableInstances #-}

module Hero.System.System where

import Control.Arrow (Arrow (arr, (***)))
import Control.Category (Category (..))
import Control.Monad.IO.Class (MonadIO (..))
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Kind (Type)
import Prelude hiding (id, (.))
import Hero.World ( World )

-- | A system is a function which can operate on the components of a world.
-- Keep in mind that system has Functor, Applicative, Category and Arrow instances, but no Monad instance.
newtype System (m :: Type -> Type) (i :: Type) (o :: Type) = System (World -> IO (i -> m o))

instance Monad m => Category (System m) where
  id = System (\_ -> pure (pure . id))
  (System f1) . (System f2) = System $ \w -> do
    f2' <- f2 w
    f1' <- f1 w
    pure $ \i -> f2' i >>= f1'
  {-# INLINE id #-}
  {-# INLINE (.) #-}

instance Monad m => Arrow (System m) where
  arr f = System (\_ -> pure (pure . f))
  (System f1) *** (System f2) = System $ \w -> do
    f1' <- f1 w
    f2' <- f2 w
    pure $ \(i1, i2) -> (,) <$> f1' i1 <*> f2' i2
  {-# INLINE arr #-}
  {-# INLINE (***) #-}

instance Applicative m => Functor (System m i) where
  fmap f (System makeS) = System $ \w -> do
    s <- makeS w
    pure $ \i -> fmap f (s i)
  {-# INLINE fmap #-}

instance Applicative m => Applicative (System m i) where
  pure a = System $ \_ -> pure $ \_ -> pure a

  -- (<*>) might be automatically parallelized in the future. Use (>>>) for sequential code.
  (System makeSF) <*> (System makeSV) = System $ \w -> do
    f <- makeSF w
    v <- makeSV w
    pure $ \i -> f i <*> v i
  {-# INLINE pure #-}
  {-# INLINE (<*>) #-}

-- | Allows code to be executed during the compilation stage.
-- `IO a` is only executed once and the `a` is the permanent output of the system.
withSetup' :: Applicative m => (World -> IO a) -> System m i a
withSetup' f = System $ \w -> f w >>= \a -> pure $ \_ -> pure a

-- | Allows code to be executed during the compilation stage.
-- `IO a` is only executed once and the `a` is the permanent output of the system.
withSetup :: Applicative m => (World -> IO a) -> (a -> System m i o) -> System m i o
withSetup f make = System $ \w -> do
  a <- f w
  let System makeS = make a
  s <- makeS w
  pure s

-- | Lifs a normal function into a System.
liftSystem :: Applicative m => (a -> m b) -> System m a b
liftSystem f = System $ \_ -> pure $ f
{-# INLINE liftSystem #-}

-- | Compiles a system with the given World and returns a function which executes
-- the operations within the System.
compileSystem :: System m i o -> World -> IO (i -> m o)
compileSystem (System f) w = f w
{-# INLINE compileSystem #-}

-- | Forwards the input of a system to its output. The previous output is ignored.
-- Look at (&&&) if you do not want to ignore the output.
forward :: Functor m => System m i o -> System m i i
forward (System makeS) = System $ \w -> do
  s <- makeS w
  pure $ \i -> i <$ s i
{-# INLINE forward #-}

-- | Executes a system only once and caches the output, then returns that output
-- continously.
once :: MonadIO m => System m i o -> System m i o
once (System makeS) = System $ \w -> do
  s <- makeS w
  ref <- newIORef (\_ -> pure undefined)
  writeIORef ref $ \i -> s i >>= \o -> liftIO (writeIORef ref (\_ -> pure o)) >> pure o
  pure $ \i -> liftIO (readIORef ref) >>= \f -> f i
{-# INLINE once #-}

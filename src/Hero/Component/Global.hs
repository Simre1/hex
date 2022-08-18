module Hero.Component.Global where

import Control.Monad.IO.Class (MonadIO (liftIO))
import Data.Default (Default (def))
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Hero.Component
  ( ComponentGet (..),
    ComponentIterate (..),
    ComponentMakeStore (..),
    ComponentPut (..),
    ComponentStore(..)
  )

-- | Component store using an IORef for a single component instance.
-- Every entity has the same component. Can be used as a 'Store'.
-- The default 'makeStore' needs a 'Default' instance on 'a'. 
-- You can create a custom 'Global' instance which does not need 'Default'.
newtype Global a = Global (IORef a)

-- | Creates a global component store. 
makeGlobal :: a -> IO (Global a)
makeGlobal a = Global <$> newIORef a

instance ComponentStore a Global where
  componentEntityDelete _ _ = pure ()
  
instance ComponentGet a Global where
  componentContains (Global ref) entity = pure True
  componentGet (Global ref) entity = readIORef ref
  {-# INLINE componentContains #-}
  {-# INLINE componentGet #-}

instance ComponentPut a Global where
  componentPut (Global ref) entity val = writeIORef ref val
  {-# INLINE componentPut #-}

instance Default a => ComponentMakeStore a Global where
  componentMakeStore _ = makeGlobal def
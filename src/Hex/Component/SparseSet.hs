module Hex.Component.SparseSet where

import Data.Coerce ( coerce )
import Data.SparseSet.Storable qualified as SV
import Data.SparseSet.Unboxed qualified as SU
import Data.Vector.Storable (Storable)
import Data.Vector.Unboxed (Unbox)
import Hex.Component ( ComponentStore(..) )
import Hex.Entity
    ( MaxEntities(MaxEntities), Entity(Entity) )

newtype SparseSetUnboxedStore a = SparseSetUnboxedStore (SU.SparseSetUnboxed a)

instance Unbox a => ComponentStore a SparseSetUnboxedStore where
  storeContains (SparseSetUnboxedStore set) entity = SU.contains set (coerce entity)
  storeGet (SparseSetUnboxedStore set) entity = SU.unsafeLookup set (coerce entity)
  storePut (SparseSetUnboxedStore set) entity val = SU.insert set (coerce entity) val
  storeDelete (SparseSetUnboxedStore set) entity = SU.remove set (coerce entity)
  storeFor (SparseSetUnboxedStore set) f = SU.for set (coerce f)
  storeMembers (SparseSetUnboxedStore set) = SU.size set
  makeStore (MaxEntities entities) = SparseSetUnboxedStore <$> SU.create entities (entities `quot` 3)
  {-# INLINE storeContains #-}
  {-# INLINE storeGet #-}
  {-# INLINE storePut #-}
  {-# INLINE storeDelete #-}
  {-# INLINE storeFor #-}
  {-# INLINE storeMembers #-}

newtype SparseSetStorableStore a = SparseSetStorableStore (SV.SparseSetStorable a)

instance Storable a => ComponentStore a SparseSetStorableStore where
  storeContains (SparseSetStorableStore set) entity = SV.contains set (coerce entity)
  storeGet (SparseSetStorableStore set) entity = SV.unsafeLookup set (coerce entity)
  storePut (SparseSetStorableStore set) entity val = SV.insert set (coerce entity) val
  storeDelete (SparseSetStorableStore set) entity = SV.remove set (coerce entity)
  storeFor (SparseSetStorableStore set) f = SV.for set (coerce f)
  storeMembers (SparseSetStorableStore set) = SV.size set
  makeStore (MaxEntities entities) = SparseSetStorableStore <$> SV.create entities (entities `quot` 3)
  {-# INLINE storeContains #-}
  {-# INLINE storeGet #-}
  {-# INLINE storePut #-}
  {-# INLINE storeDelete #-}
  {-# INLINE storeFor #-}
  {-# INLINE storeMembers #-}
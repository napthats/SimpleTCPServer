module Utils.Id
       (
         Id(),
         newId,
         nextId,
       ) where


newtype Id = Id Integer
           deriving (Eq, Show)
                            
newId :: Id
newId = Id 0

nextId :: Id -> Id
nextId (Id x) = Id $ x + 1

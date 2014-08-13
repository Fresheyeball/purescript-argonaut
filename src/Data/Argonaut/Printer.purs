module Data.Argonaut.Printer
  ( Printer
  , printJson
  ) where

  import Data.Argonaut.Core
    ( foldJson
    , Json(..)
    , JNull()
    , JBoolean()
    , JNumber()
    , JString()
    , JField()
    , JArray()
    , JObject()
    )
  import Data.Foldable (foldr)
  import Data.Tuple (Tuple(..))

  import qualified Data.Map as M

  class Printer a where
    printJson :: Json -> a

  instance printerJNull :: Printer String where
    printJson = stringify

  stringify :: Json -> String
  stringify json = foldJson stringifyNull
                            stringifyBoolean
                            stringifyNumber
                            stringifyString
                            stringifyArray
                            stringifyObject
                            json

  stringifyNull :: JNull -> String
  stringifyNull _ = "null"

  stringifyBoolean :: JBoolean -> String
  stringifyBoolean true  = "true"
  stringifyBoolean false = "false"

  stringifyNumber :: JNumber -> String
  stringifyNumber = show

  stringifyString :: JString -> String
  stringifyString = show

  stringifyField :: JField -> String
  stringifyField = show

  stringifyArray :: JArray -> String
  stringifyArray []     = "[]"
  stringifyArray (x:xs) = "[" ++ stringify x ++ foldr withComma "]" xs
    where
      withComma x acc = ", " ++ stringify x ++ acc

  stringifyObject :: JObject -> String
  stringifyObject objMap = case M.toList objMap of
    (x:xs) -> "{" ++ one x ++ foldr withComma "}" xs
    _      -> "{}"
    where
      one (Tuple k v) = show k ++ ": " ++ stringify v
      withComma x acc = ", " ++ one x ++ acc

  -- Orphan instance
  instance showJson :: Show Json where
    show = printJson

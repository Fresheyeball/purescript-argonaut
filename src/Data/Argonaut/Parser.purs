module Data.Argonaut.Parser (jsonParser) where

  import Control.Apply ((<*), (*>))
  import Control.Lens (iso, IsoP())
  import Control.Monad.Identity (Identity(..))

  import Data.Argonaut.Core
    ( fromArray
    , fromNumber
    , fromObject
    , fromString
    , jsonEmptyArray
    , jsonEmptyObject
    , jsonFalse
    , jsonNull
    , jsonTrue
    , Json(..)
    , JArray()
    , JAssoc()
    , JField()
    , JObject()
    )
  import Data.Argonaut.Printer
  import Data.Either (Either(..))
  import Data.Foldable (notElem)
  import Data.Maybe (Maybe(..))
  import Data.String (charCodeAt, joinWith)
  import Data.Tuple (Tuple(..))

  import Global (readFloat)

  import Text.Parsing.Parser
    ( fail
    , runParser
    , unParserT
    , Parser()
    , ParseError(..)
    , ParserT(..)
    )
  import Text.Parsing.Parser.Combinators
    ( (<?>)
    , between
    , choice
    , many
    , option
    , sepBy
    , sepBy1
    , try
    )
  import Text.Parsing.Parser.String (char, satisfy, string, whiteSpace)

  import qualified Data.Map as M

  -- Constants
  backspace      = "b"
  carriageReturn = "r"
  closeBrace     = "}"
  closeBracket   = "]"
  comma          = ","
  doubleQuote    = "\""
  formfeed       = "f"
  horizontalTab  = "t"
  newline        = "n"
  openBrace      = "{"
  openBracket    = "["
  reverseSolidus = "\\"
  solidus        = "/"

  jsonParser :: Parser String Json
  jsonParser = do
    skipSpaces
    c <- lookAhead char
    case c of
      "{" -> objectParser unit
      "[" -> arrayParser unit
      _   -> invalidJson "object or array"

  objectParser :: Unit -> Parser String Json
  objectParser _ = try emptyObjectParser
               <|> nonEmptyObjectParser unit

  arrayParser :: Unit -> Parser String Json
  arrayParser _ = try emptyArrayParser
              <|> nonEmptyArrayParser

  emptyObjectParser :: Parser String Json
  emptyObjectParser = skipSpaces *> braces (skipSpaces *> pure jsonEmptyObject)

  nonEmptyObjectParser :: Unit -> Parser String Json
  nonEmptyObjectParser _ =
    skipSpaces *> braces (skipSpaces *> membersParser unit <* skipSpaces)

  membersParser :: Unit -> Parser String Json
  membersParser _ =
    (M.fromList >>> fromObject) <$> sepBy1 (memberParser unit) (string comma)

  memberParser :: Unit -> Parser String JAssoc
  memberParser _ = do
    skipSpaces
    key <- rawStringParser
    skipSpaces
    string ":"
    skipSpaces
    val <- valueParser unit
    pure $ Tuple key val

  emptyArrayParser :: Parser String Json
  emptyArrayParser = skipSpaces *> brackets (skipSpaces *> pure jsonEmptyArray)

  nonEmptyArrayParser :: Parser String Json
  nonEmptyArrayParser = do
    skipSpaces
    fromArray <$> brackets (skipSpaces *> sepBy (valueParser unit) (string comma) <* skipSpaces)

  nullParser :: Parser String Json
  nullParser = skipSpaces *> string "null" *> pure jsonNull

  booleanParser :: Parser String Json
  booleanParser = do
    skipSpaces
    b <- lookAhead char
    case b of
      "t" -> string "true"  *> pure jsonTrue
      "f" -> string "false" *> pure jsonFalse
      _   -> invalidJson "one of 'true' or 'false'"

  numberParser :: Parser String Json
  numberParser = do
    skipSpaces
    neg <- option "" $ string "-"
    d <- lookAhead char
    d' <- case d of
      "0"             -> char
      _ | oneToNine d -> digits
      _               -> invalidJson "digit"
    frac <- option "" $ fracParser
    exp <- option "" $ expParser
    pure $ fromNumber $ readFloat $ neg ++ d' ++ frac ++ exp

  digits :: Parser String String
  digits =
    joinWith "" <$> manyTill digit (lookAhead $ satisfy $ not <<< isDigit)

  digit :: Parser String String
  digit = satisfy isDigit

  fracParser :: Parser String String
  fracParser = do
    string "."
    digits' <- digits
    pure ("." ++ digits')

  expParser :: Parser String String
  expParser = do
    e <- try (string "e") <|> string "E"
    sign <- option "" (try (string "+") <|> try (string "-"))
    digits' <- digits
    pure (e ++ sign ++ digits')

  stringParser :: Parser String Json
  stringParser = fromString <$> rawStringParser

  rawStringParser :: Parser String String
  rawStringParser = try emptyStringParser
                <|> nonEmptyStringParser

  emptyStringParser :: Parser String String
  emptyStringParser = skipSpaces *> quoted (pure "")

  nonEmptyStringParser :: Parser String String
  nonEmptyStringParser = do
    skipSpaces
    joinWith "" <$> quoted (manyTill (try normalChar <|> controlChar) (lookAhead $ string doubleQuote))

  normalChar :: Parser String String
  normalChar = do
    c <- lookAhead char
    case c of
      "\"" -> invalidJson "unicode character"
      "\\" -> invalidJson "unicode character"
      _    -> char

  controlChar :: Parser String String
  controlChar = do
    c <- lookAhead char
    case c of
      "\\" -> char *> do
        c' <- lookAhead char
        case c' of
          backspace      -> char
          carriageReturn -> char
          doubleQuote    -> char
          formfeed       -> char
          horizontalTab  -> char
          newline        -> char
          reverseSolidus -> char
          solidus        -> char
          "u"            -> unicodeParser
      _ -> invalidJson "control character"

  unicodeParser :: Parser String String
  unicodeParser = do
    u <- string "u"
    one <- hexDigit
    two <- hexDigit
    three <- hexDigit
    four <- hexDigit
    pure $ u ++ one ++ two ++ three ++ four

  hexDigit :: Parser String String
  hexDigit = satisfy isHex

  isHex :: String -> Boolean
  isHex = (||) <$> isDigit <*> isHexAlpha

  isHexAlpha :: String -> Boolean
  isHexAlpha str = let n = ord str in
    (65 <= n && n <= 70) || (97 <= n && n <= 102)

  valueParser :: Unit -> Parser String Json
  valueParser _ = choice (try <$>
    [ nullParser
    , booleanParser
    , stringParser
    , (objectParser unit)
    , (arrayParser unit)
    , numberParser
    ])

  invalidJson :: forall a. String -> Parser String a
  invalidJson expected = many char >>= \s -> fail $ "Invalid JSON:\n\t" ++
    "Expected " ++ expected ++ ".\n\t" ++
    "Found: " ++ joinWith "" s

  -- String things.

  ord :: String -> Number
  ord = charCodeAt 0

  isDigit :: String -> Boolean
  isDigit str | 48 <= ord str && ord str <= 57 = true
  isDigit _                                    = false

  oneToNine :: String -> Boolean
  oneToNine str = isDigit str && str /= "0"

  -- Parser things. Should move them to purescript-parsing

  type ParserState s a =
    { input    :: s
    , result   :: Either ParseError a
    , consumed :: Boolean
    }

  skipSpaces :: Parser String {}
  skipSpaces = whiteSpace *> pure {}

  skipMany :: forall s a m. (Monad m) => ParserT s m a -> ParserT s m {}
  skipMany p = skipMany1 p <|> pure {}

  skipMany1 :: forall s a m. (Monad m) => ParserT s m a -> ParserT s m {}
  skipMany1 p = do
    x <- p
    xs <- skipMany p
    pure {}

  lookAhead :: forall s a m. (Monad m) => ParserT s m a -> ParserT s m a
  lookAhead (ParserT p) = ParserT \s -> do
    state <- p s
    pure state{input = s, consumed = false}

  instance showParseError :: Show ParseError where
    show (ParseError msg) = msg.message

  noneOf :: forall s m a. (Monad m) => [String] -> ParserT String m String
  noneOf ss = satisfy (flip notElem ss)

  manyTill :: forall s a m e. (Monad m) => ParserT s m a -> ParserT s m e -> ParserT s m [a]
  manyTill p end = scan
    where
      scan = (do
                end
                pure [])
         <|> (do
                x <- p
                xs <- scan
                pure (x:xs))

  many1Till :: forall s a m e. (Monad m) => ParserT s m a -> ParserT s m e -> ParserT s m [a]
  many1Till p end = do
    x <- p
    xs <- manyTill p end
    pure (x:xs)

  braces :: forall s m a. (Monad m) => ParserT String m a -> ParserT String m a
  braces = between (string openBrace) (string closeBrace)

  brackets :: forall m a. (Monad m) => ParserT String m a -> ParserT String m a
  brackets = between (string openBracket) (string closeBracket)

  quoted :: forall m a. (Monad m) => ParserT String m a -> ParserT String m a
  quoted = between (string doubleQuote) (string doubleQuote)

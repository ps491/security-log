{-# LANGUAGE OverloadedStrings #-}

module Database
( search
, update
) where

import           Config                 (Config (..))
import           Data.Log
import           Data.Maybe             (fromJust, isJust)
import           Database.V5.Bloodhound
import           GHC.Generics           ()
import           Network.HTTP.Client    (defaultManagerSettings)
import           Prelude                hiding (log)

---- Settings
logIndex :: IndexName
logIndex = IndexName "_all"

mapping :: MappingName
mapping = MappingName "apache-access"

search :: Config -> IO [Log]
search cfg = withBH defaultManagerSettings (Server $ ip cfg) $ do
  let query = Filter $ QueryBoolQuery BoolQuery { boolQueryMustNotMatch = [TermQuery (Term "analyzed" "true") Nothing]
  , boolQueryMustMatch = []
  , boolQueryFilter = []
  , boolQueryShouldMatch = []
  , boolQueryMinimumShouldMatch = Nothing
  , boolQueryBoost = Nothing
  , boolQueryDisableCoord = Nothing
  }
  let searchQuery = (mkSearch Nothing (Just query)) { Database.V5.Bloodhound.size = Size (fromJust $ Config.size cfg) }
  searchResult <- searchByType logIndex mapping searchQuery
  -- searchResult <- searchAll searchQuery
  parse <- parseEsResponse searchResult
  return $ parseLog parse
    where
      parseLog :: Either EsError (SearchResult Log) -> [Log]
      parseLog (Left ex) = error $ show (errorMessage ex)
      parseLog (Right a) = Prelude.map fromJust $ Prelude.filter isJust $ Prelude.map parseHit $ hits $ searchHits a
        where
          parseHit :: Hit Log -> Maybe Log
          parseHit x = fmap (\y -> y {Data.Log.meta = Just $ getMeta x } ) (hitSource x)

          getMeta :: Hit a -> LogMeta
          getMeta h = LogMeta { Data.Log._id = hitDocId h, Data.Log._index = hitIndex h}


update :: Config -> Log -> IO ()
update cfg log = withBH defaultManagerSettings (Server $ ip cfg) $ do
  let documentSetting = IndexDocumentSettings { idsVersionControl = NoVersionControl
                                              , idsParent = Just $ DocumentParent (extractMeta Data.Log._id)
                                              }
  _ <- updateDocument (extractMeta Data.Log._index) mapping documentSetting log (extractMeta Data.Log._id)
  return ()
    where
      extractMeta a = a . fromJust . meta $ log

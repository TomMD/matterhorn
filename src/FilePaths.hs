{-# LANGUAGE TupleSections #-}
module FilePaths
  ( historyFilePath
  , historyFileName

  , configFileName

  , xdgName
  , locateConfig

  , Script(..)
  , locateScriptPath
  , getAllScripts
  ) where

import Control.Applicative
import Control.Monad (forM, filterM)
import Data.Monoid ((<>))
import Data.Maybe (listToMaybe)
import System.Directory ( doesFileExist
                        , doesDirectoryExist
                        , getDirectoryContents
                        , getPermissions
                        , executable
                        )
import System.Environment.XDG.BaseDir (getUserConfigFile, getAllConfigFiles)
import System.FilePath (takeBaseName)

import Prelude

xdgName :: String
xdgName = "matterhorn"

historyFileName :: FilePath
historyFileName = "history.txt"

configFileName :: FilePath
configFileName = "config.ini"

historyFilePath :: IO FilePath
historyFilePath = getUserConfigFile xdgName historyFileName

-- | Find a specified configuration file by looking in all of the
-- supported locations.
locateConfig :: FilePath -> IO (Maybe FilePath)
locateConfig filename = do
  xdgLocations <- getAllConfigFiles "matterhorn" filename
  let confLocations = ["./" <> filename] ++
                      xdgLocations ++
                      ["/etc/matterhorn/" <> filename]
  results <- forM confLocations $ \fp -> (fp,) <$> doesFileExist fp
  return $ listToMaybe $ fst <$> filter snd results

scriptDirName :: FilePath
scriptDirName = "scripts"

data Script
  = ScriptPath FilePath
  | NonexecScriptPath FilePath
  | ScriptNotFound
    deriving (Eq, Read, Show)

toScript :: FilePath -> IO (Script)
toScript fp = do
  perm <- getPermissions fp
  return $ if executable perm
    then ScriptPath fp
    else NonexecScriptPath fp

isExecutable :: FilePath -> IO Bool
isExecutable fp = do
  perm <- getPermissions fp
  return (executable perm)

locateScriptPath :: FilePath -> IO Script
locateScriptPath name
  | head name == '.' = return ScriptNotFound
  | otherwise = do
    xdgLocations <- getAllConfigFiles "matterhorn" scriptDirName
    let cmdLocations = [ xdgLoc ++ "/" ++ name
                       | xdgLoc <- xdgLocations
                       ] ++ [ "/etc/matterhorn/scripts/" <> name ]
    existingFiles <- filterM doesFileExist cmdLocations
    executables <- mapM toScript existingFiles
    return $ case executables of
      (path:_) -> path
      _        -> ScriptNotFound

-- | This returns a list of valid scripts, and a list of non-executable
--   scripts.
getAllScripts :: IO ([FilePath], [FilePath])
getAllScripts = do
  xdgLocations <- getAllConfigFiles "matterhorn" scriptDirName
  let cmdLocations = xdgLocations ++ ["/etc/matterhorn/scripts"]
  let getCommands dir = do
        exists <- doesDirectoryExist dir
        if exists
          then map ((dir ++ "/") ++) `fmap` getDirectoryContents dir
          else return []
  let isNotHidden f = case f of
        ('.':_) -> False
        []      -> False
        _       -> True
  allScripts <- concat `fmap` mapM getCommands cmdLocations
  execs <- filterM isExecutable allScripts
  nonexecs <- filterM (fmap not . isExecutable) allScripts
  return ( filter isNotHidden $ map takeBaseName execs
         , filter isNotHidden $ map takeBaseName nonexecs
         )

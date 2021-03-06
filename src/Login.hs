{-# LANGUAGE MultiWayIf #-}
module Login
  ( interactiveGatherCredentials
  ) where

import Brick
import Brick.Widgets.Edit
import Brick.Widgets.Center
import Brick.Widgets.Border
import Control.Monad.IO.Class (liftIO)
import Data.Maybe (isNothing)
import Text.Read (readMaybe)
import qualified Data.Text as T
import Graphics.Vty hiding (Config)
import System.Exit (exitSuccess)

import Network.Mattermost.Exceptions (LoginFailureException(..))

import Config
import Markdown
import Types (ConnectionInfo(..), AuthenticationException(..))

data Name = Hostname | Port | Username | Password deriving (Ord, Eq, Show)

data State =
    State { hostnameEdit :: Editor T.Text Name
          , portEdit     :: Editor T.Text Name
          , usernameEdit :: Editor T.Text Name
          , passwordEdit :: Editor T.Text Name
          , focus    :: Name
          , previousError :: Maybe AuthenticationException
          }

toPassword :: [T.Text] -> Widget a
toPassword s = txt $ T.replicate (T.length $ T.concat s) "*"

interactiveGatherCredentials :: Config
                             -> Maybe AuthenticationException
                             -> IO ConnectionInfo
interactiveGatherCredentials config authError = do
    let state = State { hostnameEdit = editor Hostname (txt . T.concat) (Just 1) hStr
                      , portEdit = editor Port (txt . T.concat) (Just 1) (T.pack $ show $ configPort config)
                      , usernameEdit = editor Username (txt . T.concat) (Just 1) uStr
                      , passwordEdit = editor Password toPassword     (Just 1) pStr
                      , focus = initialFocus
                      , previousError = authError
                      }
        hStr = maybe "" id $ configHost config
        uStr = maybe "" id $ configUser config
        pStr = case configPass config of
            Just (PasswordString s) -> s
            _                       -> ""
        initialFocus = if | T.null hStr -> Hostname
                          | T.null uStr -> Username
                          | T.null pStr -> Password
                          | otherwise   -> Hostname
    finalSt <- defaultMain app state
    let finalH = T.concat $ getEditContents $ hostnameEdit finalSt
        finalPort = read $ T.unpack $ T.concat $ getEditContents $ portEdit finalSt
        finalU = T.concat $ getEditContents $ usernameEdit finalSt
        finalPass = T.concat $ getEditContents $ passwordEdit finalSt
    return $ ConnectionInfo finalH finalPort finalU finalPass

app :: App State e Name
app = App
  { appDraw         = credsDraw
  , appChooseCursor = showFirstCursor
  , appHandleEvent  = onEvent
  , appStartEvent   = return
  , appAttrMap      = const colorTheme
  }

errorAttr :: AttrName
errorAttr = "errorMessage"

colorTheme :: AttrMap
colorTheme = attrMap defAttr
  [ (editAttr, black `on` white)
  , (editFocusedAttr, black `on` yellow)
  , (errorAttr, fg red)
  ]

credsDraw :: State -> [Widget Name]
credsDraw st =
    [ center (credentialsForm st <=> errorMessageDisplay st)
    ]

errorMessageDisplay :: State -> Widget Name
errorMessageDisplay st = do
    case previousError st of
        Nothing -> emptyWidget
        -- XXX
        Just e -> txt " " <=>
                  (withDefAttr errorAttr $
                   hCenter (str "Error: " <+> renderAuthError e))

renderAuthError :: AuthenticationException -> Widget Name
renderAuthError (ConnectError _) = txt "Could not connect to server"
renderAuthError (ResolveError _) = txt "Could not resolve server hostname"
renderAuthError (OtherAuthError e) = str $ show e
renderAuthError (LoginError (LoginFailureException msg)) = str msg

credentialsForm :: State -> Widget Name
credentialsForm st =
    hCenter $ hLimit 50 $ vLimit 15 $
    border $
    vBox [ renderText "Please enter your MatterMost credentials to log in."
         , txt " "
         , txt "Hostname:" <+> renderEditor (focus st == Hostname) (hostnameEdit st)
         , txt " "
         , txt "Port:    " <+> renderEditor (focus st == Port) (portEdit st)
         , txt " "
         , txt "Username:" <+> renderEditor (focus st == Username) (usernameEdit st)
         , txt " "
         , txt "Password:" <+> renderEditor (focus st == Password) (passwordEdit st)
         , txt " "
         , renderText "Press Enter to log in or Esc to exit."
         ]

onEvent :: State -> BrickEvent Name e -> EventM Name (Next State)
onEvent _  (VtyEvent (EvKey KEsc [])) = liftIO exitSuccess
onEvent st (VtyEvent (EvKey (KChar '\t') [])) =
    continue $ st { focus = if | focus st == Hostname -> Port
                               | focus st == Port     -> Username
                               | focus st == Username -> Password
                               | focus st == Password -> Hostname
                  }
onEvent st (VtyEvent (EvKey KEnter [])) =
    -- check for valid (non-empty) contents
    let h = T.concat $ getEditContents $ hostnameEdit st
        u = T.concat $ getEditContents $ usernameEdit st
        p = T.concat $ getEditContents $ passwordEdit st
        port :: Maybe Int
        port = readMaybe (T.unpack $ T.concat $ getEditContents $ portEdit st)
    in case T.null h || T.null u || T.null p || isNothing port of
        True -> continue st
        False -> halt st
onEvent st (VtyEvent e) =
    case focus st of
        Hostname -> do
            e' <- handleEditorEvent e (hostnameEdit st)
            continue $ st { hostnameEdit = e' }
        Port -> do
            e' <- handleEditorEvent e (portEdit st)
            continue $ st { portEdit = e' }
        Username -> do
            e' <- handleEditorEvent e (usernameEdit st)
            continue $ st { usernameEdit = e' }
        Password -> do
            e' <- handleEditorEvent e (passwordEdit st)
            continue $ st { passwordEdit = e' }
onEvent st _ = continue st

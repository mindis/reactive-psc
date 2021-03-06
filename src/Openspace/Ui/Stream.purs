module Openspace.Ui.Stream where

import Rx.Observable
import Data.Either
import Control.Monad.Eff
import Control.Monad.ST
import DOM

import Openspace.Ui.Render
import Openspace.Ui.Emitter
import Openspace.Ui.Parser
import Openspace.Types
import Openspace.Engine
import Openspace.Network.Socket

netStream :: forall eff. Socket -> Eff( net :: Net | eff ) (Observable Action)
netStream socket = do
  onReceive <- "message" `socketObserver'` socket
  return $ actionFromForeign parseAction id <$> onReceive

dragStream :: forall eff. Eff( dom :: DOM| eff) (Observable Action)
dragStream = do
  emitters <- getEmitters
  let lookup = emitterLookup emitters
      dragOverSlot = (\e -> case parseSlot (getDetail e) of
                         Right s -> AssignTopic s
                         Left e -> UnassignTopic
                     ) <$> lookup "dragOverSlot"

      dragOverTrash = const DeleteTopic <$> lookup "dragOverTrash"

      -- HTML 5 fires dragLeave before dragEnd occurs
      -- TODO: Find a cleaner solution
      dragLeave = delay 30 $ const UnassignTopic
                  <$> lookup "dragLeaveSlot" `merge` lookup "dragLeaveTrash"

      dragOver = dragLeave `merge` dragOverSlot `merge` dragOverTrash

      dragStart = parseTopic <<< getDetail
                  <$> lookup "dragStartTopic" `merge` lookup "dragStartGridTopic"

      dragTopic = do Right t <- dragStart
                     action <- dragOver
                     lookup "dragEndTopic" `merge` lookup "dragEndGridTopic"
                     return $ action t
  return dragTopic

uiStream :: forall eff. Eff( dom :: DOM | eff ) (Observable Action)
uiStream = do
  emitters <- getEmitters
  let lookup = emitterLookup emitters
      addTopic    = (actionFromForeign parseTopic AddTopic) <<< getDetail
                    <$> lookup "addTopic"
      addRoom     = (actionFromForeign parseRoom AddRoom) <<< getDetail
                    <$> lookup "addRoom"
      removeRoom  = (actionFromForeign parseRoom DeleteRoom) <<< getDetail
                    <$> lookup "deleteRoom"
      addBlock    = (actionFromForeign parseBlock AddBlock) <<< getDetail
                    <$> lookup "addBlock"
      deleteBlock = (actionFromForeign parseBlock DeleteBlock) <<< getDetail
                    <$> lookup "deleteBlock"
      changeGrid = addRoom `merge` removeRoom `merge` addBlock `merge` deleteBlock
  dragTopic <- dragStream
  return $ addTopic `merge` dragTopic `merge` changeGrid

main = do
  -- TODO: getSocket :: Either SockErr Socket
  -- let sockEmitter = getSocket "http://localhost:3000"
  -- until Websocket support is given by the server
  let sockEmitter = EmptySocket
  -- Initial State
  appSt <- newSTRef myState1
  -- Initial Render
  renderMenu (show <$> topicTypes)
  readSTRef appSt >>= renderApp
  -- Observable Action
  ui  <- uiStream
  net <- netStream sockEmitter
  -- Broadcast the UI Observable
  subscribe ui (\a -> emitAction sockEmitter (serialize a))
  -- Evaluate Action Observables
  let actions = ui `merge` net
  subscribe actions (\a -> modifySTRef appSt (evalAction a) >>= renderApp)

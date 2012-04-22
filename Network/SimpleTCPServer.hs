module Network.SimpleTCPServer
    (
     SimpleTCPServer(),
     ClientID(),
     runTCPServer,
     getClientMessage,
     getClientMessageFrom,
     getEachClientMessages,
     broadcastMessage,
     sendMessageTo,
     shutdownServer,
    ) where

--import Network.Socket
import Network
import System.IO
import Control.Concurrent
import Control.Concurrent.STM.TChan
import Control.Exception
import Control.Monad.Fix (fix)
import Data.IORef
import Data.List
import Control.Monad
import Control.Monad.STM
import qualified Utils.Id as UI

    
newtype SimpleTCPServer = SimpleTCPServer (IORef [Client], Socket, ThreadId)
newtype ClientID = ClientID UI.Id
                 deriving (Eq, Show)
data ClientStatus = Live | Dead
type Client = (ClientID, TChan String, TChan String, IORef ClientStatus)

newClientID :: ClientID
newClientID = ClientID UI.newId

nextClientID :: ClientID -> ClientID
nextClientID (ClientID x) = ClientID $ UI.nextId x

getClientID :: Client -> ClientID
getClientID (cid, _, _, _) = cid 

getWchan :: Client -> TChan String
getWchan (_, wchan, _, _) = wchan

isLive :: Client -> IO Bool
isLive (_, _, _, stref) = do
  st <- atomicModifyIORef stref (\x -> (x, x))
  case st of 
    Dead -> return False
    Live -> return True

shutdownServer :: SimpleTCPServer -> IO ()
shutdownServer (SimpleTCPServer (_, sock, threadid)) = do
  killThread threadid
  sClose sock

runTCPServer :: PortNumber -> IO SimpleTCPServer
runTCPServer port = do
  clientListRef <- newIORef []
  sock <- listenOn $ PortNumber port
  threadid <- forkIO $ acceptLoop sock clientListRef newClientID
  _ <- forkIO $ clientStatusCheckLoop clientListRef
  return $ SimpleTCPServer (clientListRef, sock, threadid)

clientStatusCheckLoop :: IORef [Client] -> IO ()
clientStatusCheckLoop clientListRef = do
  clientList <- atomicModifyIORef clientListRef (\x -> (x, x))
  toDeleteClientList <- filterWithIOBool (liftM not . isLive) clientList
  atomicModifyIORef clientListRef
    (\list -> (filter
               (\client -> notElem (getClientID client) (map getClientID toDeleteClientList))
               list, ()))
  threadDelay $ 1000 * 1000
  clientStatusCheckLoop clientListRef
 
acceptLoop :: Socket -> IORef [Client] -> ClientID -> IO ()
acceptLoop sock clientListRef cid = do
  (hdl, _, _) <- accept sock
  wchan <- atomically newTChan
  rchan <- atomically newTChan
  stref <- newIORef Live
  atomicModifyIORef clientListRef (\x -> ((cid, wchan, rchan, stref):x, ()))
  _ <- forkIO $ runClient hdl wchan rchan stref
  acceptLoop sock clientListRef $ nextClientID cid

runClient :: Handle -> TChan String -> TChan String -> IORef ClientStatus -> IO ()
runClient hdl wchan rchan stref = do
  hSetBuffering hdl NoBuffering
  reader <- forkIO $ fix $ \loop -> do
    msg <- atomically $ readTChan rchan
    hPutStrLn hdl msg
    loop
  handle (\(SomeException _) -> return ()) $ fix $ \loop -> do
    line <- hGetLine hdl
    atomically $ writeTChan wchan line
    loop
  killThread reader
  atomicModifyIORef stref (\_ -> (Dead, ()))
  hClose hdl

--return a message if exists
--it's oldest about messages of same client
--no consistency about priority of clients
getClientMessage :: SimpleTCPServer -> IO (Maybe (ClientID, String))
getClientMessage (SimpleTCPServer (clientListRef, _, _)) = do
  clientList <- atomicModifyIORef clientListRef (\x -> (x, x))
  maybeChan <- findWithIOBool (atomically . liftM not . isEmptyTChan . getWchan) clientList
  case maybeChan of
    Just (cid, wchan, _, _) -> do 
      msg <- atomically $ readTChan wchan
      return $ Just (cid, msg)
    Nothing -> return Nothing

--return a message from a certain client if exists
--it's oldest about messages of same client
getClientMessageFrom :: SimpleTCPServer -> ClientID -> IO (Maybe String)
getClientMessageFrom (SimpleTCPServer (clientListRef, _, _)) cid = do
  clientList <- atomicModifyIORef clientListRef (\x -> (x, x))
  maybeClient <- return $ find ((==) cid . getClientID) clientList
  case maybeClient of
    Just (_, wchan, _, _) -> do
      isEmpty <- atomically $ isEmptyTChan wchan
      if isEmpty then return Nothing
                 else do
                      msg <- atomically $ readTChan wchan
                      return $ Just msg
    Nothing -> return Nothing

--return a list of one message for each client.
--ignore client with no message (so length of the list is the number of clients with messages)
--it's oldest about messages of same client
--no consistency about an order of messages
getEachClientMessages :: SimpleTCPServer -> IO [(ClientID, String)]
getEachClientMessages (SimpleTCPServer (clientListRef, _, _)) = do
  clientList <- atomicModifyIORef clientListRef (\x -> (x, x))
  notEmptyChanList <- filterWithIOBool (atomically . liftM not . isEmptyTChan . getWchan) clientList
  mapM (\(cid, wchan, _, _) -> do {msg <- atomically $ readTChan wchan; return (cid, msg)}) notEmptyChanList  

findWithIOBool :: (a -> IO Bool) -> [a] -> IO (Maybe a)
findWithIOBool _ [] = return Nothing
findWithIOBool predict (x:xs) = do
  predResult <- predict x
  if predResult then return $ Just x
                else findWithIOBool predict xs

filterWithIOBool :: (a -> IO Bool) -> [a] -> IO [a]
filterWithIOBool _ [] = return []
filterWithIOBool predict (x:xs) = do
  predResult <- predict x
  remainder <- filterWithIOBool predict xs
  if predResult then return $ x : remainder
                else filterWithIOBool predict xs


broadcastMessage :: SimpleTCPServer -> String -> IO ()
broadcastMessage (SimpleTCPServer (clientListRef, _, _)) msg = do
  clientList <- atomicModifyIORef clientListRef (\x -> (x, x))
  mapM_ (\(_, _, rchan, _) -> atomically $ writeTChan rchan msg) clientList

--return if a message can be sent
--False means that a client already disconnected
--disconnect check is executed every seconds
sendMessageTo :: SimpleTCPServer -> ClientID -> String -> IO Bool
sendMessageTo (SimpleTCPServer (clientListRef, _, _)) cid msg = do
  clientList <- atomicModifyIORef clientListRef (\x -> (x, x))
  maybeClient <- return $ find ((==) cid . getClientID) clientList
  case maybeClient of
    Just (_, _, rchan, _) -> do
      atomically $ writeTChan rchan msg
      return True
    Nothing -> return False

import Test.HUnit
import Network
import GHC.IO.Handle.Types
import System.IO
import Control.Concurrent
import qualified Network.SimpleTCPServer as STS


getClientMessageTest :: Test
getClientMessageTest = TestCase (
  do 
    server <- STS.runTCPServer 20017    
    handle1 <- connectTo "localhost" (PortNumber 20017)    
    hSetBuffering handle1 LineBuffering    
    handle2 <- connectTo "localhost" (PortNumber 20017)
    hSetBuffering handle2 LineBuffering
    
    hPutStrLn handle1 "test"
    threadDelay $ 10 * 1000
    clientmsg1 <- STS.getClientMessage server
    case clientmsg1 of 
      Nothing -> assertFailure "cannot get message (1)"
      Just (_, msg) -> assertEqual "compare sending message and result of getClientMessage" msg "test"
    
    hPutStrLn handle2 "test"
    hPutStrLn handle2 "test"
    threadDelay $ 10 * 1000
    clientmsg2 <- STS.getClientMessage server
    clientmsg3 <- STS.getClientMessage server
    case clientmsg2 of
      Nothing -> assertFailure "cannot get message (2)"
      Just (id2, _) ->
        case clientmsg3 of
          Nothing -> assertFailure "cannot get message (3)"
          Just (id3, _) ->
            assertEqual "compare 2 ids sent by same client" id2 id3
    
    hPutStrLn handle1 "test"
    hPutStrLn handle2 "test"
    threadDelay $ 10 * 1000
    clientmsg4 <- STS.getClientMessage server
    clientmsg5 <- STS.getClientMessage server
    case clientmsg4 of
      Nothing -> assertFailure "cannot get message (4)"
      Just (id4, _) ->
        case clientmsg5 of
          Nothing -> assertFailure "cannot get message (5)"
          Just (id5, _) ->
            assertBool "compare 2 ids sent by different clients" (id4 /= id5)
  
    clientmsg6 <- STS.getClientMessage server
    case clientmsg6 of
      Nothing -> return ()
      Just _ -> assertFailure "message should not exist"
  
    hPutStrLn handle1 "test1"
    threadDelay $ 10 * 1000
    hPutStrLn handle1 "test2"
    threadDelay $ 10 * 1000
    clientmsg7 <- STS.getClientMessage server
    case clientmsg7 of 
      Nothing -> assertFailure "cannot get message (7)"
      Just (_, msg) -> assertEqual "getting a oldest message" msg "test1"
    _ <- STS.getClientMessage server
  
    hClose handle1
    hClose handle2
    STS.shutdownServer server
  )

getClientMessageFromTest :: Test
getClientMessageFromTest = TestCase (
  do 
    server <- STS.runTCPServer 20017  
    handle1 <- connectTo "localhost" (PortNumber 20017)
    handle2 <- connectTo "localhost" (PortNumber 20017)
    hSetBuffering handle1 LineBuffering      
    hSetBuffering handle2 LineBuffering

    hPutStrLn handle1 "test"
    threadDelay $ 10 * 1000
    clientmsg1 <- STS.getClientMessage server
    id1 <- case clientmsg1 of 
      Nothing -> do {assertFailure "cannot get message (1)"; undefined}
      Just (tmpid, _) -> return tmpid
    hPutStrLn handle2 "test"
    threadDelay $ 10 * 1000
    clientmsg2 <- STS.getClientMessage server    
    id2 <- case clientmsg2 of 
      Nothing -> do {assertFailure "cannot get message (2)"; undefined}
      Just (tmpid, _) -> return tmpid
  
    hPutStrLn handle1 "test"
    threadDelay $ 10 * 1000
    clientmsg3 <- STS.getClientMessageFrom server id2
    case clientmsg3 of 
      Nothing -> return ()
      Just _ -> assertFailure "message should not exist on getClientMessageFrom"
    clientmsg4 <- STS.getClientMessageFrom server id1
    case clientmsg4 of 
      Nothing -> assertFailure "cannot get message (4)"
      Just msg -> assertEqual "compare sending message and result of getClientMessageFrom" msg "test"

    clientmsg5 <- STS.getClientMessageFrom server id1
    case clientmsg5 of
      Nothing -> return ()
      Just _ -> assertFailure "message should not exist"
      
    hPutStrLn handle1 "test1"
    threadDelay $ 10 * 1000
    hPutStrLn handle1 "test2"
    threadDelay $ 10 * 1000
    clientmsg6 <- STS.getClientMessageFrom server id1
    case clientmsg6 of 
      Nothing -> assertFailure "cannot get message (6)"
      Just msg -> assertEqual "getting a oldest message" msg "test1"
    _ <- STS.getClientMessage server
  
    hClose handle1
    hClose handle2
    STS.shutdownServer server    
  )

getEachClientMessagesTest :: Test
getEachClientMessagesTest = TestCase (
  do 
    server <- STS.runTCPServer 20017  
    handle1 <- connectTo "localhost" (PortNumber 20017)
    handle2 <- connectTo "localhost" (PortNumber 20017)
    hSetBuffering handle1 LineBuffering      
    hSetBuffering handle2 LineBuffering
    
    hPutStrLn handle1 "test"
    threadDelay $ 10 * 1000
    clientmsgs1 <- STS.getEachClientMessages server
    id1 <- case clientmsgs1 of 
      [] -> do {assertFailure "cannot get message (1)"; undefined}
      [(tmpid, _)] -> return tmpid
      _ : _ : _ -> do {assertFailure "too many messages (1)"; undefined}
    hPutStrLn handle2 "test"
    threadDelay $ 10 * 1000
    clientmsgs2 <- STS.getEachClientMessages server    
    id2 <- case clientmsgs2 of 
      [] -> do {assertFailure "cannot get message (2)"; undefined}
      [(tmpid, _)] -> return tmpid
      _ : _ : _ -> do {assertFailure "too many messages (1)"; undefined}

    hPutStrLn handle1 "test1 by client1"
    hPutStrLn handle1 "test2 by client1"
    hPutStrLn handle2 "test1 by client2"
    threadDelay $ 10 * 1000
    clientmsgs3 <- STS.getEachClientMessages server
    case clientmsgs3 of 
      [] -> do {assertFailure "cannot get message"; undefined}
      [_] -> do {assertFailure "cannot get message"; undefined}
      [(id3_1, msg3_1), (id3_2, msg3_2)] -> 
        if id3_1 == id1 then do
            assertEqual "get oldest message" msg3_1 "test1 by client1"
            assertEqual "compare ids" id3_2 id2
            assertEqual "compare messages" msg3_2 "test1 by client2"            
          else do
            assertEqual "get oldest message" msg3_2 "test1 by client1"
            assertEqual "compare ids" id3_2 id1
            assertEqual "compare ids" id3_1 id2            
            assertEqual "compare messages" msg3_1 "test1 by client2"            
      _ : _ : _ -> do {assertFailure "too many messages"; undefined}        
    
    clientmsgs4 <- STS.getEachClientMessages server
    case clientmsgs4 of
      [] -> do {assertFailure "cannot get message"; undefined}
      [(id4, msg4)] -> do
        assertEqual "compare ids" id4 id1
        assertEqual "compare messages" msg4 "test2 by client1"
      _ : _ -> do {assertFailure "cannot get messages"; undefined}
  
    clientmsgs5 <- STS.getEachClientMessages server
    case clientmsgs5 of
      [] -> return ()
      _ -> do {assertFailure "message should not exist"; undefined}
  
    hClose handle1
    hClose handle2
    STS.shutdownServer server    
  )

broadcastMessageTest :: Test
broadcastMessageTest = TestCase (
  do 
    server <- STS.runTCPServer 20017  
    handle1 <- connectTo "localhost" (PortNumber 20017)
    handle2 <- connectTo "localhost" (PortNumber 20017)
    hSetBuffering handle1 LineBuffering      
    hSetBuffering handle2 LineBuffering
    
    threadDelay $ 10 * 1000
    
    STS.broadcastMessage server "test1"
    threadDelay $ 10 * 1000
    msg1 <- hGetLine handle1
    case msg1 of
      "test1" -> return ()
      _ -> do {assertFailure "compare messages from handle and broadcast"; undefined}
    msg2 <- hGetLine handle2
    case msg2 of
      "test1" -> return ()
      _ -> do {assertFailure "compare messages from handle and broadcast"; undefined}

    STS.broadcastMessage server "test2"
    STS.broadcastMessage server "test3"
    threadDelay $ 10 * 1000
    msg3 <- hGetLine handle1
    case msg3 of
      "test2" -> return ()
      _ -> do {assertFailure "compare messages from handle and broadcast"; undefined}
    msg4 <- hGetLine handle1
    case msg4 of
      "test3" -> return ()
      _ -> do {assertFailure "compare messages from handle and broadcast"; undefined}
      
    hClose handle1
    hClose handle2
    STS.shutdownServer server    
  )

sendMessageToTest :: Test
sendMessageToTest = TestCase (
  do
    server <- STS.runTCPServer 20017  
    handle1 <- connectTo "localhost" (PortNumber 20017)
    handle2 <- connectTo "localhost" (PortNumber 20017)
    hSetBuffering handle1 LineBuffering      
    hSetBuffering handle2 LineBuffering
    
    hPutStrLn handle1 "test"
    threadDelay $ 10 * 1000
    clientmsgs1 <- STS.getEachClientMessages server
    id1 <- case clientmsgs1 of 
      [] -> do {assertFailure "cannot get message (1)"; undefined}
      [(tmpid, _)] -> return tmpid
      _ : _ : _ -> do {assertFailure "too many messages (1)"; undefined}
    hPutStrLn handle2 "test"
    threadDelay $ 10 * 1000
    clientmsgs2 <- STS.getEachClientMessages server    
    id2 <- case clientmsgs2 of 
      [] -> do {assertFailure "cannot get message (2)"; undefined}
      [(tmpid, _)] -> return tmpid
      _ : _ : _ -> do {assertFailure "too many messages (1)"; undefined}

    canSend1 <- STS.sendMessageTo server id1 "test1"
    case canSend1 of
      True -> return ()
      False -> do {assertFailure "cannot sendMessageTo"; undefined}
    canSend2 <- STS.sendMessageTo server id2 "test2"
    case canSend2 of
      True -> return ()
      False -> do {assertFailure "cannot sendMessageTo"; undefined}
    threadDelay $ 10 * 1000
    msg1 <- hGetLine handle1
    case msg1 of
      "test1" -> return ()
      _ -> do {assertFailure "compare messages from handle and broadcast"; undefined}
    msg2 <- hGetLine handle2
    case msg2 of
      "test2" -> return ()
      _ -> do {assertFailure "compare messages from handle and broadcast"; undefined}
  
    hClose handle1
    threadDelay $ 2000 * 1000
    canSend3 <- STS.sendMessageTo server id1 "test"
    case canSend3 of
      True -> do {assertFailure "sending a message to a disconnected client is succeeded"; undefined}
      False -> return ()
    
    hClose handle2
    STS.shutdownServer server    
  )


tests :: Test
tests = TestList [TestLabel "getClientMessageTest" getClientMessageTest,
                  TestLabel "getClientMessageFromTest" getClientMessageFromTest,
                  TestLabel "getEachClientMessagesTest" getEachClientMessagesTest,
                  TestLabel "broadcastMessageTest" broadcastMessageTest,
                  TestLabel "sendMessageToTest" sendMessageToTest]

main :: IO ()
main = do
  _ <- runTestTT tests
  return ()

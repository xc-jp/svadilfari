-- |
-- Module      :  Database.Redis.Worker.Config
-- Copyright   :  © 2019 XCompass
-- License     :  BSD 3 clause
--
-- Maintainer  :  Mark Karpov <mark.karpov@tweag.io>
-- Stability   :  experimental
-- Portability :  portable
--
-- Configuration for running worker processes. You probably want to import
-- "Database.Redis.Worker" instead.

{-# LANGUAGE LambdaCase #-}

module Database.Redis.Worker.Config
  ( WorkerConfig (..)
  , WorkerFailure (..)
  , defaultWorkerConfig
  )
where

import Control.Exception (SomeException, Exception (..))
import Data.ByteString (ByteString)
import System.IO (hPutStrLn, hPrint, stderr)
import qualified Database.Redis as Redis

-- | Worker configuration.

data WorkerConfig = WorkerConfig
  { cfgConnectInfo :: !Redis.ConnectInfo -- ^ Redis connection info
  , cfgQueueKey :: ![ByteString] -- ^ Queue key
  , cfgTimeout :: !Integer -- ^ Queue timeout (in seconds), default is 1
  , cfgWorkerCount :: !Int -- ^ Number of worker threads, default is 5
  , cfgFailureHandler :: WorkerFailure -> IO ()
  }

-- | Failures related to reading queue and decoding messages from it.

data WorkerFailure
  = FailedToRead Redis.Reply -- ^ Failed to read queue with this key
  | FailedToDecode ByteString String -- ^ Failed to decode a message,
    -- arguments are: queue name and error message
  | QueueException SomeException
    -- ^ Worker thread threw synchronous exception

-- | Default 'WorkerConfig'.

defaultWorkerConfig :: WorkerConfig
defaultWorkerConfig = WorkerConfig
  { cfgConnectInfo = Redis.defaultConnectInfo
  , cfgQueueKey = []
  , cfgTimeout = 1
  , cfgWorkerCount = 5
  , cfgFailureHandler = defaultFailureHandler
  }

-- | Default failure handler.

defaultFailureHandler :: WorkerFailure -> IO ()
defaultFailureHandler = \case
  FailedToRead reply -> do
    hPutStrLn stderr "Failed to read queue:"
    hPrint stderr reply
  FailedToDecode queue err -> do
    hPutStrLn stderr ("Failed to decode queue " ++ show queue)
    hPutStrLn stderr err
  QueueException e ->
    hPutStrLn stderr (displayException e)

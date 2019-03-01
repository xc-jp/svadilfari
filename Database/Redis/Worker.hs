-- |
-- Module      :  Database.Redis.Worker
-- Copyright   :  © 2019 XCompass
-- License     :  BSD 3 clause
--
-- Maintainer  :  Mark Karpov <markkarpov92@gmail.com>
-- Stability   :  experimental
-- Portability :  portable
--
-- The module provides a way to listen to a Redis queue and execute an
-- action on every decoded 'Job'.
--
--     * Start by defining job data type and making it an instance of the
--       'Job' type class.
--     * Define function of the form @job -> WorkerT m ()@ that will be
--       executed for each job.
--     * Provide 'WorkerConfig'.
--     * Run workers using the 'runWorkers' function.

{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Database.Redis.Worker
  ( -- * Types
    WorkerT
  , WorkerConfig (..)
  , defaultWorkerConfig
  , WorkerFailure (..)
  , Job (..)
    -- * Runnig workers
  , runWorkers
  , liftRedis
  )
where

import Control.Monad.IO.Unlift (MonadUnliftIO)
import Control.Monad.Reader
import Data.Foldable (sequenceA_)
import Database.Redis (Redis)
import Database.Redis.Worker.Config
import Database.Redis.Worker.Job
import UnliftIO.Async
import UnliftIO.Exception
import UnliftIO.STM
import qualified Database.Redis as Redis

-- | Worker monad transformer.

type WorkerT m a = ReaderT Redis.Connection m a

-- | Run workers on @job@s. Configuration specifies how many worker threads
-- to run. All issues, including synchronous exceptions thrown from worker
-- therads are handled by 'cfgFailureHandler'.

runWorkers
  :: (Job job, MonadUnliftIO m)
  => WorkerConfig               -- ^ Worker configuration
  -> (job -> WorkerT m ())      -- ^ Computation to run on job
  -> m ()
runWorkers cfg f = do
  jobChannel <- newTChanIO
  runConcurrently . sequenceA_ $
    Concurrently . runWorkerT cfg . ($ jobChannel) <$>
      (schedulingThread cfg :
         replicate (cfgWorkerCount cfg) (workerThread cfg f))

-- | Scheduling thread.

schedulingThread
  :: (Job job, MonadIO m)
  => WorkerConfig               -- ^ Worker configuration
  -> TChan job                  -- ^ Job channel
  -> WorkerT m ()
schedulingThread cfg jobChannel = forever $ do
  let key = cfgQueueKey cfg
  liftRedis $ Redis.brpop key 1 >>= \case
    Left err ->
      liftIO . cfgFailureHandler cfg . FailedToRead $ err
    Right Nothing -> return ()
    Right (Just (name, bs)) ->
      case decodeJob name bs of
        Left err ->
          liftIO . cfgFailureHandler cfg $ FailedToDecode name err
        Right job ->
          (liftIO . atomically . writeTChan jobChannel) job

-- | Worker thread.

workerThread
  :: MonadUnliftIO m
  => WorkerConfig
  -> (job -> WorkerT m ())      -- ^ Action to perform on 'Job's
  -> TChan job                  -- ^ Job channel
  -> WorkerT m ()
workerThread cfg f jobChannel = forever $ do
  job <- atomically (readTChan jobChannel)
  catch (f job) (liftIO . cfgFailureHandler cfg . QueueException)

-- | Low-level runner for the 'WokrerT' monad.

runWorkerT
  :: MonadIO m
  => WorkerConfig               -- ^ Worker configuration
  -> WorkerT m ()               -- ^ Computation to run
  -> m ()
runWorkerT cfg m = do
  reddisConn <- liftIO $ Redis.checkedConnect (cfgConnectInfo cfg)
  runReaderT m reddisConn

-- | Run a computation in 'Redis' monad from 'Worker' monad.

liftRedis
  :: MonadIO m
  => Redis a
  -> WorkerT m a
liftRedis m = do
  conn <- ask
  liftIO (Redis.runRedis conn m)

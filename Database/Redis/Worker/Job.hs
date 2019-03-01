-- |
-- Module      :  Database.Redis.Worker.Job
-- Copyright   :  © 2019 Cross Compass Ltd.
-- License     :  BSD 3 clause
--
-- Maintainer  :  Mark Karpov <markkarpov92@gmail.com>
-- Stability   :  experimental
-- Portability :  portable
--
-- 'Job' type class definition. You probably want to import
-- "Database.Redis.Worker" instead.

module Database.Redis.Worker.Job
  ( Job (..)
  )
where

import Data.ByteString (ByteString)

-- | Jobs are characterized by the way they are decoded from binary data
-- fetched from Reddis. There is only way to decode a particular type of
-- job, but there may be many ways to run it.

class Job a where

  -- | Decode a job.

  decodeJob
    :: ByteString               -- ^ Queue name
    -> ByteString               -- ^ Job body
    -> Either String a

{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE BangPatterns #-}

-- |
-- Module: Chainweb.Test.Mining
-- Copyright: Copyright © 2021 Kadena LLC.
-- License: MIT
-- Maintainer: Lars Kuhtz <lars@kadena.io>
-- Stability: experimental
--
-- TODO
--
module Chainweb.Test.Mining
( tests
) where

import Control.Concurrent
import Control.Concurrent.Async
import Control.Lens

import Data.CAS.RocksDB
import Data.IORef
import Data.Maybe

import GHC.Stack

import System.LogLevel

import Test.Tasty
import Test.Tasty.HUnit

-- internal modules

import Chainweb.Chainweb.MinerResources
import Chainweb.Graph
import Chainweb.Logger
import Chainweb.Miner.Config
import Chainweb.Miner.Coordinator
import Chainweb.Test.CutDB hiding (tests)
import Chainweb.Version

-- -------------------------------------------------------------------------- --
--

tests :: RocksDb -> TestTree
tests rdb = testGroup "Mining"
    [ testCase "Miner account names are not empty strings" (nonEmptyMiningAccount rdb)
    ]

-- -------------------------------------------------------------------------- --
-- Test Mining Coordinator

withTestCoordinator
    :: HasCallStack
    => RocksDb
    -> Maybe MiningConfig
        -- ^ Custom Mining configuration. If coordination is disabled it will be
        -- set to enabled before the coordinator is initialized.
    -> (forall cas logger . Logger logger => logger -> MiningCoordination logger cas -> IO ())
    -> IO ()
withTestCoordinator rdb maybeConf a = do
    var <- newEmptyMVar
    x <- race (takeMVar var) $
        withTestCutDb rdb v id 0 (\_ _ -> return fakePact) (logFunction logger) $ \_ cdb ->
            withMiningCoordination logger conf cdb $ \case
                Nothing -> error "nonEmptyMiningAccount: Bug in the mining Code"
                Just coord -> do
                    a logger coord
                    putMVar var ()
    case x of
        Left () -> logFunctionText logger Info "withTestCoordinator: action finished"
        Right () -> logFunctionText logger Info "withTestCoordinator: coordinator service stopped"

  where
    v = Test pairChainGraph
    logger = genericLogger Warn print
    conf = fromMaybe defaultMining maybeConf
        & miningCoordination . coordinationEnabled .~ True

-- -------------------------------------------------------------------------- --
-- Tests

nonEmptyMiningAccount :: HasCallStack => RocksDb -> Assertion
nonEmptyMiningAccount rdb = withTestCoordinator rdb Nothing $ \_logger coord -> do
    !(PrimedWork !_) <- readIORef (_coordPrimedWork coord)
    return ()


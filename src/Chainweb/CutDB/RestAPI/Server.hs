{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

-- |
-- Module: Chainweb.CutDB.RestAPI.Server
-- Copyright: Copyright © 2018 Kadena LLC.
-- License: MIT
-- Maintainer: Lars Kuhtz <lars@kadena.io>
-- Stability: experimental
--
-- Server implementation of the 'Cut' REST API.
--
module Chainweb.CutDB.RestAPI.Server
(
-- * Handlers
  cutGetHandler
, cutPutHandler

-- * Cut Server
, cutServer
, cutGetServer

-- * Some Cut Server
, someCutServer
, someCutGetServer

-- * Run server
, serveCutOnPort
) where

import Control.Lens (view)
import Control.Monad.Except

import Data.IxSet.Typed
import Data.Proxy
import Data.Semigroup

import Network.HTTP.Types
import Network.Wai.Handler.Warp hiding (Port)
import qualified Network.Wai as Wai

import Servant.API
import Servant.Server

import Web.DeepRoute
import Web.DeepRoute.Wai

-- internal modules

import Chainweb.Cut
import Chainweb.Cut.CutHashes
import Chainweb.CutDB
import Chainweb.CutDB.RestAPI
import Chainweb.HostAddress
import Chainweb.RestAPI.Utils
import Chainweb.TreeDB (MaxRank(..))
import Chainweb.Utils
import Chainweb.Version

import P2P.Node.PeerDB
import P2P.Peer

-- -------------------------------------------------------------------------- --
-- Handlers

cutGetHandler :: CutDb cas -> Maybe MaxRank -> IO CutHashes
cutGetHandler db Nothing = cutToCutHashes Nothing <$> _cut db
cutGetHandler db (Just (MaxRank (Max mar))) = do
    !c <- _cut db
    !c' <- limitCut (view cutDbWebBlockHeaderDb db) (int mar) c
    return $! cutToCutHashes Nothing c'

cutPutHandler :: PeerDb -> CutDb cas -> CutHashes -> Handler NoContent
cutPutHandler pdb db c = case _peerAddr <$> _cutOrigin c of
    Nothing -> throwError $ err400 { errBody = "Cut is missing an origin entry" }
    Just addr -> do
        ps <- liftIO $ peerDbSnapshot pdb
        case getOne (getEQ addr ps) of
            Nothing -> throwError $ err401 { errBody = "Unknown peer" }
            Just{} -> NoContent <$ liftIO (addCutHashes db c)

-- -------------------------------------------------------------------------- --
-- Cut API Server

cutServer
    :: forall cas (v :: ChainwebVersionT)
    . PeerDb
    -> CutDbT cas v
    -> Server (CutApi v)
cutServer pdb (CutDbT db) = (liftIO . cutGetHandler db) :<|> cutPutHandler pdb db

cutGetServer
    :: forall cas (v :: ChainwebVersionT)
    . CutDbT cas v
    -> Server (CutGetApi v)
cutGetServer (CutDbT db) = liftIO . cutGetHandler db

cutGetApi :: CutDb cas -> Route (ChainwebVersion -> Wai.Application)
cutGetApi cutDb =
    choice "cut" $ terminus methodGet "application/json" $ \_ req respond -> do
        let maxheight = getParams req (queryParamMaybe "maxheight")
        respond . responseJSON status200 [] =<< cutGetHandler cutDb maxheight

-- -------------------------------------------------------------------------- --
-- Some Cut Server

someCutServerT :: PeerDb -> SomeCutDb cas -> SomeServer
someCutServerT pdb (SomeCutDb (db :: CutDbT cas v)) =
    SomeServer (Proxy @(CutApi v)) (cutServer pdb db)

someCutServer :: ChainwebVersion -> PeerDb -> CutDb cas -> SomeServer
someCutServer v pdb = someCutServerT pdb . someCutDbVal v

someCutGetServerT :: SomeCutDb cas -> SomeServer
someCutGetServerT (SomeCutDb (db :: CutDbT cas v)) =
    SomeServer (Proxy @(CutGetApi v)) (cutGetServer db)

someCutGetServer :: ChainwebVersion -> CutDb cas -> SomeServer
someCutGetServer v = someCutGetServerT . someCutDbVal v

-- -------------------------------------------------------------------------- --
-- Run Server

serveCutOnPort :: Port -> ChainwebVersion -> PeerDb -> CutDb cas -> IO ()
serveCutOnPort p v pdb = run (int p) . someServerApplication . someCutServer v pdb



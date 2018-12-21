//
//  MockMusicRemote.swift
//  Spotify TuneIn Tests
//
//  Created by Jonathan Berglind on 2018-12-20.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa

class MockMusicRemote: MusicRemote {
  var playerStateUpdates = [PlayerState]()

  var allowConnect = true
  var connected = false

  private var playerUpdatesRelay = PublishRelay<Event<PlayerState>>()

  func mockDisconnect() {
    connected = false
    playerUpdatesRelay.accept(.error("Player disconnected"))
  }

  func mockPlayerUpdateEvent(playerState: PlayerState) {
    if connected {
      playerUpdatesRelay.accept(.next(playerState))
    }
  }

  func connect() -> Completable {
    return Completable.create(subscribe: { [weak self] src in
      if self?.allowConnect ?? false {
        self?.connected = true
        src(.completed)
      } else {
        src(.error("Error connecting"))
      }
      return Disposables.create()
    })
  }

  func getPlayerUpdates() -> Observable<PlayerState> {
    return Observable.deferred({ [weak self] in
      guard let self = self else { return Observable.empty() }
      return self.connected
        ? self.playerUpdatesRelay.dematerialize().asObservable()
        : Observable.error("Not connected to remote")
    })
  }

  func updatePlayerToState(newState: PlayerState) -> Completable {
    return Completable.create(subscribe: { [weak self] src in
      if self?.connected ?? false {
        self?.playerStateUpdates.append(newState)
        src(.completed)
      } else {
        src(.error("Not connected to remote"))
      }
      return Disposables.create()
    })
  }
}

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
  let isConnectedRelay = BehaviorRelay<Bool>(value: false)
  let playerStateRelay = BehaviorRelay<PlayerState?>(value: nil)
  let errorRelay = PublishRelay<Error>()

  var isConnected: Driver<Bool> { return isConnectedRelay.asDriver() }
  var playerState: Driver<PlayerState?> { return playerStateRelay.asDriver() }
  var unexpectedErrors: Signal<Error> { return errorRelay.asSignal() }

  var allowConnect = true
  var playerStateUpdates = [PlayerState]()

  func mockDisconnect() {
    isConnectedRelay.accept(false)
    playerStateRelay.accept(nil)
    errorRelay.accept("Disconnected")
  }

  func mockPlayerUpdateEvent(playerState: PlayerState) {
    if isConnectedRelay.value {
      playerStateRelay.accept(playerState)
    }
  }

  func connect() -> Completable {
    return Completable.create(subscribe: { [weak self] src in
      if self?.allowConnect ?? false {
        self?.isConnectedRelay.accept(true)
        src(.completed)
      } else {
        src(.error("Error connecting"))
      }
      return Disposables.create()
    })
  }

  func updatePlayerToState(newState: PlayerState) -> Completable {
    return Completable.create(subscribe: { [weak self] src in
      if self?.isConnectedRelay.value ?? false {
        self?.playerStateUpdates.append(newState)
        self?.playerStateRelay.accept(newState)
        src(.completed)
      } else {
        src(.error("Not connected to remote"))
      }
      return Disposables.create()
    })
  }
}

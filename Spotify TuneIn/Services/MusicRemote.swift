//
//  MusicManager.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-20.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa

protocol MusicRemote {
  var isConnected: Driver<Bool> { get }
  var playerState: Driver<PlayerState?> { get }
  var unexpectedErrors: Signal<Error> { get }
  func connect() -> Completable
  func updatePlayerToState(newState: PlayerState) -> Completable
}

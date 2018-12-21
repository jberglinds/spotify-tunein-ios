//
//  MusicManager.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-20.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import Foundation
import RxSwift

protocol MusicRemote {
  func connect() -> Completable
  func getPlayerUpdates() -> Observable<PlayerState>
  func updatePlayerToState(newState: PlayerState) -> Completable
}

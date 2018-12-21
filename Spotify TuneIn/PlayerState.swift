//
//  PlayerState.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-20.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import Foundation

struct PlayerState: Codable {
  var isPaused: Bool
  var trackURI: String
  var playbackPosition: Int
}

extension PlayerState: Equatable {}

//
//  BackgroundManager.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-21.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import Foundation
import AVFoundation

class BackgroundManager {
  private var player: AVAudioPlayer?

  static let shared = BackgroundManager()
  private init() {}

  /// Start playing silence if not already doing that. Keeps us alive in background
  func playSilence() {
    // Bail out if unit test
    guard ProcessInfo.processInfo.environment["XCInjectBundleInto"] == nil else { return }

    guard let silence = NSDataAsset(name: "Silence") else {
      return
    }

    do {
      try AVAudioSession.sharedInstance()
        .setCategory(.playback, mode: .default, options: .mixWithOthers)
      try AVAudioSession.sharedInstance().setActive(true)

      player = try AVAudioPlayer(data: silence.data, fileTypeHint: "mp3")

      guard let player = player else { return }
      if !player.isPlaying {
        player.numberOfLoops = -1
        player.play()
        print("Starting to play silence")
      }
    } catch let error {
      print(error.localizedDescription)
    }
  }

  func stopSilence() {
    print("Ending silence")
    player?.stop()
  }
}


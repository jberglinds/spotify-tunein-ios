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

  func playSilence() {
    guard let url = Bundle.main.url(forResource: "silence", withExtension: "mp3") else { return }

    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
      try AVAudioSession.sharedInstance().setActive(true)

      player = try AVAudioPlayer(contentsOf: url, fileTypeHint: AVFileType.mp3.rawValue)

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


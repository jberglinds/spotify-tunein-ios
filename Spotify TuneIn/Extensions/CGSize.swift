//
//  CGSize.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-31.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import Foundation

extension CGSize {
  /// Returns a new CGSize, scaled by the current pixels per point ratio
  var scaled: CGSize {
    let scale = UIScreen.main.scale
    return CGSize(width: self.width * scale,
                  height: self.height * scale)
  }
}

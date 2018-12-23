//
//  RoundedButton.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-23.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import UIKit

@IBDesignable class RoundedButton: UIButton {
  @IBInspectable var cornerRadius: CGFloat = 10 {
    didSet {
      updateCornerRadius()
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    setup()
  }

  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    setup()
  }

  override func prepareForInterfaceBuilder() {
    setup()
  }

  private func setup() {
    updateCornerRadius()
  }

  private func updateCornerRadius() {
    layer.cornerRadius = cornerRadius
  }
}

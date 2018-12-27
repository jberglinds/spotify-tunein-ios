//
//  RadioStation.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-26.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import Foundation

class RadioStation: NSObject, Codable {
  init(name: String, coordinate: Coordinate?) {
    self.name = name
    self.coordinate = coordinate
  }

  var name: String
  var coordinate: Coordinate?
}

struct Coordinate: Codable {
  var lat: Double
  var lng: Double
}

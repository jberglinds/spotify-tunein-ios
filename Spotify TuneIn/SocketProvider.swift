//
//  SocketProvider.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-19.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import Foundation

enum ClientEvent {
  case connect
  case error
}

protocol AckEmitter {
  func with(_ items: Any...)
}

protocol SocketProvider {
  func connect()
  func on(clientEvent: ClientEvent, callback: @escaping ([Any], AckEmitter) -> ())
  func on(_ event: String, callback: @escaping ([Any], AckEmitter) -> ())
  func emit(event: String, data: Any...)
  func emitWithAck(event: String, data: Any..., ackCallback: @escaping ([Any]) -> ())
}

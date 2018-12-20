//
//  SocketIOProvider.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-19.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import Foundation
import SocketIO

extension SocketAckEmitter: AckEmitter {
  func with(_ items: Any...) {
    with(items)
  }
}

extension ClientEvent {
  var socketClientEvent: SocketClientEvent {
    return self == .connect ? .connect : .error
  }
}

class SocketIOProvider: SocketProvider {
  var socketManager: SocketManager
  var socket: SocketIOClient

  init(url: String, namespace: String? = nil) {
    socketManager = SocketManager(socketURL: URL(string: url)!,
                                  config: [.compress])
    socket = socketManager.socket(forNamespace: namespace ?? "/")
  }

  func connect() {
    socket.connect()
  }

  func on(clientEvent: ClientEvent, callback: @escaping ([Any], AckEmitter) -> ()) {
    socket.on(clientEvent: clientEvent.socketClientEvent, callback: callback)
  }

  func on(_ event: String, callback: @escaping (([Any], AckEmitter) -> ())) {
    socket.on(event, callback: callback)
  }

  func emit(event: String, data: Any...){
    socket.emit(event, data)
  }

  func emitWithAck(event: String, data: Any..., ackCallback: @escaping ([Any]) -> ()) {
    socket.emitWithAck(event, data).timingOut(after: 1.0, callback: ackCallback)
  }
}

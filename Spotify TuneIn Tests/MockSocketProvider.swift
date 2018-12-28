//
//  MockSocketProvider.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-19.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import Foundation

class MockAckEmitter: AckEmitter {
  func with(_ items: [Any]) {}
}

class MockSocketProvider: SocketProvider {
  private var clientCallbacks = [ClientEvent: ([Any], AckEmitter) -> ()]()
  private var callbacks = [String: ([Any], AckEmitter) -> ()]()

  private var ackResponderData = [String: [Any]]()

  var emittedEvents = [String]()

  var connected = false
  lazy var defaultAckResponder = {
    return self.connected ? [] : ["NO ACK"]
  }

  func mockIncomingClientEvent(_ clientEvent: ClientEvent) {
    if let callback = clientCallbacks[clientEvent] {
      callback([], MockAckEmitter())
    }
  }

  func mockIncomingEvent(_ event: String, data: Any...) {
    if let callback = callbacks[event] {
      callback(data, MockAckEmitter())
    }
  }

  func mockAckResponderData(for event: String, data: Any...) {
    ackResponderData[event] = data
  }

  func connect() {
    mockIncomingClientEvent(.connect)
    connected = true
  }

  func disconnectWithError() {
    mockIncomingClientEvent(.error)
    connected = false
  }

  func on(clientEvent: ClientEvent, callback: @escaping ([Any], AckEmitter) -> ()) {
    self.clientCallbacks[clientEvent] = callback
  }

  func on(_ event: String, callback: @escaping ([Any], AckEmitter) -> ()) {
    self.callbacks[event] = callback
  }

  func emit(event: String, data: [Any]) {
    if connected {
      emittedEvents.append(event)
    }
  }

  func emitWithAck(event: String, data: [Any], ackCallback: @escaping ([Any]) -> ()) {
    if connected {
      emittedEvents.append(event)
      if let ackData = ackResponderData[event] {
        ackCallback(ackData)
        return
      }
    }
    ackCallback(defaultAckResponder())
  }
}

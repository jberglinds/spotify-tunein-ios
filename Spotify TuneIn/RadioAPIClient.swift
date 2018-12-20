//
//  RadioAPIClient.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-18.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import Foundation
import SocketIO
import RxSwift

class RadioAPIClient {
  enum SocketEvent: String {
    case startBroadcast = "start-broadcast"
    case endBroadcast = "end-broadcast"
    case updatePlayerState = "update-player-state"
    case joinBroadcast = "join-broadcast"
    case leaveBroadcast = "leave-broadcast"
    case playerStateUpdated = "player-state-updated"
    case broadcastEnded = "broadcast-ended"
    case listenerCountChanged = "listener-count-changed"
  }

  enum ListenerEvent {
    case playerStateChanged(PlayerState)
  }

  enum BroadcasterEvent {
    case listenerCountChanged(newCount: Int)
  }

  private var socket: SocketProvider

  private var broadcasterStreams = [UUID: PublishSubject<BroadcasterEvent>]()
  private var listenerStreams = [UUID: PublishSubject<ListenerEvent>]()

  private(set) var isBroadcasting = false
  private(set) var isListening = false

  init(socket: SocketProvider) {
    self.socket = socket

    socket.on(clientEvent: .connect) { _, _ in
      print("Socket connected")
    }

    socket.on(clientEvent: .error) { [weak self] _, _ in
      self?.isBroadcasting = false
      self?.isListening = false
      self?.listenerStreams.values.forEach({ $0.onError("Lost connection to server") })
      self?.broadcasterStreams.values.forEach({ $0.onError("Lost connection to server") })
    }

    socket.on(SocketEvent.broadcastEnded.rawValue) { [weak self] data, _ in
      self?.listenerStreams.values.forEach({ $0.onCompleted() })
      self?.isListening = false
    }

    socket.on(SocketEvent.playerStateUpdated.rawValue) { [weak self] data, _ in
      guard let first = data.first as? [String: Any] else { return }
      guard let state = PlayerState(data: first) else { return }
      self?.listenerStreams.values.forEach({ $0.onNext(.playerStateChanged(state)) })
    }

    socket.on(SocketEvent.listenerCountChanged.rawValue) { [weak self] data, _ in
      self?.broadcasterStreams.values.forEach({
        $0.onNext(.listenerCountChanged(newCount: 1))
      })
    }

    socket.connect()
  }

  func startBroadcasting(stationName: String) -> Completable {
    return endBroadcasting()
      .andThen(socket
        .emitWithAck(event: .startBroadcast, data: stationName)
        .do(onCompleted: { [weak self] in
          self?.isBroadcasting = true
        }))
  }

  func getBroadcasterEvents() -> Observable<BroadcasterEvent> {
    let subject = PublishSubject<BroadcasterEvent>()
    let uuid = UUID()
    return Completable.create(subscribe: { [weak self] src in
      if !(self?.isBroadcasting ?? false) {
        src(.error("Not currently broadcasting"))
      } else {
        self?.broadcasterStreams[uuid] = subject
        src(.completed)
      }
      return Disposables.create()
    }).andThen(subject).do(onDispose: { [weak self] in
      self?.broadcasterStreams.removeValue(forKey: uuid)
    })
  }

  func endBroadcasting() -> Completable {
    return socket.emitWithAck(event: .endBroadcast)
      .do(onCompleted: { [weak self] in
        self?.isBroadcasting = false
        self?.broadcasterStreams.values.forEach({ $0.onCompleted() })
      })
  }

  func joinBroadcast(stationName: String) -> Completable {
    return endBroadcasting()
      .andThen(socket
        .emitWithAck(event: .joinBroadcast, data: stationName)
        .do(onCompleted: { [weak self] in
          self?.isListening = true
        }))
  }

  func getListenerEvents() -> Observable<ListenerEvent> {
    let subject = PublishSubject<ListenerEvent>()
    let uuid = UUID()
    return Completable.create(subscribe: { [weak self] src in
      if !(self?.isListening ?? false) {
        src(.error("Not currently listening"))
      } else {
        self?.listenerStreams[uuid] = subject
        src(.completed)
      }
      return Disposables.create()
    }).andThen(subject).do(onDispose: { [weak self] in
      self?.listenerStreams.removeValue(forKey: uuid)
    })
  }

  func leaveBroadcast() -> Completable {
    return socket.emitWithAck(event: .leaveBroadcast)
      .do(onCompleted: { [weak self] in
        self?.isListening = false
        self?.listenerStreams.values.forEach({ $0.onCompleted() })
      })
  }

  func broadcastPlayerStateChange(newState: PlayerState) -> Completable {
    return Completable.create(subscribe: { [weak self] src in
      if self?.isBroadcasting ?? true {
        src(.completed)
      } else {
        src(.error("Not currently broadcasting"))
      }
      return Disposables.create()
    }).andThen(
      socket.emitWithAck(event: .updatePlayerState, data: newState.socketRepresentation())
    )
  }
}

extension SocketProvider {
  func emitWithAck(event: RadioAPIClient.SocketEvent, data: Any...) -> Completable {
    return Completable.create { completable in
      self.emitWithAck(event: event.rawValue, data: data) { data in
        // FIXME: Proper error handling
        if let error = data.first as? String {
          if error == "NO ACK" {
            completable(.error("No response from server"))
          } else {
            completable(.error(error))
          }
        }
        completable(.completed)
      }
      return Disposables.create {}
    }
  }
}

extension PlayerState {
  init?(data: [String: Any]) {
    guard
      let isPaused = data["isPaused"] as? Bool,
      let playbackPosition = data["playbackPosition"] as? Int,
      let trackURI = data["trackURI"] as? String
    else { return nil }
    self.isPaused = isPaused
    self.playbackPosition = playbackPosition
    self.trackURI = trackURI
  }

  func socketRepresentation() -> SocketData {
    return [
      "isPaused": self.isPaused,
      "playbackPosition": self.playbackPosition,
      "trackURI": self.trackURI
    ]
  }
}

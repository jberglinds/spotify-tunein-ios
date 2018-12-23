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
import RxCocoa

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

  private var broadcasterRelay = PublishRelay<Event<BroadcasterEvent>>()
  private var listenerRelay = PublishRelay<Event<ListenerEvent>>()

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
      self?.listenerRelay.accept(.error("Lost connection to server"))
      self?.broadcasterRelay.accept(.error("Lost connection to server"))
    }

    socket.on(SocketEvent.broadcastEnded.rawValue) { [weak self] data, _ in
      self?.listenerRelay.accept(.completed)
      self?.isListening = false
    }

    socket.on(SocketEvent.playerStateUpdated.rawValue) { [weak self] data, _ in
      guard let first = data.first as? [String: Any] else { return }
      guard let state = PlayerState(data: first) else { return }
      self?.listenerRelay.accept(.next(.playerStateChanged(state)))
    }

    socket.on(SocketEvent.listenerCountChanged.rawValue) { [weak self] data, _ in
      self?.broadcasterRelay.accept(.next(.listenerCountChanged(newCount: 1)))
    }

    socket.connect()
  }

  func startBroadcasting(stationName: String) -> Completable {
    return socket
      .emitWithAck(event: .startBroadcast, data: stationName)
      .do(onCompleted: { [weak self] in
        self?.isBroadcasting = true
        self?.isListening = false
      })
  }

  func getBroadcasterEvents() -> Observable<BroadcasterEvent> {
    return Observable.deferred({ [weak self] in
      guard let self = self else { return Observable.empty() }
      return self.isBroadcasting
        ? self.broadcasterRelay.dematerialize().asObservable()
        : Observable.error("Not currently broadcasting")
    })
  }

  func endBroadcasting() -> Completable {
    return socket.emitWithAck(event: .endBroadcast)
      .do(onCompleted: { [weak self] in
        self?.isBroadcasting = false
        self?.broadcasterRelay.accept(.completed)
      })
  }

  func joinBroadcast(stationName: String) -> Completable {
    return socket
      .emitWithAck(event: .joinBroadcast, data: stationName)
      .do(onCompleted: { [weak self] in
        self?.isBroadcasting = false
        self?.isListening = true
      })
  }

  func getListenerEvents() -> Observable<ListenerEvent> {
    return Observable.deferred({ [weak self] in
      guard let self = self else { return Observable.empty() }
      return self.isListening
        ? self.listenerRelay.dematerialize().asObservable()
        : Observable.error("Not currently listening")
    })
  }

  func leaveBroadcast() -> Completable {
    return socket.emitWithAck(event: .leaveBroadcast)
      .do(onCompleted: { [weak self] in
        self?.isListening = false
        self?.listenerRelay.accept(.completed)
      })
  }

  func broadcastPlayerStateChange(newState: PlayerState) -> Completable {
    return Completable.create(subscribe: { [weak self] src in
      if self?.isBroadcasting ?? false {
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
      let timestamp = data["timestamp"] as? Int,
      let isPaused = data["isPaused"] as? Bool,
      let playbackPosition = data["playbackPosition"] as? Int,
      let trackURI = data["trackURI"] as? String
    else { return nil }
    self.timestamp = timestamp
    self.isPaused = isPaused
    self.playbackPosition = playbackPosition
    self.trackURI = trackURI
    self.trackName = nil
    self.trackArtist = nil
  }

  func socketRepresentation() -> SocketData {
    return [
      "timestamp": self.timestamp,
      "isPaused": self.isPaused,
      "playbackPosition": self.playbackPosition,
      "trackURI": self.trackURI
    ]
  }
}

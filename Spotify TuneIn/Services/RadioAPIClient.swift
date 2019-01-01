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
  // MARK: - Models
  enum IncomingEvent: String {
    case playerStateUpdated = "player-state-updated"
    case broadcastEnded = "broadcast-ended"
    case listenerCountChanged = "listener-count-changed"
  }

  enum OutgoingEvent: String {
    case startBroadcast = "start-broadcast"
    case endBroadcast = "end-broadcast"
    case updatePlayerState = "update-player-state"
    case joinBroadcast = "join-broadcast"
    case leaveBroadcast = "leave-broadcast"
  }

  enum ListenerEvent {
    case playerStateChanged(PlayerState)
    case broadcastEnded
  }

  enum BroadcasterEvent {
    case listenerCountChanged(newCount: Int)
  }

  struct State {
    var isBroadcasting = false
    var isListenening = false
  }

  enum UnexpectedError {
    case disconnected
  }

  // MARK: - Properties
  private var socket: SocketProvider
  private var broadcasterRelay = PublishRelay<BroadcasterEvent>()
  private var listenerRelay = PublishRelay<ListenerEvent>()
  private var stateRelay = BehaviorRelay<State>(
    value: State(isBroadcasting: false, isListenening: false)
  )
  private var errorRelay = PublishRelay<UnexpectedError>()

  var broadcasterEvents: Signal<BroadcasterEvent> { return broadcasterRelay.asSignal() }
  var listenerEvents: Signal<ListenerEvent> { return listenerRelay.asSignal() }
  var state: Driver<State> { return stateRelay.asDriver() }
  var errors: Signal<UnexpectedError> { return errorRelay.asSignal() }

  // MARK: - Initialization
  init(socket: SocketProvider) {
    self.socket = socket

    socket.on(clientEvent: .connect) { _, _ in
      print("Socket connected")
    }

    socket.on(clientEvent: .error) { _, _ in
      self.errorRelay.accept(.disconnected)
      self.stateRelay.accept(
        State(isBroadcasting: false, isListenening: false)
      )
    }

    socket.on(clientEvent: .disconnect) {  _, _ in
      self.errorRelay.accept(.disconnected)
      self.stateRelay.accept(
        State(isBroadcasting: false, isListenening: false)
      )
    }

    socket.on(IncomingEvent.broadcastEnded.rawValue) { data, _ in
      self.listenerRelay.accept(.broadcastEnded)
      self.stateRelay.accept(
        State(isBroadcasting: false, isListenening: false)
      )
    }

    socket.on(IncomingEvent.playerStateUpdated.rawValue) { data, _ in
      guard let first = data.first  else { return }
      guard let state = PlayerState(from: first) else { return }
      self.listenerRelay.accept(.playerStateChanged(state))
    }

    socket.on(IncomingEvent.listenerCountChanged.rawValue) { data, _ in
      self.broadcasterRelay.accept(.listenerCountChanged(newCount: 1))
    }

    socket.connect()
  }

  // MARK: - API Actions
  func startBroadcasting(station: RadioStation) -> Completable {
    return socket
      .emitWithVoidAck(event: .startBroadcast, data: station.socketRepresentation())
      .do(onCompleted: { [weak self] in
        self?.stateRelay.accept(
          State(isBroadcasting: true, isListenening: false)
        )
      })
  }

  func endBroadcasting() -> Completable {
    return socket.emitWithVoidAck(event: .endBroadcast)
      .do(onCompleted: { [weak self] in
        self?.stateRelay.accept(
          State(isBroadcasting: false, isListenening: false)
        )
      })
  }

  func joinBroadcast(stationName: String) -> Completable {
    return socket
      .emitWithAck(event: .joinBroadcast, data: stationName)
      .do(onSuccess: { [weak self] state in
        self?.stateRelay.accept(
          State(isBroadcasting: false, isListenening: true)
        )
      })
      .map({ value throws -> PlayerState in
        if let state = PlayerState(from: value) {
          return state
        } else {
          throw "Invalid payload"
        }
      })
      .do(onSuccess: { state in
        self.listenerRelay.accept(.playerStateChanged(state))
      })
      .asCompletable()
  }

  func leaveBroadcast() -> Completable {
    return socket.emitWithVoidAck(event: .leaveBroadcast)
      .do(onCompleted: { [weak self] in
        self?.stateRelay.accept(
          State(isBroadcasting: false, isListenening: false)
        )
      })
  }

  func broadcastPlayerStateChange(newState: PlayerState) -> Completable {
    return Completable.create(subscribe: { [weak self] src in
      if self?.stateRelay.value.isBroadcasting ?? false {
        src(.completed)
      } else {
        src(.error("Not currently broadcasting"))
      }
      return Disposables.create()
    }).andThen(
      socket.emitWithVoidAck(event: .updatePlayerState,
                             data: newState.socketRepresentation())
    )
  }
}

// MARK: - Private Extensions
private extension SocketProvider {
  func emitWithVoidAck(event: RadioAPIClient.OutgoingEvent, data: SocketData...)
    -> Completable {
      let maybe = emitWithAck(event: event, data: data)
      return maybe.asObservable().ignoreElements()
  }

  func emitWithAck(event: RadioAPIClient.OutgoingEvent, data: SocketData...)
    -> Single<Any> {
      let maybe: Maybe<Any> = emitWithAck(event: event, data: data)
      return maybe.asObservable().asSingle()
  }

  private func emitWithAck(event: RadioAPIClient.OutgoingEvent, data: [SocketData])
    -> Maybe<Any> {
      return Maybe.create { src in
        self.emitWithAck(event: event.rawValue, data: data) { data in
          if let first = data.first {
            if let error = first as? String {
              if error == "NO ACK" {
                src(.error("No response from server"))
              } else {
                src(.error(error))
              }
            } else {
              src(.success(first))
            }
          } else {
            src(.completed)
          }
        }
        return Disposables.create()
      }
  }
}

extension PlayerState {
  init?(from: Any) {
    guard
      let dict = from as? [String: Any],
      let timestamp = dict["timestamp"] as? Int,
      let isPaused = dict["isPaused"] as? Bool,
      let playbackPosition = dict["playbackPosition"] as? Int,
      let trackURI = dict["trackURI"] as? String
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

private extension RadioStation {
  func socketRepresentation() -> SocketData {
    var data: [String: Any] = [
      "name": self.name
    ]
    if let coordinate = self.coordinate {
      data["coordinate"] = [
        "lat": coordinate.lat,
        "lng": coordinate.lng
      ]
    }
    return data
  }
}

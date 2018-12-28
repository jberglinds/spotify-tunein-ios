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

    socket.on(IncomingEvent.broadcastEnded.rawValue) { [weak self] data, _ in
      self?.listenerRelay.accept(.completed)
      self?.isListening = false
    }

    socket.on(IncomingEvent.playerStateUpdated.rawValue) { [weak self] data, _ in
      guard let first = data.first  else { return }
      guard let state = PlayerState(from: first) else { return }
      self?.listenerRelay.accept(.next(.playerStateChanged(state)))
    }

    socket.on(IncomingEvent.listenerCountChanged.rawValue) { [weak self] data, _ in
      self?.broadcasterRelay.accept(.next(.listenerCountChanged(newCount: 1)))
    }

    socket.connect()
  }

  func startBroadcasting(station: RadioStation) -> Completable {
    return socket
      .emitWithVoidAck(event: .startBroadcast, data: station.socketRepresentation())
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
    return socket.emitWithVoidAck(event: .endBroadcast)
      .do(onCompleted: { [weak self] in
        self?.isBroadcasting = false
        self?.broadcasterRelay.accept(.completed)
      })
  }

  func joinBroadcast(stationName: String) -> Single<PlayerState> {
    return socket
      .emitWithAck(event: .joinBroadcast, data: stationName)
      .map({ value in
        if let state = PlayerState(from: value) {
          return state
        } else {
          throw "Invalid payload"
        }
      })
      .do(onSuccess: { [weak self] _ in
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
    return socket.emitWithVoidAck(event: .leaveBroadcast)
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
      socket.emitWithVoidAck(event: .updatePlayerState,
                             data: newState.socketRepresentation())
    )
  }
}

extension SocketProvider {
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

extension PlayerState: SocketData {
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

extension RadioStation: SocketData {
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

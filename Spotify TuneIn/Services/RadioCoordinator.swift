//
//  RadioCoordinator.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-19.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa

class RadioCoordinator {
  // MARK: - Models
  struct State {
    var stationName: String?
    var isListening = false
    var isBroadcasting = false
  }

  enum UnexpectedError {
    case apiDisconnected
    case remoteDisconnected
  }

  // MARK: - Properties
  private var api: RadioAPIClient
  private var remote: MusicRemote
  private let disposeBag = DisposeBag()

  private let stateRelay = BehaviorRelay<State>(
    value: State(stationName: nil, isListening: false, isBroadcasting: false)
  )
  var state: Driver<State> { return stateRelay.asDriver() }

  private let errorRelay = PublishRelay<UnexpectedError>()
  var errors: Signal<UnexpectedError> { return errorRelay.asSignal() }

  // MARK: - Initialization
  init(api: RadioAPIClient, remote: MusicRemote) {
    self.api = api
    self.remote = remote

    // Forward the state from the api to our own state relay
    api.state.drive(onNext: { apiState in
      var state = self.stateRelay.value
      state.isBroadcasting = apiState.isBroadcasting
      state.isListening = apiState.isListenening
      self.stateRelay.accept(state)
    }).disposed(by: disposeBag)

    // Play silence if listening or broadcasting to not get killed in background
    api.state.drive(onNext: { apiState in
      if apiState.isListenening || apiState.isBroadcasting {
        BackgroundManager.shared.playSilence()
      } else {
        BackgroundManager.shared.stopSilence()
        var state = self.stateRelay.value
        state.stationName = nil
        self.stateRelay.accept(state)
      }
    }).disposed(by: disposeBag)

    // When remote disconnects we want to stop broadcasting or listening if doing that
    remote.unexpectedErrors.asObservable()
      .withLatestFrom(api.state, resultSelector: { ($0, $1) })
      .subscribe(onNext: { (error, apiState) in
        // TODO: Handle errors
        if apiState.isListenening {
          api.leaveBroadcast().subscribe().disposed(by: self.disposeBag)
        } else if apiState.isBroadcasting {
          api.endBroadcasting().subscribe().disposed(by: self.disposeBag)
        }
      }).disposed(by: disposeBag)

    // Broadcast updates from player to api if broadcasting
    Observable.combineLatest(api.state.asObservable(), remote.playerState.asObservable())
      .subscribe(onNext: { (apiState, playerState) in
        guard apiState.isBroadcasting else { return }
        guard let playerState = playerState else { return }
        api.broadcastPlayerStateChange(newState: playerState)
          .subscribe().disposed(by: self.disposeBag)
      }).disposed(by: disposeBag)

    // Update player from api if listening
    api.listenerEvents.asObservable()
      .withLatestFrom(api.state, resultSelector: { ($0, $1) })
      .subscribe(onNext: { (apiEvent, apiState) in
        guard apiState.isListenening else { return }
        guard case .playerStateChanged(let state) = apiEvent else { return }
        remote.updatePlayerToState(newState: state)
          .subscribe().disposed(by: self.disposeBag)
      }).disposed(by: disposeBag)

    // Forward any errors to our own error relay
    remote.unexpectedErrors.map({ _ in UnexpectedError.remoteDisconnected })
      .emit(to: errorRelay)
      .disposed(by: disposeBag)
    api.errors.map({ _ in UnexpectedError.apiDisconnected })
      .emit(to: errorRelay)
      .disposed(by: disposeBag)
  }

  // MARK: - Radio actions
  func startBroadcast(station: RadioStation) -> Completable {
    return remote
      .connect()
      .andThen(api.startBroadcasting(station: station))
      .do(onCompleted: {
        var state = self.stateRelay.value
        state.stationName = station.name
        self.stateRelay.accept(state)
      })
  }

  func endBroadcast() -> Completable {
    return api.endBroadcasting()
  }

  func joinBroadcast(stationName: String) -> Completable {
    return remote
      .connect()
      .andThen(api.joinBroadcast(stationName: stationName))
      .do(onCompleted: {
        var state = self.stateRelay.value
        state.stationName = stationName
        self.stateRelay.accept(state)
      })
  }

  func leaveBroadcast() -> Completable {
    return api.leaveBroadcast()
  }
}

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
  struct State {
    var isBroadcasting: Bool
    var isListening: Bool
    var stationName: String?
  }

  enum UnexpectedError {
    case apiDisconnected
    case apiError(String)
    case remoteDisconnected
    case remoteError(String)
  }

  private var api: RadioAPIClient
  private var remote: MusicRemote
  private let disposeBag = DisposeBag()

  private let stateRelay = BehaviorRelay<State>(
    value: State(isBroadcasting: false, isListening: false, stationName: nil)
  )
  var state: Observable<State> {
    return stateRelay.asObservable()
  }
  private let errorRelay = PublishRelay<UnexpectedError>()
  var errors: Observable<UnexpectedError> {
    return errorRelay.asObservable()
  }

  init(api: RadioAPIClient, remote: MusicRemote) {
    self.api = api
    self.remote = remote
  }

  private var playerUpdatesSubscription: Disposable?
  private var broadcasterSubscription: Disposable?
  private var tuneInSubscription: Disposable?

  func startBroadcast(station: RadioStation) -> Completable {
    return remote
      .connect()
      .andThen(api.startBroadcasting(station: station))
      .do(onCompleted: { [weak self] in
        BackgroundManager.shared.playSilence()
        self?.stateRelay.accept(State(isBroadcasting: true,
                                      isListening: false,
                                      stationName: station.name))
        self?.startBroadcastingPlayerUpdates()
        self?.startMonitoringBroadcasterUpdates()
      })
  }

  /// Starts subscribing to player updates from the remote and forwards them to the api.
  private func startBroadcastingPlayerUpdates() {
    guard playerUpdatesSubscription == nil else { return }
    playerUpdatesSubscription = remote.getPlayerUpdates()
      .subscribe(onNext: { [weak self] playerState in
        guard let self = self else { return }
        // Pass along player updates to api client
        self.api.broadcastPlayerStateChange(newState: playerState)
          .retry(2)
          .subscribe(onError: { error in
            // TODO: Might be disconnected error, handle it
            self.errorRelay.accept(.apiError(error.localizedDescription))
            self.stopBroadcastingPlayerUpdates()
          })
          .disposed(by: self.disposeBag)
        }, onError: { [weak self] error in
          // This is when the remote disconnects unvoluntarily
          guard let self = self else { return }
          // End broadcast
          self.endBroadcast()
            .retry(2)
            .subscribe(onError: { error in
              // TODO: Might be disconnected error, handle it
              self.errorRelay.accept(.apiError(error.localizedDescription))
            })
            .disposed(by: self.disposeBag)

          self.errorRelay.accept(.remoteDisconnected)
        }, onDisposed: { [weak self] in
          self?.stateRelay.accept(State(isBroadcasting: false,
                                        isListening: false,
                                        stationName: nil))
          BackgroundManager.shared.stopSilence()
      })
    disposeBag.insert(playerUpdatesSubscription!)
  }

  private func startMonitoringBroadcasterUpdates() {
    guard broadcasterSubscription == nil else { return }
    broadcasterSubscription = api.getBroadcasterEvents()
      .subscribe(onNext: { _ in
        // TODO: Do something with these updates
        }, onError: { [weak self] error in
          // This is when the api disconnects involuntarily
          self?.stopBroadcastingPlayerUpdates()
          self?.errorRelay.accept(.apiDisconnected)
        })
    disposeBag.insert(broadcasterSubscription!)
  }

  private func stopBroadcastingPlayerUpdates() {
    guard let subscription = playerUpdatesSubscription else { return }
    subscription.dispose()
    playerUpdatesSubscription = nil
  }

  private func stopMonitoringBroadcasterUpdates() {
    guard let subscription = broadcasterSubscription else { return }
    subscription.dispose()
    broadcasterSubscription = nil
  }

  func endBroadcast() -> Completable {
    return api.endBroadcasting()
      .do(onCompleted: { [weak self] in
        self?.stopBroadcastingPlayerUpdates()
        self?.stopMonitoringBroadcasterUpdates()
      })
  }

  func joinBroadcast(stationName: String) -> Completable {
    return remote
      .connect()
      .andThen(api.joinBroadcast(stationName: stationName))
      .do(onCompleted: { [weak self] in
        BackgroundManager.shared.playSilence()
        self?.stateRelay.accept(State(isBroadcasting: false,
                                      isListening: true,
                                      stationName: stationName))
        self?.startUpdatingPlayerFromBroadcast()
        self?.startMonitoringPlayerChanges()
      })
  }

  /// Starts subscribing to player updates from the api and forwards them to the remote.
  private func startUpdatingPlayerFromBroadcast() {
    guard tuneInSubscription == nil else { return }
    tuneInSubscription = api.getListenerEvents()
      .subscribe(onNext: { [weak self] event in
        guard let self = self else { return }
        guard case .playerStateChanged(let playerState) = event else { return }
        // Pass along player change to remote
        self.remote.updatePlayerToState(newState: playerState)
          .retry(2)
          .subscribe(onError: { error in
            // TODO: Might be disconnected error, handle it
            self.errorRelay.accept(.remoteError(error.localizedDescription))
            self.stopUpdatingPlayerFromBroadcast()
          })
          .disposed(by: self.disposeBag)
        }, onError: { [weak self] error in
          // This is when the api disconnects involuntarily
          guard let self = self else { return }
          self.stopMonitoringPlayerChanges()
          self.errorRelay.accept(.apiDisconnected)
        }, onDisposed: { [weak self] in
          self?.stateRelay.accept(State(isBroadcasting: false,
                                        isListening: false,
                                        stationName: nil))
        BackgroundManager.shared.stopSilence()
      })
    disposeBag.insert(tuneInSubscription!)
  }

  private func startMonitoringPlayerChanges() {
    guard playerUpdatesSubscription == nil else { return }
    playerUpdatesSubscription = remote.getPlayerUpdates()
      .subscribe(onNext: { _ in
        // TODO: Leave broadcast if the update was initiated by us
      }, onError: { [weak self] error in
        // This is when the remote disconnects involuntarily
        self?.stopUpdatingPlayerFromBroadcast()
        self?.errorRelay.accept(.remoteDisconnected)
      })
    disposeBag.insert(playerUpdatesSubscription!)
  }

  private func stopUpdatingPlayerFromBroadcast() {
    guard let subscription = tuneInSubscription else { return }
    subscription.dispose()
    tuneInSubscription = nil
  }

  private func stopMonitoringPlayerChanges() {
    guard let subscription = playerUpdatesSubscription else { return }
    subscription.dispose()
    playerUpdatesSubscription = nil
  }

  func leaveBroadcast() -> Completable {
    return api.leaveBroadcast()
      .do(onCompleted: { [weak self] in
        self?.stopUpdatingPlayerFromBroadcast()
        self?.stopMonitoringPlayerChanges()
      })
  }
}

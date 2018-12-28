//
//  SpotifyManager.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-18.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import Foundation
import UIKit
import RxSwift
import RxCocoa

class SpotifyRemote: NSObject, MusicRemote {
  // MARK: - Spotify SDK and conf
  private let SpotifyClientID = "92856ab901c743489c9bfde3b024a13e"
  private let SpotifyRedirectURL = URL(string: "spotify-tunein://spotify-login-callback")!
  private lazy var configuration = SPTConfiguration(
    clientID: SpotifyClientID,
    redirectURL: SpotifyRedirectURL
  )
  private lazy var sessionManager: SPTSessionManager = {
    if let tokenSwapURL = URL(string: "https://spotify-tunein-tokenswap.herokuapp.com/api/token"),
      let tokenRefreshURL = URL(string: "https://spotify-tunein-tokenswap.herokuapp.com/api/refresh_token") {
      self.configuration.tokenSwapURL = tokenSwapURL
      self.configuration.tokenRefreshURL = tokenRefreshURL
      self.configuration.playURI = ""
    }
    let manager = SPTSessionManager(configuration: self.configuration, delegate: self)
    return manager
  }()
  private lazy var appRemote: SPTAppRemote = {
    let appRemote = SPTAppRemote(configuration: self.configuration, logLevel: .error)
    appRemote.delegate = self
    return appRemote
  }()
  var isConnected: Bool {
    return appRemote.isConnected
  }

  // MARK: - Properties
  private var authenticationRelay = PublishRelay<Event<Void>>()
  private var connectionRelay = PublishRelay<Event<Void>>()
  private var playerUpdatesRelay = PublishRelay<Event<PlayerState>>()

  private var currentState: PlayerState?
  private var currentAlbumArt: SPTAppRemoteImageRepresentable?

  // MARK: - Authentication
  /// Tries to authenticate using the Spotify app
  private func authenticate() -> Completable {
    return Completable.deferred({ [weak self] in
      guard let self = self else { return Completable.error("Error") }
      self.sessionManager.initiateSession(with: [.appRemoteControl], options: .default)
      return self.authenticationRelay.dematerialize().take(1).ignoreElements()
    })
  }

  /// Tries to connect to the Spotify app remote.
  /// Will fail if not having authenticated previously.
  private func connectToRemote() -> Completable {
    return Completable.deferred({ [weak self] in
      guard let self = self else { return Completable.error("Error") }
      if self.appRemote.isConnected {
        // Skip authentication
        self.authenticationRelay.accept(.completed)
        return Completable.empty()
      } else {
        self.appRemote.connect()
      }
      return self.connectionRelay.dematerialize().take(1).ignoreElements()
    })
  }

  // MARK: -
  /// Connects to the Spotify app remote.
  /// Authenticates if needed.
  func connect() -> Completable {
    return connectToRemote()
      .catchError({ [weak self] _ in
        guard let self = self else { return Completable.error("Error") }
        return self.authenticate()
      })
      .andThen(connectToRemote())
  }

  func subscribeToPlayerUpdates() -> Completable {
    return Completable.create { [weak self] src in
      guard let playerAPI = self?.appRemote.playerAPI else {
        src(.error("Not connected to Spotify"))
        return Disposables.create()
      }
      playerAPI.subscribe(toPlayerState: { result, error in
        if let error = error {
          src(.error(error))
        } else {
          src(.completed)
        }
      })
      return Disposables.create()
    }
  }

  func getCurrentAlbumArtwork(size: CGSize) -> Single<UIImage> {
    return Single.create(subscribe: { [weak self] src in
      if let imageAPI = self?.appRemote.imageAPI {
        if let albumArt = self?.currentAlbumArt {
          imageAPI.fetchImage(forItem: albumArt, with: size) { result, error in
            if let error = error {
              src(.error(error))
            } else {
              src(.success(result as! UIImage))
            }
          }
        } else {
          src(.success(UIImage()))
        }
      } else {
        src(.error("Not connected to Spotify"))
      }
      return Disposables.create()
    })
  }

  /// Gets updates to the Spotify player.
  /// Will fail if not connected to remote before calling.
  /// Fails if remote disconnects
  func getPlayerUpdates() -> Observable<PlayerState> {
    return Observable.deferred({ [weak self] in
      guard let self = self else { return Observable.error("Error") }
      return self.subscribeToPlayerUpdates()
        .andThen(self.playerUpdatesRelay
          .dematerialize()
          .asObservable()
          .debounce(0.5, scheduler: MainScheduler.instance)
      )
    })
  }

  func updatePlayerToState(newState: PlayerState) -> Completable {
    return Completable.deferred({ [weak self] in
      guard let self = self else { return Completable.error("Error") }
      guard let playerAPI = self.appRemote.playerAPI else {
        return Completable.error("Not connected to Spotify")
      }
      let scrubPosition =
        newState.playbackPosition + ((Int(CACurrentMediaTime() * 1000)) - newState.timestamp)
      if let currentState = self.currentState {
        if newState.isPaused {
          if currentState.isPaused {
            return Completable.empty()
          } else {
            return self.pause(player: playerAPI)
          }
        } else {
          if currentState.isPaused {
            return self.play(trackURI: newState.trackURI, player: playerAPI)
              .andThen(self.scrub(to: scrubPosition, player: playerAPI))
          } else {
            if currentState.trackURI != newState.trackURI {
              // New track
              return self.play(trackURI: newState.trackURI, player: playerAPI)
                .andThen(self.scrub(to: scrubPosition, player: playerAPI))
            } else {
              // Same track
              return self.scrub(to: scrubPosition, player: playerAPI)
            }
          }
        }
      } else {
        // No current state
        if newState.isPaused {
          return self.pause(player: playerAPI)
        } else {
          return self.play(trackURI: newState.trackURI, player: playerAPI)
            .andThen(self.scrub(to: scrubPosition, player: playerAPI))
        }
      }
    })
  }

  private func play(trackURI: String, player: SPTAppRemotePlayerAPI) -> Completable {
    return Completable.create(subscribe: { src in
      player.play(trackURI) { result, error in
        if let error = error {
          src(.error(error))
        } else {
          src(.completed)
        }
      }
      return Disposables.create()
    })
  }

  private func scrub(to position: Int, player: SPTAppRemotePlayerAPI) -> Completable {
    return Completable.create(subscribe: { src in
      player.seek(toPosition: position) { result, error in
        if let error = error {
          src(.error(error))
        } else {
          src(.completed)
        }
      }
      return Disposables.create()
    })
  }

  private func pause(player: SPTAppRemotePlayerAPI) -> Completable {
    return Completable.create(subscribe: { src in
      player.pause() { result, error in
        if let error = error {
          src(.error(error))
        } else {
          src(.completed)
        }
      }
      return Disposables.create()
    })
  }

  // Auth callback, used when returning from Spotify authentication flow
  func returnFromAuth(_ application: UIApplication, open url: URL,
                      options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
    return sessionManager.application(application, open: url, options: options)
  }
}

// MARK: - Spotify SDK Session Manager Delegate
extension SpotifyRemote: SPTSessionManagerDelegate {
  internal func sessionManager(manager: SPTSessionManager,
                               didInitiate session: SPTSession) {
    appRemote.connectionParameters.accessToken = session.accessToken
    authenticationRelay.accept(.completed)
  }

  internal func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
    authenticationRelay.accept(.error(error))
  }

  internal func sessionManager(manager: SPTSessionManager, didRenew session: SPTSession) {
    authenticationRelay.accept(.completed)
  }
}

// MARK: - Spotify SDK App Remote Delegate
extension SpotifyRemote: SPTAppRemoteDelegate {
  internal func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
    self.appRemote.playerAPI?.delegate = self
    connectionRelay.accept(.completed)
  }

  internal func appRemote(_ appRemote: SPTAppRemote,
                 didFailConnectionAttemptWithError error: Error?) {
    connectionRelay.accept(.error(error ?? "Failed to connect to Spotify"))
  }

  internal func appRemote(_ appRemote: SPTAppRemote,
                          didDisconnectWithError error: Error?) {
    playerUpdatesRelay.accept(.error(error ?? "Spotify disconnected"))
  }
}

// MARK: - Spotify SDK App Remote Player State Delegate
extension SpotifyRemote: SPTAppRemotePlayerStateDelegate {
  internal func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
    currentState = playerState.state
    currentAlbumArt = playerState.track
    playerUpdatesRelay.accept(.next(playerState.state))
  }
}

// MARK: -
extension SPTAppRemotePlayerState {
  var state: PlayerState {
    return PlayerState(timestamp: Int(CACurrentMediaTime() * 1000),
                       isPaused: self.isPaused,
                       trackName: self.track.name,
                       trackArtist: self.track.artist.name,
                       trackURI: self.track.uri,
                       playbackPosition: self.playbackPosition)
  }
}

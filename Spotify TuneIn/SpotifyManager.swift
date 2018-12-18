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

class SpotifyManager:
  NSObject,
  SPTSessionManagerDelegate,
  SPTAppRemoteDelegate,
  SPTAppRemotePlayerStateDelegate
{
  enum Result {
    case success
    case error(Error)
  }

  // MARK: - Properties
  private let SpotifyClientID = "92856ab901c743489c9bfde3b024a13e"
  private let SpotifyRedirectURL = URL(string: "spotify-tunein://spotify-login-callback")!
  private lazy var configuration = SPTConfiguration(
    clientID: SpotifyClientID,
    redirectURL: SpotifyRedirectURL
  )

  let authenticationSubject = PublishSubject<Result>()
  let remoteConnectionSubject = PublishSubject<Result>()
  let playerUpdatesSubject = PublishSubject<SPTAppRemotePlayerState>()
  static var shared = SpotifyManager()
  var hasValidSession: Bool {
    guard let session = sessionManager.session else { return false }
    return session.expirationDate > Date()
  }

  private override init() {}

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
  lazy var appRemote: SPTAppRemote = {
    self.configuration.playURI = ""
    let appRemote = SPTAppRemote(configuration: self.configuration, logLevel: .none)
    appRemote.delegate = self
    return appRemote
  }()

  private func authenticate() -> Completable {
    return Completable.empty()
      .do(onError: nil, onCompleted: { [weak self] in
        self?.sessionManager.initiateSession(with: [.appRemoteControl], options: .default)
      })
      .andThen(self.authenticationSubject.take(1).single { result in
        if case .error(let error) = result {
          throw error
        }
        return true
      }).ignoreElements()
  }

  private func connectToRemote() -> Completable {
    return Completable.empty()
      .do(onError: nil, onCompleted: { [weak self] in
        if (self?.appRemote.isConnected ?? false) {
          self?.remoteConnectionSubject.onNext(.success)
        } else {
          self?.appRemote.connect()
        }
      })
      .andThen(self.remoteConnectionSubject.take(1).single { result in
        if case .error(let error) = result {
          throw error
        }
        return true
      }).ignoreElements()
  }

  private func authenticateAndConnectToRemote() -> Completable {
    return connectToRemote()
      .catchError({ _ in
        return self.authenticate()
      })
      .andThen(connectToRemote())
  }

  func connect() -> Observable<SPTAppRemotePlayerState> {
    return authenticateAndConnectToRemote()
      .andThen(Completable.create { completable in
        // Register for player updates
        self.appRemote.playerAPI?.subscribe(toPlayerState: { (result, error) in
          if let error = error {
            completable(.error(error))
          } else {
            completable(.completed)
          }
        })
        return Disposables.create()
      })
      .andThen(playerUpdatesSubject.asObservable())
  }

  func returnFromAuth(_ application: UIApplication, open url: URL,
                      options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
    return sessionManager.application(application, open: url, options: options)
  }

  func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
    authenticationSubject.onNext(.success)
    appRemote.connectionParameters.accessToken = session.accessToken
  }

  func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
    authenticationSubject.onNext(.error(error))
  }

  func sessionManager(manager: SPTSessionManager, didRenew session: SPTSession) {
    authenticationSubject.onNext(.success)
  }

  func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
    playerUpdatesSubject.onNext(playerState)
  }

  func getPlayerUpdates() -> Observable<SPTAppRemotePlayerState> {
    return playerUpdatesSubject.asObservable()
  }

  func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
    remoteConnectionSubject.onNext(.success)
    self.appRemote.playerAPI?.delegate = self
  }

  func appRemote(_ appRemote: SPTAppRemote,
                 didFailConnectionAttemptWithError error: Error?) {
    remoteConnectionSubject.onNext(.error(error ?? "Failed to connect to Spotify"))
  }

  func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
    remoteConnectionSubject.onNext(.error(error ?? "Spotify disconnected"))
  }
}

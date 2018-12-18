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
  enum AuthencationResult {
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

  let authenticationSubject = PublishSubject<AuthencationResult>()
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
    let appRemote = SPTAppRemote(configuration: self.configuration, logLevel: .debug)
    appRemote.delegate = self
    return appRemote
  }()

  func authenticate() -> Completable {
    self.sessionManager.initiateSession(with: [.appRemoteControl], options: .default)
    return authenticationSubject.take(1).single { result in
      if case .error(let error) = result {
        throw error
      }
      return true
    }.ignoreElements()
  }

  func returnFromAuth(_ application: UIApplication, open url: URL,
                      options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
    return sessionManager.application(application, open: url, options: options)
  }

  func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
    authenticationSubject.onNext(.success)
    appRemote.connectionParameters.accessToken = session.accessToken
    DispatchQueue.main.async {
      self.appRemote.connect()
    }
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

  func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
    self.appRemote.playerAPI?.delegate = self
    self.appRemote.playerAPI?.subscribe(toPlayerState: { (result, error) in
      if let error = error {
        debugPrint(error.localizedDescription)
      }
    })
  }

  func appRemote(_ appRemote: SPTAppRemote,
                 didFailConnectionAttemptWithError error: Error?) {
  }

  func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
  }
}

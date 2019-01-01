//
//  AppDelegate.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-14.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  lazy var spotifyRemote = SpotifyRemote()
  lazy var radioCoordinator: RadioCoordinator = {
    let socket = SocketIOProvider(url: "http://192.168.0.99:3000", namespace: "/radio")
    let api = RadioAPIClient(socket: socket)
    return RadioCoordinator(api: api, remote: spotifyRemote)
  }()

  func application( _ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    if ProcessInfo.processInfo.environment["XCInjectBundleInto"] != nil {
      // Unit test, bail out
      return false
    }
    return true
  }

  func application(_ app: UIApplication, open url: URL,
                   options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    return spotifyRemote.returnFromAuth(app, open: url, options: options)
  }
}


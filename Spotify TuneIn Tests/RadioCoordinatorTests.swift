//
//  RadioCoordinatorTests.swift
//  Spotify TuneIn Tests
//
//  Created by Jonathan Berglind on 2018-12-21.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import XCTest
import RxSwift
import RxBlocking

class RadioCoordinatorTests: XCTestCase {
  var socket: MockSocketProvider!
  var remote: MockMusicRemote!
  var coordinator: RadioCoordinator!
  var disposeBag = DisposeBag()

  override func setUp() {
    socket = MockSocketProvider()
    let api = RadioAPIClient(socket: socket)
    remote = MockMusicRemote()
    coordinator = RadioCoordinator(api: api, remote: remote)
  }

  var examplePlayerState = PlayerState(timestamp: 0,
                                       isPaused: true,
                                       trackName: nil,
                                       trackArtist: nil,
                                       trackURI: "",
                                       playbackPosition: 1)

  func startBroadcast() throws {
    _ = try coordinator.startBroadcast(station: RadioStation(name: "station", coordinate: nil))
      .toBlocking(timeout: 1.0)
      .last()
  }

  func endBroadcast() throws {
    _ = try coordinator.endBroadcast()
      .toBlocking(timeout: 1.0)
      .last()
  }

  func joinBroadcast() throws {
    socket.mockAckResponderData(
      for: RadioAPIClient.OutgoingEvent.joinBroadcast.rawValue,
      data: examplePlayerState.socketRepresentation()
    )
    _ = try coordinator.joinBroadcast(stationName: "station")
      .toBlocking(timeout: 1.0)
      .last()
  }

  func leaveBroadcast() throws {
    _ = try coordinator.leaveBroadcast()
      .toBlocking(timeout: 1.0)
      .last()
  }

  func failOnError() {
    coordinator.errors.emit(onNext: { _ in
      XCTFail()
    }).disposed(by: disposeBag)
  }

  func testBroadcastHappyPath() throws {
    failOnError()
    try startBroadcast()
    remote.mockPlayerUpdateEvent(playerState: examplePlayerState)
    remote.mockPlayerUpdateEvent(playerState: examplePlayerState)
    try endBroadcast()
    XCTAssertEqual(
      socket.emittedEvents,
      [RadioAPIClient.OutgoingEvent.startBroadcast,
       RadioAPIClient.OutgoingEvent.updatePlayerState,
       RadioAPIClient.OutgoingEvent.updatePlayerState,
       RadioAPIClient.OutgoingEvent.endBroadcast].map({ $0.rawValue })
    )
  }

  func testTuneInHappyPath() throws {
    failOnError()
    try joinBroadcast()
    socket.mockIncomingEvent(RadioAPIClient.IncomingEvent.playerStateUpdated.rawValue,
                             data: examplePlayerState.socketRepresentation())
    socket.mockIncomingEvent(RadioAPIClient.IncomingEvent.playerStateUpdated.rawValue,
                             data: examplePlayerState.socketRepresentation())
    try leaveBroadcast()
    XCTAssertEqual(
      socket.emittedEvents,
      [RadioAPIClient.OutgoingEvent.joinBroadcast,
       RadioAPIClient.OutgoingEvent.leaveBroadcast].map({ $0.rawValue })
    )
    XCTAssertEqual(
      remote.playerStateUpdates,
      [examplePlayerState,
       examplePlayerState,
       examplePlayerState]
    )
  }

  func testBroadcastWhenBroadcasting() throws {
    failOnError()
    try startBroadcast()
    try startBroadcast()
  }

  func testTuneInWhenTunedIn() throws {
    failOnError()
    try joinBroadcast()
    try joinBroadcast()
  }

  func testTuneInWhenBroadcasting() throws {
    failOnError()
    try startBroadcast()
    try joinBroadcast()
    XCTAssertEqual(
      socket.emittedEvents,
      [RadioAPIClient.OutgoingEvent.startBroadcast,
       RadioAPIClient.OutgoingEvent.joinBroadcast].map({ $0.rawValue })
    )
  }

  func testBroadcastWhenTunedIn() throws {
    failOnError()
    try joinBroadcast()
    try startBroadcast()
    XCTAssertEqual(
      socket.emittedEvents,
      [RadioAPIClient.OutgoingEvent.joinBroadcast,
       RadioAPIClient.OutgoingEvent.startBroadcast,
       RadioAPIClient.OutgoingEvent.updatePlayerState].map({ $0.rawValue })
    )
  }

  func testBroadcastWhenDisconnectedFromApi () {
    socket.disconnectWithError()
    XCTAssertThrowsError(try startBroadcast())
  }

  func testBroadcastWhenDisconnectedFromRemote () {
    failOnError()
    remote.allowConnect = false
    XCTAssertThrowsError(try startBroadcast())
  }

  func testTuneInWhenDisconnectedFromApi () {
    socket.disconnectWithError()
    XCTAssertThrowsError(try joinBroadcast())
  }

  func testTuneInWhenDisconnectedFromRemote () {
    failOnError()
    remote.allowConnect = false
    XCTAssertThrowsError(try joinBroadcast())
  }

  func testApiDisconnectWhileBroadcasting() throws {
    try startBroadcast()
    let async = XCTestExpectation()
    coordinator.errors.emit(onNext: { error in
      if case .apiDisconnected = error {}
      else { XCTFail() }
      async.fulfill()
    }).disposed(by: disposeBag)
    socket.disconnectWithError()
    wait(for: [async], timeout: 1.0)
  }

  func testRemoteDisconnectWhileBroadcasting() throws {
    try startBroadcast()
    let async = XCTestExpectation()
    coordinator.errors.emit(onNext: { error in
      if case .remoteDisconnected = error {}
      else { XCTFail() }
      async.fulfill()
    }).disposed(by: disposeBag)
    remote.mockDisconnect()
    wait(for: [async], timeout: 1.0)
  }

  func testApiDisconnectWhileTunedIn() throws {
    try joinBroadcast()
    let async = XCTestExpectation()
    coordinator.errors.emit(onNext: { error in
      if case .apiDisconnected = error {}
      else { XCTFail() }
      async.fulfill()
    }).disposed(by: disposeBag)
    socket.disconnectWithError()
    wait(for: [async], timeout: 1.0)
  }

  func testRemoteDisconnectWhileTunedIn() throws {
    try joinBroadcast()
    let async = XCTestExpectation()
    coordinator.errors.emit(onNext: { error in
      if case .remoteDisconnected = error {}
      else { XCTFail() }
      async.fulfill()
    }).disposed(by: disposeBag)
    remote.mockDisconnect()
    wait(for: [async], timeout: 1.0)
  }
}

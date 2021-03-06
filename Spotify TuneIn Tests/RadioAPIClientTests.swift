//
//  RadioAPIClientTests.swift
//  Spotify TuneIn Tests
//
//  Created by Jonathan Berglind on 2018-12-20.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import XCTest
import RxSwift
import RxBlocking

class RadioAPIClientTests: XCTestCase {
  var socketProvider: MockSocketProvider!
  var apiClient: RadioAPIClient!
  var disposeBag = DisposeBag()

  override func setUp() {
    socketProvider = MockSocketProvider()
    apiClient = RadioAPIClient(socket: socketProvider)
  }

  var examplePlayerState = PlayerState(timestamp: 0,
                                       isPaused: true,
                                       trackName: nil,
                                       trackArtist: nil,
                                       trackURI: "",
                                       playbackPosition: 1)

  func startBroadcasting() throws {
    _ = try apiClient.startBroadcasting(station: RadioStation(name: "station", coordinate: nil))
      .toBlocking(timeout: 1.0)
      .last()
  }

  func endBroadcasting() throws {
    _ = try apiClient.endBroadcasting()
      .toBlocking(timeout: 1.0)
      .last()
  }

  func joinBroadcast() throws {
    socketProvider.mockAckResponderData(
      for: RadioAPIClient.OutgoingEvent.joinBroadcast.rawValue,
      data: examplePlayerState.socketRepresentation()
    )
    _ = try apiClient.joinBroadcast(stationName: "station")
      .toBlocking(timeout: 1.0)
      .last()
  }

  func leaveBroadcast() throws {
    _ = try apiClient.leaveBroadcast()
      .toBlocking(timeout: 1.0)
      .last()
  }

  func testDisconnectEndsBroadcasting() throws {
    try startBroadcasting()
    XCTAssert(apiClient.isBroadcasting == true)
    socketProvider.disconnectWithError()
    XCTAssert(apiClient.isBroadcasting == false)
  }

  // MARK: - startBroadcasting
  func testStartBroadcastingWithoutConnectionFails() throws {
    socketProvider.disconnectWithError()
    XCTAssertThrowsError(
      try apiClient.startBroadcasting(station: RadioStation(name: "station", coordinate: nil))
        .toBlocking(timeout: 1.0)
        .last()) { error in
          // Assure not timeout error
          XCTAssertNil(error as? RxError)
    }
    XCTAssert(apiClient.isBroadcasting == false)

    // Event not emitted
    let event = socketProvider.emittedEvents.last
    XCTAssert(event != RadioAPIClient.OutgoingEvent.startBroadcast.rawValue)
  }

  func testStartBroadcasting() throws {
    try startBroadcasting()
    XCTAssert(apiClient.isBroadcasting == true)

    // Event emitted
    let event = socketProvider.emittedEvents.last
    XCTAssert(event == RadioAPIClient.OutgoingEvent.startBroadcast.rawValue)
  }

  // MARK: - endBroadcasting
  func testEndBroadcastingWhileNotBroadcasting() throws {
    XCTAssert(apiClient.isBroadcasting == false)
    try endBroadcasting()
    XCTAssert(apiClient.isBroadcasting == false)
  }

  func testEndBroadcastingWhileBroadcasting() throws {
    try startBroadcasting()
    XCTAssert(apiClient.isBroadcasting == true)
    try endBroadcasting()
    XCTAssert(apiClient.isBroadcasting == false)

    // Event emitted
    let event = socketProvider.emittedEvents.last
    XCTAssert(event == RadioAPIClient.OutgoingEvent.endBroadcast.rawValue)
  }

  // MARK: - getBroadcasterEvents
  func testGetBroadcasterEventsWhenBroadcasting() throws {
    try startBroadcasting()
    XCTAssert(apiClient.isBroadcasting == true)

    let async = XCTestExpectation()
    apiClient.broadcasterEvents
      .emit(onNext: { _ in
        async.fulfill()
      }).disposed(by: disposeBag)
    // Send event which should appear in subscribe
    socketProvider.mockIncomingEvent(
      RadioAPIClient.IncomingEvent.listenerCountChanged.rawValue,
      data: 1
    )
    wait(for: [async], timeout: 1.0)
  }

  // MARK: - broadcastPlayerStateChange
  func testBroadcastPlayerStateDoesErrorsWhenNotBroadcasting() {
    XCTAssert(apiClient.isBroadcasting == false)
    XCTAssertThrowsError(
      try apiClient.broadcastPlayerStateChange(newState: examplePlayerState)
        .toBlocking(timeout: 1.0).last()
    ) { error in
      // Assure not timeout error
      XCTAssertNil(error as? RxError)
    }
  }

  func testBroadcastPlayerStateWhenBroadcastingEmitsUpdate() throws {
    _ = try startBroadcasting()
    XCTAssert(apiClient.isBroadcasting == true)
    _ = try apiClient.broadcastPlayerStateChange(newState: examplePlayerState)
      .toBlocking(timeout: 1.0).last()
    let event = socketProvider.emittedEvents.last
    XCTAssertNotNil(event)
    XCTAssert(event! == RadioAPIClient.OutgoingEvent.updatePlayerState.rawValue)
  }

  // MARK: - joinBroadcast
  func testJoinBroadcastWithoutConnectionFails() throws {
    socketProvider.disconnectWithError()
    XCTAssertThrowsError(
      try apiClient.joinBroadcast(stationName: "station")
        .toBlocking(timeout: 1.0)
        .last()) { error in
          // Assure not timeout error
          XCTAssertNil(error as? RxError)
    }
    XCTAssert(apiClient.isListening == false)

    // Event not emitted
    let event = socketProvider.emittedEvents.last
    XCTAssert(event != RadioAPIClient.OutgoingEvent.joinBroadcast.rawValue)
  }

  func testJoinBroadcast() throws {
    try joinBroadcast()
    XCTAssert(apiClient.isListening == true)

    // Event emitted
    let event = socketProvider.emittedEvents.last
    XCTAssert(event == RadioAPIClient.OutgoingEvent.joinBroadcast.rawValue)
  }

  // MARK: - leaveBroadcast
  func testLeaveBroadcastWhileNotListening() throws {
    XCTAssert(apiClient.isListening == false)
    try leaveBroadcast()
    XCTAssert(apiClient.isListening == false)
  }

  func testLeaveBroadcastWhileListening() throws {
    try joinBroadcast()
    XCTAssert(apiClient.isListening == true)
    try leaveBroadcast()
    XCTAssert(apiClient.isListening == false)

    // Event emitted
    let event = socketProvider.emittedEvents.last
    XCTAssert(event == RadioAPIClient.OutgoingEvent.leaveBroadcast.rawValue)
  }

  // MARK: - getListenerEvents
  func testGetListenerEventsWhenListening() throws {
    try joinBroadcast()
    XCTAssert(apiClient.isListening == true)

    let async = XCTestExpectation()
    apiClient.listenerEvents
      .emit(onNext: { _ in
        async.fulfill()
      }).disposed(by: disposeBag)
    // Send event which should appear in subscribe
    socketProvider.mockIncomingEvent(
      RadioAPIClient.IncomingEvent.playerStateUpdated.rawValue,
      data: examplePlayerState.socketRepresentation()
    )
    wait(for: [async], timeout: 1.0)
  }
}

private extension RadioAPIClient {
  var isBroadcasting: Bool {
    return try! state.toBlocking().first()!.isBroadcasting
  }
  var isListening: Bool {
    return try! state.toBlocking().first()!.isListenening
  }
}

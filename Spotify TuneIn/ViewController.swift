//
//  ViewController.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-14.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import UIKit
import CoreLocation
import RxSwift
import RxCocoa

class ViewController: UIViewController {
  struct State {
    var isConnected = false
    var albumArt: UIImage?
    var playerState: PlayerState?
    var radioState = RadioCoordinator.State(isBroadcasting: false,
                                            isListening: false,
                                            stationName: nil)
  }

  // MARK: - Outlets
  @IBOutlet weak var notConnectedLabel: UILabel!
  @IBOutlet weak var listeningOrBroadcastingLabel: UILabel!
  @IBOutlet weak var stationNameLabel: UILabel!
  @IBOutlet weak var beamLeftImageView: UIImageView!
  @IBOutlet weak var artworkImageView: UIImageView!
  @IBOutlet weak var beamRightImageView: UIImageView!
  @IBOutlet weak var trackNameLabel: UILabel!
  @IBOutlet weak var trackArtistLabel: UILabel!
  @IBOutlet weak var actionButtonDescriptionLabel: UILabel!
  @IBOutlet weak var actionButton: RoundedButton!

  // MARK: - Properties
  private lazy var remote: SpotifyRemote = {
    let appDelegate = UIApplication.shared.delegate as! AppDelegate
    return appDelegate.spotifyRemote
  }()
  private lazy var radioCoordinator: RadioCoordinator = {
    let appDelegate = UIApplication.shared.delegate as! AppDelegate
    return appDelegate.radioCoordinator
  }()
  private var playerUpdatesSubscription: Disposable?
  private let disposeBag = DisposeBag()
  private var state = State() {
    didSet { updateUI() }
  }
  private var locationService = LocationService()

  // MARK: - Lifecycle
  override func viewDidLoad() {
    super.viewDidLoad()

    updateUI()
    radioCoordinator.stateStream.subscribe(onNext: { [weak self] state in
      self?.state.radioState = state
    }).disposed(by: disposeBag)
    radioCoordinator.errorStream.subscribe(onNext: { error in
      switch error {
      case .apiDisconnected:
        self.showErrorAlert(error: "The server disconnected")
      case .apiError(let str):
        self.showErrorAlert(error: str)
      case .remoteDisconnected:
        self.showErrorAlert(error: "Spotify disconnected")
      case .remoteError(let str):
        self.showErrorAlert(error: str)
      }
    }).disposed(by: disposeBag)
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    return .lightContent
  }

  func updateUI() {
    notConnectedLabel.isHidden = state.isConnected
    listeningOrBroadcastingLabel.isHidden = !state.isConnected
    actionButtonDescriptionLabel.isHidden = state.isConnected
    trackNameLabel.isHidden = !state.isConnected
    trackArtistLabel.isHidden = !state.isConnected
    artworkImageView.image = state.isConnected ? state.albumArt : nil
    if !state.isConnected {
      actionButton.setTitle("CONNECT TO SPOTIFY", for: .normal)
      stationNameLabel.text = " "
    } else if state.radioState.isBroadcasting {
      actionButton.setTitle("END BROADCAST", for: .normal)
      listeningOrBroadcastingLabel.text = "YOU ARE BROADCASTING TO"
      stationNameLabel.text = state.radioState.stationName?.uppercased()
    } else if state.radioState.isListening {
      actionButton.setTitle("LEAVE BROADCAST", for: .normal)
      listeningOrBroadcastingLabel.text = "YOU ARE TUNED IN TO"
      stationNameLabel.text = state.radioState.stationName?.uppercased()
    } else {
      actionButton.setTitle("START BROADCASTING", for: .normal)
      listeningOrBroadcastingLabel.text = "LISTENING LOCALLY"
      stationNameLabel.text = " "
    }
    let showBeams = state.radioState.isBroadcasting || state.radioState.isListening
    beamLeftImageView.image = showBeams ? UIImage(named: "BeamLeft") : nil
    beamRightImageView.image = showBeams ? UIImage(named: "BeamRight") : nil
    trackNameLabel.text = state.playerState?.trackName
    trackArtistLabel.text = state.playerState?.trackArtist
  }

  /// Displays an error alert popup
  private func showErrorAlert(error: Error) {
    let msg = error as? String ?? error.localizedDescription
    let alert = UIAlertController(title: "Error",
                                  message: msg,
                                  preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .cancel) { alert in
      self.dismiss(animated: true)
    })
    present(alert, animated: true)
  }

  private func startMonitoringPlayerUpdates() {
    playerUpdatesSubscription = remote.getPlayerUpdates()
      .subscribe(onNext: { [weak self] state in
        if state.trackURI != self?.state.playerState?.trackURI {
          self?.fetchAlbumArt()
        }
        self?.state.playerState = state
      }, onError: { [weak self] error in
        self?.state.isConnected = false
      })
    disposeBag.insert(playerUpdatesSubscription!)
  }

  private func fetchAlbumArt() {
    remote.getCurrentAlbumArtwork(size: artworkImageView.frame.size.scaled)
      .retry(2)
      .subscribe(onSuccess: { [weak self] artwork in
        self?.state.albumArt = artwork
      }, onError: { [weak self] error in
        self?.state.albumArt = nil
      }).disposed(by: disposeBag)
  }

  private func connectToSpotify() {
    remote.connect()
      .subscribe(onCompleted: { [weak self] in
        self?.state.isConnected = true
        self?.startMonitoringPlayerUpdates()
        }, onError: {
          self.showErrorAlert(error: $0)
      }).disposed(by: disposeBag)
  }

  private func startBroadcasting() {
    let alert = UIAlertController(title: nil,
                                  message: "What should your radio station be called?",
                                  preferredStyle: .alert)
    var field: UITextField?
    alert.addTextField(configurationHandler: {(textField: UITextField!) in
      field = textField
    })
    alert.addAction(UIAlertAction(title: "Start broadcasting",
                                  style: .default, handler:
      { [weak self] action in
        guard let self = self else { return }
        guard let text = field?.text, !text.isEmpty else { return }
        self.locationService.getLocation()
          .timeout(3.0, scheduler: MainScheduler.instance)
          .map({ RadioStation(name: text, coordinate: $0.coord )})
          .catchErrorJustReturn(RadioStation(name: text, coordinate: nil))
          .flatMapCompletable({ station in
            return self.radioCoordinator.startBroadcast(station: station)
          })
          .subscribe(onError: { self.showErrorAlert(error: $0) })
          .disposed(by: self.disposeBag)
    }))
    self.present(alert, animated: true, completion: nil)
  }

  private func endBroadcasting() {
    radioCoordinator.endBroadcast()
      .subscribe(onError: { self.showErrorAlert(error: $0) })
      .disposed(by: disposeBag)
  }

  private func leaveBroadcast() {
    radioCoordinator.leaveBroadcast()
      .subscribe(onError: { self.showErrorAlert(error: $0) })
      .disposed(by: disposeBag)
  }

  @IBAction func actionButtonTapped(_ sender: Any) {
    if !state.isConnected {
      connectToSpotify()
    } else if state.radioState.isBroadcasting {
      endBroadcasting()
    } else if state.radioState.isListening {
      leaveBroadcast()
    } else {
      startBroadcasting()
    }
  }
}

extension CGSize {
  var scaled: CGSize {
    let scale = UIScreen.main.scale
    return CGSize(width: self.width * scale,
                  height: self.height * scale)
  }
}

extension CLLocation {
  var coord: Coordinate {
    return Coordinate(lat: self.coordinate.latitude, lng: self.coordinate.longitude)
  }
}



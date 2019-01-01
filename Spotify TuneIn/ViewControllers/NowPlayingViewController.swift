//
//  NowPlayingViewController.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-14.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import UIKit
import CoreLocation
import RxSwift
import RxCocoa
import RxSwiftExt

class NowPlayingViewController: UIViewController {
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
  private var locationService = LocationService()
  private let albumArt = BehaviorRelay<UIImage?>(value: nil)
  private let disposeBag = DisposeBag()

  // MARK: - Lifecycle
  override func viewDidLoad() {
    super.viewDidLoad()
    bindUI()
  }

  // MARK: - UIViewController
  override var preferredStatusBarStyle: UIStatusBarStyle {
    return .lightContent
  }

  // MARK: - UI
  /// Binds the UI components to react to changes in streams from model
  private func bindUI() {
    remote.isConnected
      .drive(onNext: { [unowned self] connected in
        self.notConnectedLabel.isHidden = connected
        self.listeningOrBroadcastingLabel.isHidden = !connected
        self.actionButtonDescriptionLabel.isHidden = connected
        self.trackNameLabel.isHidden = !connected
        self.trackArtistLabel.isHidden = !connected
      }).disposed(by: disposeBag)

    radioCoordinator.state
      .drive(onNext: { [unowned self] state in
        let showBeams = state.isBroadcasting || state.isListening
        self.beamLeftImageView.image = showBeams ? UIImage(named: "BeamLeft") : nil
        self.beamRightImageView.image = showBeams ? UIImage(named: "BeamRight") : nil
        if state.isBroadcasting {
          self.listeningOrBroadcastingLabel.text = "YOU ARE BROADCASTING TO"
        } else if state.isListening {
          self.listeningOrBroadcastingLabel.text = "YOU ARE TUNED IN TO"
        } else {
          self.listeningOrBroadcastingLabel.text = "YOU ARE LISTENING LOCALLY"
        }
      }).disposed(by: disposeBag)

    Driver.combineLatest(radioCoordinator.state, remote.isConnected)
      .drive(onNext: { [unowned self] (state, connected) in
        if !connected {
          self.actionButton.setTitle("CONNECT TO SPOTIFY", for: .normal)
          self.stationNameLabel.text = " "
        } else if state.isBroadcasting {
          self.actionButton.setTitle("END BROADCAST", for: .normal)
          self.stationNameLabel.text = state.stationName?.uppercased()
        } else if state.isListening {
          self.actionButton.setTitle("LEAVE BROADCAST", for: .normal)
          self.stationNameLabel.text = state.stationName?.uppercased()
        } else {
          self.actionButton.setTitle("START BROADCASTING", for: .normal)
          self.stationNameLabel.text = " "
        }
      }).disposed(by: disposeBag)

    Driver.combineLatest(remote.isConnected, albumArt.asDriver())
      .drive(onNext: { [unowned self] (connected, image) in
        self.artworkImageView.image = connected ? image : nil
      }).disposed(by: disposeBag)

    remote.playerState
      .drive(onNext: { [unowned self] state in
        self.trackNameLabel.text = state?.trackName
        self.trackArtistLabel.text = state?.trackArtist
      }).disposed(by: disposeBag)

    remote.playerState
      .scan((nil, nil), accumulator: { ($0.1, $1) }).skip(1)
      .drive(onNext: { [unowned self] (prev, current) in
        if prev?.trackURI != current?.trackURI {
          self.albumArt.accept(UIImage(named: "NoArtwork"))
          self.fetchAlbumArt()
        }
      }).disposed(by: disposeBag)

    actionButton.rx.tap.asDriver()
      .withLatestFrom(Driver.combineLatest(remote.isConnected, radioCoordinator.state))
      .drive(onNext: { [unowned self] (connected, state) in
        if !connected {
          self.connectToSpotify()
        } else if state.isBroadcasting {
          self.endBroadcasting()
        } else if state.isListening {
          self.leaveBroadcast()
        } else {
          self.startBroadcasting()
        }
      }).disposed(by: disposeBag)

    radioCoordinator.errors
      .emit(onNext: { [unowned self] error in
        switch error {
        case .apiDisconnected:
          self.showErrorAlert(error: "The server disconnected")
        case .remoteDisconnected:
          self.showErrorAlert(error: "Spotify disconnected")
        }
      }).disposed(by: disposeBag)
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

  // MARK: - Actions
  private func connectToSpotify() {
    remote.connect()
      .subscribe(onError: {
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

  // MARK: -
  private func fetchAlbumArt() {
    remote.getCurrentAlbumArtwork(size: artworkImageView.frame.size.scaled)
      .asObservable()
      .retry(.exponentialDelayed(maxCount: 3, initial: 1.0, multiplier: 1.0),
             scheduler: MainScheduler.instance)
      .asSingle()
      .subscribe(onSuccess: { [weak self] image in
        self?.albumArt.accept(image)
        }, onError: { [weak self] error in
          self?.albumArt.accept(UIImage(named: "NoArtwork"))
      }).disposed(by: disposeBag)
  }
}

extension CLLocation {
  var coord: Coordinate {
    return Coordinate(lat: self.coordinate.latitude, lng: self.coordinate.longitude)
  }
}

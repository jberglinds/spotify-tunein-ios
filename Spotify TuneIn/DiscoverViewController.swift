//
//  DiscoverViewController.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-26.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import UIKit
import MapKit
import RxSwift

class DiscoverViewController: UIViewController {
  // MARK: - Outlets
  @IBOutlet weak var mapView: MKMapView!

  // MARK: - Properties
  private lazy var radioCoordinator: RadioCoordinator = {
    let appDelegate = UIApplication.shared.delegate as! AppDelegate
    return appDelegate.radioCoordinator
  }()
  var disposeBag = DisposeBag()

  // MARK: - UIViewController
  override var preferredStatusBarStyle: UIStatusBarStyle {
    return .lightContent
  }

  // MARK: - Lifecycle
  override func viewDidLoad() {
    super.viewDidLoad()
    mapView.delegate = self
  }

  override func viewDidAppear(_ animated: Bool) {
    // Reload stations every time this view is visited
    fetchRadioStations()
      .subscribe(onSuccess: self.updateMapPinsToStations,
                 onError: self.showErrorAlert)
      .disposed(by: disposeBag)
  }

  // MARK: -
  private func fetchRadioStations() -> Single<[RadioStation]> {
    let req = URLRequest(url: URL(string: "http://192.168.0.99:3000/radio/stations")!)
    return URLSession.shared.rx.data(request: req)
      .asSingle()
      .map({ data -> [RadioStation] in
        let decoder = JSONDecoder()
        return try decoder.decode([RadioStation].self, from: data)
      })
      .observeOn(MainScheduler.instance)
  }

  /// Creates pins for radio stations and populates the map view with them
  private func updateMapPinsToStations(_ stations: [RadioStation]) {
    let annotations: [MKPointAnnotation] = stations
      .filter({
        // Remove the current station
        return $0.name != radioCoordinator.state.stationName
      })
      .compactMap({ station in
        guard let coordinate = station.coordinate else { return nil }
        let marker = MKPointAnnotation()
        marker.coordinate = coordinate.CLCoordinate
        marker.title = station.name
        return marker
      })
    mapView.removeAnnotations(mapView.annotations)
    mapView.addAnnotations(annotations)
  }

  /// Attempts to join the broadcast with the given name
  private func joinBroadcast(stationName: String) {
    let radioState = radioCoordinator.state
    if radioState.isBroadcasting && radioState.stationName == stationName {
      self.showErrorAlert(error: "You can't listen to your own station")
    } else {
      self.radioCoordinator.joinBroadcast(stationName: stationName)
        .subscribe(onCompleted: {
          // Go to first tab
          self.tabBarController?.selectedIndex = 0
        }, onError: { error in
          self.showErrorAlert(error: error)
        }).disposed(by: self.disposeBag)
    }
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
}

// MARK: - MKMapViewDelegate
extension DiscoverViewController: MKMapViewDelegate {
  // Sets up popup view with play button for markers
  func mapView(_ mapView: MKMapView,
               viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    if annotation is MKUserLocation { return nil }
    var view: MKMarkerAnnotationView
    if let dequeuedView = mapView.dequeueReusableAnnotationView(withIdentifier: "marker")
      as? MKMarkerAnnotationView {
      dequeuedView.annotation = annotation
      view = dequeuedView
    } else {
      view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "marker")
      view.canShowCallout = true
      view.markerTintColor = .black
      view.glyphImage = UIImage(named: "Radio")
      view.glyphTintColor = mapView.tintColor
      let image = UIImage(named: "PlayCircle")
      let button = UIButton(type: .custom)
      button.setImage(image, for: .normal)
      button.frame = CGRect(x: 0, y: 0,
                            width: image!.size.width, height: image!.size.height)
      view.rightCalloutAccessoryView = button
    }
    return view
  }

  // Called when the play button of a station is tapped
  func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
               calloutAccessoryControlTapped control: UIControl) {
    guard case let station?? = view.annotation?.title else { return }
    joinBroadcast(stationName: station)
  }
}

// MARK: - Coordinate+CLLocationCoordinate2D
extension Coordinate {
  var CLCoordinate: CLLocationCoordinate2D {
    return CLLocationCoordinate2D(latitude: self.lat, longitude: self.lng)
  }
}

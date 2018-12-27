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
import RxBlocking

class DiscoverViewController: UIViewController {
  // MARK: - Outlets
  @IBOutlet weak var mapView: MKMapView!

  // MARK: - Properties
  private lazy var radioCoordinator: RadioCoordinator = {
    let appDelegate = UIApplication.shared.delegate as! AppDelegate
    return appDelegate.radioCoordinator
  }()
  var disposeBag = DisposeBag()
  var radioStations = [RadioStation]() {
    didSet {
      let radioState = try? radioCoordinator.state.take(1).toBlocking().single()
      let annotations: [MKPointAnnotation] = radioStations
        .filter({ (station) -> Bool in
          return station.coordinate != nil
        })
        .filter({
          return $0.name != radioState?.stationName
        })
        .map({ station in
          let marker = MKPointAnnotation()
          marker.coordinate = station.coordinate!.CLCoordinate
          marker.title = station.name
          return marker
        })
      mapView.removeAnnotations(mapView.annotations)
      mapView.addAnnotations(annotations)
    }
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    return .lightContent
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    mapView.delegate = self
  }

  // MARK: - Lifecycle
  override func viewDidAppear(_ animated: Bool) {
    let req = URLRequest(url: URL(string: "http://192.168.0.99:3000/radio/stations")!)
    URLSession.shared.rx.data(request: req)
      .asSingle()
      .map({ data -> [RadioStation] in
        let decoder = JSONDecoder()
        return try decoder.decode([RadioStation].self, from: data)
      })
      .observeOn(MainScheduler.instance)
      .subscribe(onSuccess: { [weak self] stations in
        self?.radioStations = stations
      }, onError: { [weak self] error in
        self?.showErrorAlert(error: error.localizedDescription)
      }).disposed(by: disposeBag)
  }

  private func showErrorAlert(error: String) {
    let alert = UIAlertController(title: "Error",
                                  message: error,
                                  preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .cancel) { alert in
      self.dismiss(animated: true)
    })
    present(alert, animated: true)
  }
}

// MARK: - MKMapViewDelegate
extension DiscoverViewController: MKMapViewDelegate {
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
      button.frame = CGRect(x: 0, y: 0, width: image!.size.width, height: image!.size.height)
      view.rightCalloutAccessoryView = button
    }
    return view
  }

  func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
               calloutAccessoryControlTapped control: UIControl) {
    guard case let station?? = view.annotation?.title else { return }
    radioCoordinator.state
      .take(1)
      .subscribe(onNext: { [weak self] state in
        guard let self = self else { return }
        if state.isBroadcasting && state.stationName == station {
          self.showErrorAlert(error: "You can't listen to your own station")
        } else {
          self.radioCoordinator.joinBroadcast(stationName: station)
            .subscribe(onError: { error in
              self.showErrorAlert(error: "Failed to join broadcast")
            }).disposed(by: self.disposeBag)
        }
    }).disposed(by: disposeBag)
  }
}

extension Coordinate {
  var CLCoordinate: CLLocationCoordinate2D {
    return CLLocationCoordinate2D(latitude: self.lat, longitude: self.lng)
  }
}

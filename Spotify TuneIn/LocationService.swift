//
//  LocationService.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-26.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import Foundation
import CoreLocation
import RxSwift
import RxCocoa

class LocationService: NSObject {
  private lazy var locationManager: CLLocationManager = {
    let manager = CLLocationManager()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyKilometer 
    return manager
  }()

  private var authorizationRelay = PublishRelay<Event<Void>>()
  private var locationUpdatesRelay = PublishRelay<Event<CLLocation>>()

  private func authorize() -> Completable {
    return Completable.deferred({ [weak self] in
      guard let self = self else { return Completable.error("Error") }
      switch CLLocationManager.authorizationStatus() {
      case .notDetermined:
        self.locationManager.requestWhenInUseAuthorization()
        return self.authorizationRelay.take(1).dematerialize().ignoreElements()
      case .authorizedWhenInUse, .authorizedAlways:
        return Completable.empty()
      default:
        return Completable.error("Not allowed to use location services")
      }
    })
  }

  func getLocation() -> Single<CLLocation> {
    return authorize()
      .andThen(Single.deferred({ [weak self] in
        guard let self = self else { return Single.error("Error") }
        if !CLLocationManager.locationServicesEnabled() {
          return Single.error("Location services not enabled")
        }
        self.locationManager.requestLocation()
        return self.locationUpdatesRelay.take(1).dematerialize().asSingle()
      }))
  }
}

extension LocationService: CLLocationManagerDelegate {
  func locationManager(_ manager: CLLocationManager,
                       didChangeAuthorization status: CLAuthorizationStatus) {
    if status == .authorizedWhenInUse || status == .authorizedAlways {
      self.authorizationRelay.accept(.completed)
    } else {
      self.authorizationRelay.accept(.error("Not allowed to use location services"))
    }
  }

  func locationManager(_ manager: CLLocationManager,
                       didUpdateLocations locations: [CLLocation]) {
    self.locationUpdatesRelay.accept(.next(locations.last!))
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    self.locationUpdatesRelay.accept(.error(error))
  }
}

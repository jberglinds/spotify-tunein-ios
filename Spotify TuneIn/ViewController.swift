//
//  ViewController.swift
//  Spotify TuneIn
//
//  Created by Jonathan Berglind on 2018-12-14.
//  Copyright © 2018 Jonathan Berglind. All rights reserved.
//

import UIKit
import RxSwift

class ViewController: UIViewController {
  let spotifyManager = SpotifyManager.shared
  let disposeBag = DisposeBag()

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.

    spotifyManager.authenticate().subscribe(onCompleted: {
      print("success")
    }, onError: { error in
      print("fail", error)
    }).disposed(by: disposeBag)
  }
}


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
  lazy var radioCoordinator: RadioCoordinator = {
    let appDelegate = UIApplication.shared.delegate as! AppDelegate
    let socket = SocketIOProvider(url: "http://192.168.0.99:3000", namespace: "/radio")
    let api = RadioAPIClient(socket: socket)
    let remote = appDelegate.spotifyRemote
    return RadioCoordinator(api: api, remote: remote)
  }()
  let disposeBag = DisposeBag()

  @IBOutlet weak var label: UILabel!

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.
    radioCoordinator.state.subscribe(onNext: { [weak self] state in
      if state.isListening {
        self?.label.text = "Listening to: \(state.stationName ?? "")"
      } else if state.isBroadcasting {
        self?.label.text = "Broadcasting to: \(state.stationName ?? "")"
      } else {
        self?.label.text = ""
      }
    }).disposed(by: disposeBag)
  }

  @IBAction func broadcastPressed(_ sender: Any) {
    radioCoordinator.startBroadcast(stationName: "test")
      .subscribe(onCompleted: {
        print("success")
      }, onError: { error in
        print("error", error)
        if let  str = error as? String {
          self.showErrorAlert(error: str)
        }
      }).disposed(by: disposeBag)
  }

  @IBAction func subscribePressed(_ sender: Any) {
    radioCoordinator.joinBroadcast(stationName: "test")
      .subscribe(onCompleted: {
        print("success")
      }, onError: { error in
        print("error", error)
        if let str = error as? String {
          self.showErrorAlert(error: str)
        }
      }).disposed(by: disposeBag)
  }

  func showErrorAlert(error: String) {
    let alert = UIAlertController(title: "Error",
                                  message: error,
                                  preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .cancel) { alert in
      self.dismiss(animated: true)
    })
    present(alert, animated: true)
  }
}


# spotify-tunein-ios
This is the iOS app for Spotify TuneIn, an app for discovering music that other people really listens to.  
It allows the creation of a personal _radio station_ tied to your Spotify app, and tuning in to other people stations by listening in your local Spotify app.

When broadcasting, the app watches for player changes in the Spotify app and forwards them to a server. When listening, the app receives player updates for the station and updates the Spotify app.

## Getting started
### Prerequisites
- [Cocoapods (Package Manager)](https://cocoapods.org)
- [Spotify TuneIn Backend](https://github.com/jberglinds/spotify-tunein-backend)

### Installing
```sh
# Update Cocoapods specs
pod repo update

# Install dependencies
pod install

# Open the workspace in Xcode (Not .xcodeproj/ !)
open Spotify\ TuneIn.xcworkspace/
```

## Built with
- [Spotify iOS SDK](https://github.com/spotify/ios-sdk)
- [Socket.IO](https://github.com/socketio/socket.io-client-swift)
- [RxSwift](https://github.com/ReactiveX/RxSwift)

import SwiftUI

@main
struct CityOfShadowsApp: App {
    @StateObject var gameState = GameState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gameState)
                .preferredColorScheme(.dark)
        }
    }
}

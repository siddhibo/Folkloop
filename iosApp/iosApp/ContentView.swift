import SwiftUI
import Shared

struct ContentView: View {
    private let greeting = Greeting().greet()

    var body: some View {
        VStack(spacing: 12) {
            Text("GeoCircle")
                .font(.largeTitle.bold())
            Text(greeting)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

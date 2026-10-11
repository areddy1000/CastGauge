import SwiftUI

@main
struct CastGaugeApp: App {
    @State private var model = GaugeModel()

    var body: some Scene {
        MenuBarExtra {
            Text("CastGauge")
                .padding()
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

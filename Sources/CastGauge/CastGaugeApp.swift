import SwiftUI

@main
struct CastGaugeApp: App {
    @State private var model = GaugeModel()

    init() {
        registerBundledFonts()
        PanelSnapshot.runIfRequested { expanded in Panel(model: PanelSnapshot.sampleModel(), startExpanded: expanded) }
    }

    var body: some Scene {
        MenuBarExtra {
            Panel(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}


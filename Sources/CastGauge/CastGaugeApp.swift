import SwiftUI

@main
struct CastGaugeApp: App {
    @State private var model: GaugeModel

    init() {
        registerBundledFonts()
        PanelSnapshot.runIfRequested { expanded, confirming in
            Panel(model: PanelSnapshot.sampleModel(), startExpanded: expanded, startConfirming: confirming, scrolls: false)
        }
        // The model starts here, so it runs from launch, before the label first draws.
        let model = GaugeModel()
        model.start()
        _model = State(initialValue: model)
        LoginItem.configureOnFirstLaunch()
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


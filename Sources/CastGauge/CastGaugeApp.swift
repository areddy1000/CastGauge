import SwiftUI

@main
struct CastGaugeApp: App {
    @State private var model: GaugeModel

    init() {
        registerBundledFonts()
        PanelSnapshot.runIfRequested { expanded, confirming in
            Panel(model: PanelSnapshot.sampleModel(), startExpanded: expanded, startConfirming: confirming, scrolls: false)
        }
        // The menu bar item can be hidden at launch, so the model starts here, not in the label.
        let model = GaugeModel()
        model.start()
        _model = State(initialValue: model)
        LoginItem.configureOnFirstLaunch()
    }

    var body: some Scene {
        // The menu bar item shows only while a Chromecast is on the network.
        MenuBarExtra(isInserted: Binding(get: { !model.devices.isEmpty }, set: { _ in })) {
            Panel(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}


import SwiftUI
import WatchKit
import AVFoundation

/// Wraps `WKInterfaceVolumeControl` so the Digital Crown adjusts the device's
/// output volume (what headphones/speaker hear) instead of in-app gain.
/// `WKInterfaceVolumeControl` is the only supported way to do this on watchOS.
///
/// SwiftUI's `.focusable()`/`@FocusState` does not route crown input into a
/// `WKInterfaceObjectRepresentable` — focus has to be asserted directly on the
/// underlying `WKInterfaceVolumeControl` via `focus()`, and SwiftUI reclaims
/// crown focus on every view update (NowPlayingView updates every second for
/// elapsed time), so focus has to be re-asserted on a timer for as long as
/// the control stays on screen.
struct VolumeCrownControl: WKInterfaceObjectRepresentable {
    final class Coordinator {
        weak var control: WKInterfaceVolumeControl?
        private var focusTimer: Timer?

        func startReassertingFocus() {
            focusTimer?.invalidate()
            focusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.control?.focus()
            }
        }

        func stopReassertingFocus() {
            focusTimer?.invalidate()
            focusTimer = nil
        }

        deinit {
            focusTimer?.invalidate()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeWKInterfaceObject(context: Context) -> WKInterfaceVolumeControl {
        let control = WKInterfaceVolumeControl(origin: .local)
        context.coordinator.control = control
        DispatchQueue.main.async {
            control.focus()
        }
        context.coordinator.startReassertingFocus()
        return control
    }

    func updateWKInterfaceObject(_ wkInterfaceObject: WKInterfaceVolumeControl, context: Context) {}

    static func dismantleWKInterfaceObject(_ wkInterfaceObject: WKInterfaceVolumeControl, coordinator: Coordinator) {
        coordinator.stopReassertingFocus()
    }
}

/// Keeps `VolumeCrownControl` permanently in the view hierarchy (it must stay
/// live to remain the crown's focus target) but visually hidden until the
/// crown actually changes the device's output volume, then fades it back out
/// shortly after the last change.
struct VolumeIndicatorOverlay: View {
    @State private var isAdjusting = false
    @State private var volumeObserver: NSKeyValueObservation?
    @State private var hideWorkItem: DispatchWorkItem?

    var body: some View {
        VolumeCrownControl()
            .frame(width: 28, height: 28)
            // 0.015, not 0: keeps the control live as the crown conduit while
            // remaining effectively invisible at rest.
            .opacity(isAdjusting ? 1 : 0.015)
            .animation(.easeInOut(duration: 0.25), value: isAdjusting)
            .onAppear(perform: startObservingVolume)
            .onDisappear(perform: stopObservingVolume)
    }

    private func startObservingVolume() {
        volumeObserver = AVAudioSession.sharedInstance().observe(\.outputVolume, options: []) { _, _ in
            DispatchQueue.main.async {
                showIndicatorTemporarily()
            }
        }
    }

    private func stopObservingVolume() {
        volumeObserver?.invalidate()
        volumeObserver = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func showIndicatorTemporarily() {
        hideWorkItem?.cancel()
        isAdjusting = true

        let workItem = DispatchWorkItem {
            isAdjusting = false
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }
}

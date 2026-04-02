import Foundation
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        BackgroundDownloadService.shared.handle(backgroundTasks)
    }
}

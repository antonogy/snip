import Foundation
import SwiftUI

/// Process entry point.
///
/// Intercepts `--self-check` to run the headless startup verification and exit
/// before SwiftUI takes over; otherwise hands off to the SwiftUI app.
@main
enum Entrypoint {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--self-check") {
            exit(SelfCheck.run())
        }
        SnipApp.main()
    }
}

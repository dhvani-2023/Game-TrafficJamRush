import Foundation

/// iOS-only extras on top of the Android port. Each one can be switched off here; with a flag off its UI
/// entry points disappear and the game behaves exactly like the Android version.
enum ExtrasFeatures {
    /// One extra date-seeded level per local day: Home card with a calendar badge, 7-day streak strip, flame count
    /// and a streak coin reward (50 + 10 × streak, max 150).
    static let dailyPuzzle = true
    /// Undo booster in the in-game booster bar: sends the last moved vehicle that hasn't departed back to its lot spot
    /// (its passengers rejoin the front of the line). Counts as a booster for stars; 60 coins; two to start.
    static let undoBooster = true
    /// Saves the running level when the app leaves the foreground; Home offers "Continue level N?" on the next launch.
    static let autosave = true
    /// Settings toggle (default off): a distinct symbol per colour on vehicle roofs and passenger shirts.
    static let colorBlindPatterns = true
}

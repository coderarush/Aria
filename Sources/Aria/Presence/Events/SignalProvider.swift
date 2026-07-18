import Foundation

/// A source of proactive suggestions. Each provider observes one kind of signal
/// (calendar, learned routines, recurring commands, screen context) and turns it
/// into candidate `Suggestion`s. Providers are pure with respect to their injected
/// inputs so they can be tested without the live system.
protocol SignalProvider: Sendable {
    var source: SuggestionSource { get }
    func candidates(now: Date) async -> [Suggestion]
}

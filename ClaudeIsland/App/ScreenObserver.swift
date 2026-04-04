//
//  ScreenObserver.swift
//  ClaudeIsland
//
//  Monitors screen configuration changes
//

import AppKit
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "ScreenObserver")

class ScreenObserver {
    private var screenChangeObserver: Any?
    private var sleepObserver: Any?
    private var wakeObserver: Any?
    private let onScreenChange: () -> Void

    /// Debounce work item — coalesces rapid screen-change notifications
    /// (e.g. sleep/wake fires 3-5 events within milliseconds)
    private var debounceWork: DispatchWorkItem?

    /// Debounce interval in seconds
    private let debounceInterval: TimeInterval = 0.5

    /// Whether we're in a post-wake suppression window
    private var isSuppressingAfterWake = false

    /// Duration to suppress screen-change callbacks after wake (seconds)
    private let wakeSuppression: TimeInterval = 2.0

    init(onScreenChange: @escaping () -> Void) {
        self.onScreenChange = onScreenChange
        startObserving()
    }

    deinit {
        stopObserving()
    }

    private func startObserving() {
        // Screen parameter changes (resolution, arrangement, connect/disconnect)
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenChange()
        }

        // System sleep — cancel any pending work
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            logger.debug("System will sleep — cancelling pending screen-change callbacks")
            self?.debounceWork?.cancel()
            self?.debounceWork = nil
        }

        // System wake — suppress screen-change callbacks for a short window
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            logger.debug("System did wake — suppressing screen-change callbacks for \(self.wakeSuppression)s")
            self.isSuppressingAfterWake = true
            DispatchQueue.main.asyncAfter(deadline: .now() + self.wakeSuppression) { [weak self] in
                guard let self = self else { return }
                self.isSuppressingAfterWake = false
                logger.debug("Wake suppression ended — delivering deferred screen change")
                // Deliver one final callback so the window repositions to current screen geometry
                self.onScreenChange()
            }
        }
    }

    private func handleScreenChange() {
        // Drop events during post-wake suppression window
        if isSuppressingAfterWake {
            logger.debug("Dropping screen-change event (wake suppression active)")
            return
        }

        // Debounce: cancel previous pending work and schedule a new one
        debounceWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            logger.debug("Debounced screen-change callback firing")
            self.onScreenChange()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func stopObserving() {
        debounceWork?.cancel()
        debounceWork = nil

        if let obs = screenChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }
}

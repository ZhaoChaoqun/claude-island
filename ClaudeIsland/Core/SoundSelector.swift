//
//  SoundSelector.swift
//  ClaudeIsland
//
//  Manages sound selection state for the settings menu
//

import AppKit
import Combine
import Foundation

@MainActor
class SoundSelector: ObservableObject {
    static let shared = SoundSelector()

    // MARK: - Published State

    /// Which event type's picker is currently expanded (nil = all collapsed)
    @Published var expandedEventType: SoundEventType? = nil

    /// Cached sound selections per event type
    @Published var soundSelections: [SoundEventType: SoundSource] = [:]

    /// Custom sounds available for selection
    @Published var customSounds: [(URL, String)] = []

    // MARK: - Constants

    /// Maximum number of sound options to show before scrolling
    private let maxVisibleOptions = 6

    /// Height per sound option row
    private let rowHeight: CGFloat = 32

    /// Height of the event type section header
    private let sectionHeaderHeight: CGFloat = 38

    private init() {
        loadSelections()
        refreshCustomSounds()
    }

    // MARK: - Public API

    /// Play the appropriate sound for an event type
    func playSound(for event: SoundEventType) {
        let source = soundSelections[event] ?? AppSettings.sound(for: event)
        source.play()
    }

    /// Whether a sound is configured (not silent) for an event type
    func hasSound(for event: SoundEventType) -> Bool {
        let source = soundSelections[event] ?? AppSettings.sound(for: event)
        return !source.isSilent
    }

    /// Get the current sound for an event type
    func sound(for event: SoundEventType) -> SoundSource {
        soundSelections[event] ?? AppSettings.sound(for: event)
    }

    /// Set a new sound for an event type
    func setSound(_ sound: SoundSource, for event: SoundEventType) {
        soundSelections[event] = sound
        AppSettings.setSound(sound, for: event)
    }

    /// Toggle expansion of an event type's picker
    func toggleExpanded(for event: SoundEventType) {
        if expandedEventType == event {
            expandedEventType = nil
        } else {
            expandedEventType = event
        }
    }

    /// Import a custom sound file from a URL
    func importCustomSound(from url: URL) -> SoundSource? {
        guard let (savedURL, displayName) = CustomSoundsManager.importSound(from: url) else {
            return nil
        }
        refreshCustomSounds()
        return .custom(savedURL, displayName)
    }

    /// Delete a custom sound and update any event types using it
    func deleteCustomSound(at url: URL) {
        CustomSoundsManager.deleteSound(at: url)
        refreshCustomSounds()

        // Reset any event types that were using this sound
        for event in SoundEventType.allCases {
            if case .custom(let soundURL, _) = sound(for: event), soundURL == url {
                setSound(.system("Pop"), for: event)
            }
        }
    }

    /// Refresh the list of available custom sounds
    func refreshCustomSounds() {
        customSounds = CustomSoundsManager.listCustomSounds()
    }

    /// Extra height needed when a picker is expanded
    var expandedPickerHeight: CGFloat {
        guard expandedEventType != nil else { return 0 }

        // System sounds + "None" + custom sounds + import button
        let systemSoundsCount = SystemSound.allCases.count + 1 // +1 for "None"
        let customCount = customSounds.count
        let totalOptions = systemSoundsCount + customCount + 1 // +1 for import button
        let visibleOptions = min(totalOptions, maxVisibleOptions)
        return CGFloat(visibleOptions) * rowHeight + 8
    }

    /// Total extra height for the sound settings section in the menu
    var totalSoundSectionHeight: CGFloat {
        // Each event type gets a section header row
        let headersHeight = CGFloat(SoundEventType.allCases.count) * sectionHeaderHeight
        // Plus any expanded picker height
        return headersHeight + expandedPickerHeight
    }

    // MARK: - Private

    private func loadSelections() {
        AppSettings.migrateSoundSettingsIfNeeded()
        for event in SoundEventType.allCases {
            soundSelections[event] = AppSettings.sound(for: event)
        }
    }
}

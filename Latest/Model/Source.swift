//
//  Source.swift
//  Latest
//
//  Created by Max Langer on 14.03.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

import AppKit

extension App {
	
	/// The source of update information.
	enum Source: String, Equatable {
		/// No known source had information about this app. It is unsupported by the update checker.
		case none
		
		/// The Sparkle Updater is the update source.
		case sparkle
		
		/// The Mac App Store is the update source.
		case appStore
		
		/// Homebrew is the update source.
		case homebrew
		
		/// The icon representing the source.
		var sourceIcon: NSImage? {
			switch self {
			case .none:
				return nil
			case .sparkle:
				return NSImage(named: "sparkle")
			case .appStore:
				return NSImage(named: "appstore")
			case .homebrew:
				return NSImage(named: "brew")
			}
		}
		
		/// The name of the source.
		var sourceName: String? {
			switch self {
			case .none:
				return nil
			case .sparkle:
				return NSLocalizedString("WebSource", comment: "The source name for apps loaded from third-party websites.")
			case .appStore:
				return NSLocalizedString("AppStoreSource", comment: "The source name of apps loaded from the App Store.")
			case .homebrew:
				return NSLocalizedString("HomebrewSource", comment: "The source name for apps checked via the Homebrew package manager.")
				
			}
		}
	}
}

// MARK: - Support State

extension App.Source {
	/// Possible states for whether a source is supported by the app.
	enum SupportState {
		/// The source is fully supported, including in-app updates.
		case full
		
		/// Update information is available and Latest can update the app with limited integration, such as via Homebrew.
		case limited
		
		/// The source is unknown and no update information is available.
		case none
	}
	
	/// Whether the source is supported by the app.
	var supportState: SupportState {
		switch self {
		case .none:
			return .none
		case .sparkle, .appStore:
			return .full
		case .homebrew:
			return .limited
		}
	}
}


// MARK: Accessors

extension App.Source.SupportState {
	private static let limitedColor = NSColor(red: 249.0 / 255.0, green: 208.0 / 255.0, blue: 148.0 / 255.0, alpha: 1.0)

	/// Returns an image using the system status indicator (colored dot) for the given status.
	var statusImage: NSImage {
		switch self {
		case .limited:
			let baseImage = NSImage(named: NSImage.statusPartiallyAvailableName)!
			let image = NSImage(size: baseImage.size, flipped: false) { rect in
				baseImage.draw(in: rect)
				Self.limitedColor.setFill()
				rect.fill(using: .sourceAtop)
				return true
			}
			image.isTemplate = false
			return image
		case .full, .none:
			let name = self == .full ? NSImage.statusAvailableName : NSImage.statusUnavailableName
			
			return NSImage(named: name)!
		}
	}
	
	/// Returns a label briefly describing the given status.
	var label: String {
		switch self {
		case .full: NSLocalizedString("SupportedLabel", comment: "A label used for apps which are fully supported by Latest.")
		case .limited: NSLocalizedString("LimitedSupportLabel", comment: "A label used for apps which are updated via Homebrew.")
		case .none: NSLocalizedString("UnsupportedLabel", comment: "A label used for apps which are not supported by Latest.")
		}
	}
	
	/// A more compact version of the label describing the given status.
	var compactLabel: String {
		switch self {
		case .full: NSLocalizedString("SupportedCompactLabel", comment: "A compact label used for apps which are fully supported by Latest.")
		case .limited: NSLocalizedString("LimitedSupportCompactLabel", comment: "A compact label used for apps which are updated via Homebrew.")
		case .none: NSLocalizedString("UnsupportedCompactLabel", comment: "A compact label used for apps which are not supported by Latest.")
		}
	}
}

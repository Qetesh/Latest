//
//  UpdateOperation.swift
//  Latest
//
//  Created by Max Langer on 01.07.19.
//  Copyright © 2019 Max Langer. All rights reserved.
//

import Foundation

/// The abstract update operation used for updating apps.
class UpdateOperation: StatefulOperation, @unchecked Sendable {
	
	/// Encapsulates different states that may be active during the update process.
	enum ProgressState {
		/// No update is occurring at the moment.
		case none
		
		/// The update is currently waiting to be executed. This may happen due to external constraints like the Mac App Store update queue.
		case pending
		
		/// The download is currently initializing. This may be fetching update information from a server.
		case initializing
		
		/// The new version is currently downloading. Loaded size defines the already downloaded bytes. Total size defines the final size of the download.
		case downloading(loadedSize: Int64, totalSize: Int64)
		
		/// The update is being extracted. The extraction progress is given.
		case extracting(progress: Double)
		
		/// The update is currently installing.
		case installing
		
		/// An error occurred during updating.
		case error(Error)
		
		/// The update is currently being cancelled.
		case cancelling
	}
	
	/// The app that is updated by this operation.
	let bundleIdentifier: String
	
	/// The identifier of the updated app.
	let appIdentifier: App.Bundle.Identifier

	/// Guards access to progress state shared between background work and the UI.
	private let progressLock = NSLock()

	/// Private storage for the current progress handler.
	private var _progressHandler: UpdateQueue.ProgressHandler?

	/// Private storage for the current progress description.
	private var _progressDescription: String?

	/// Private storage for the current progress state.
	private var _progressState: UpdateOperation.ProgressState = .pending
	
	/// The handler forwarding the current progress state.
	var progressHandler: UpdateQueue.ProgressHandler? {
		get {
			return self.progressLock.withCriticalScope {
				self._progressHandler
			}
		}
		set {
			let handler = self.progressLock.withCriticalScope { () -> UpdateQueue.ProgressHandler? in
				self._progressHandler = newValue
				return self._progressHandler
			}

			// Notify immediately
			handler?(self.appIdentifier)
		}
	}

	/// The text describing the current progress state.
	var progressDescription: String? {
		get {
			return self.progressLock.withCriticalScope {
				self._progressDescription
			}
		}
		set {
			let handler = self.progressLock.withCriticalScope { () -> UpdateQueue.ProgressHandler? in
				guard self._progressDescription != newValue else { return nil }
				self._progressDescription = newValue
				return self._progressHandler
			}

			handler?(self.appIdentifier)
		}
	}
	
	/// The current update state.
	var progressState: UpdateOperation.ProgressState {
		get {
			return self.progressLock.withCriticalScope {
				self._progressState
			}
		}
		set {
			let handler = self.progressLock.withCriticalScope { () -> UpdateQueue.ProgressHandler? in
				self._progressState = newValue
				return self._progressHandler
			}

			handler?(self.appIdentifier)
		}
	}

	
	/// Initializes the operation with the given app and progress handler.
	init(bundleIdentifier: String, appIdentifier: App.Bundle.Identifier) {
		self.bundleIdentifier = bundleIdentifier
		self.appIdentifier = appIdentifier
	}
	
	
	// MARK: - Operation sub-classing
	
	override func execute() {
		self.progressDescription = nil
		self.progressState = .initializing
	}
	
	override func cancel() {
		super.cancel()
		self.progressDescription = nil
		self.progressState = .cancelling
	}
		
	override func finish() {
		self.progressDescription = nil
		if let error = self.error {
			self.progressState = .error(error)
		} else {
			self.progressState = .none
		}
		
		super.finish()
	}
	
}

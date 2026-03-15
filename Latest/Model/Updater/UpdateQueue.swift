//
//  UpdateQueue.swift
//  Latest
//
//  Created by Max Langer on 01.07.19.
//  Copyright © 2019 Max Langer. All rights reserved.
//

import Foundation

/// The queue where update operations are scheduled on.
class UpdateQueue: OperationQueue, @unchecked Sendable {
	
	// MARK: - Initialization
	private override init() {
		super.init()
		
		self.maxConcurrentOperationCount = 3
	}
	
	/// The shared instance of the queue.
	static let shared = UpdateQueue()
	
	
	// MARK: - Public Methods
	
	/// The handler forwarding the current progress state.
	typealias ProgressHandler = (_: App.Bundle.Identifier) -> Void
	
	/// Cancels the update operation for the given app.
	func cancelUpdate(for identifier: App.Bundle.Identifier) {
		guard let operation = self.operation(for: identifier) else { return }
		operation.cancel()
	}
	
	/// Whether the queue contains an update operation for the given app.
	func contains(_ identifier: App.Bundle.Identifier) -> Bool {
		return self.operation(for: identifier) != nil
	}
	
	/// Returns the state for a given app.
	func state(for identifier: App.Bundle.Identifier) -> UpdateOperation.ProgressState {
		return self.operation(for: identifier)?.progressState ?? .none
	}

	/// Returns the current status description for a given app.
	func statusDescription(for identifier: App.Bundle.Identifier) -> String? {
		return self.operation(for: identifier)?.progressDescription
	}
	
	override func addOperation(_ op: Operation) {
		// Abort if the operation is of an unknown type
		guard let operation = op as? UpdateOperation else {
			assertionFailure("Added unknown operation \(op.self) to update queue.")
			return
		}
		
		// Abort if the app is already in the queue
		if !self.contains(operation.appIdentifier) {
			if let homebrewOperation = operation as? HomebrewUpdateOperation,
			   let previousHomebrewOperation = self.operations.compactMap({ $0 as? HomebrewUpdateOperation }).last {
				homebrewOperation.addDependency(previousHomebrewOperation)
			}

			super.addOperation(op)
			
			operation.progressHandler = { identifier in
				self.notifyObservers(for: identifier)
			}
		}
	}
	
	
	// MARK: - Observer Handling
	
	/// The handler for notifying observers about changes to the update state.
	typealias ObserverHandler = (_: UpdateOperation.ProgressState) -> Void

	/// A mapping of observers associated with apps.
	private var observers = [App.Bundle.Identifier : [NSObject: ObserverHandler]]()
	
	/// App identifiers that already have an observer update queued on the main thread.
	private var pendingNotifications = Set<App.Bundle.Identifier>()
	
	/// Guards access to observer bookkeeping.
	private let observerLock = NSLock()
	
	/// Adds the observer if it is not already registered.
	func addObserver(_ observer: NSObject, to identifier: App.Bundle.Identifier, handler: @escaping ObserverHandler) {
		let shouldRegister = self.observerLock.withCriticalScope { () -> Bool in
			var observers = self.observers[identifier] ?? [:]
			
			// Only add the observer, if it is not already installed.
			guard observers[observer] == nil else {
				return false
			}
			
			observers[observer] = handler
			self.observers[identifier] = observers
			return true
		}
		guard shouldRegister else { return }
		
		// Call handler immediately to propagate initial state
		handler(self.state(for: identifier))
	}
	
	/// Removes the observer.
	func removeObserver(_ observer: NSObject, for identifier: App.Bundle.Identifier) {
		_ = self.observerLock.withCriticalScope {
			self.observers[identifier]?.removeValue(forKey: observer)
		}
	}
		
	/// Notifies observers about state changes.
	private func notifyObservers(for identifier: App.Bundle.Identifier) {
		let shouldSchedule = self.observerLock.withCriticalScope { () -> Bool in
			guard !self.pendingNotifications.contains(identifier) else {
				return false
			}
			
			self.pendingNotifications.insert(identifier)
			return true
		}
		guard shouldSchedule else { return }
		
		DispatchQueue.main.async {
			let state = self.state(for: identifier)
			let handlers = self.observerLock.withCriticalScope { () -> [UpdateQueue.ObserverHandler] in
				self.pendingNotifications.remove(identifier)
				return Array((self.observers[identifier] ?? [:]).values)
			}
			
			handlers.forEach { handler in
				handler(state)
			}
		}
	}
	
	
	// MARK: - Helper
	
	/// Returns the operation for the given app.
	private func operation(for identifier: App.Bundle.Identifier) -> UpdateOperation? {
		guard let updateOperations = self.operations as? [UpdateOperation] else {
			fatalError("Unknown operations in update queue")
		}
				
		return updateOperations.first(where: { $0.appIdentifier == identifier })
	}
		
}

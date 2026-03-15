//
//  HomebrewUpdateOperation.swift
//  Latest
//
//  Created by qetesh on 14.03.26.
//

import Foundation

enum HomebrewTool {

	static var isAvailable: Bool {
		executableURL != nil
	}

	static let executableURL: URL? = {
		let knownPaths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        let fileManager = FileManager.default
        for path in knownPaths {
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }()
}

/// The operation updating Homebrew casks.
class HomebrewUpdateOperation: UpdateOperation, @unchecked Sendable {
    
    private static let ansiEscapeRegex = try? NSRegularExpression(pattern: "\u{001B}\\[[0-9;]*[A-Za-z]")
    
    private let caskToken: String
    
    private var process: Process?
    private var outputBuffer = ""
    private var recentOutputLines = [String]()
    private let outputQueue = DispatchQueue(label: "HomebrewUpdateOperation.output")
    
    init(bundleIdentifier: String, appIdentifier: App.Bundle.Identifier, caskToken: String) {
        self.caskToken = caskToken
        super.init(bundleIdentifier: bundleIdentifier, appIdentifier: appIdentifier)
    }
    
    
    // MARK: - Operation Overrides
    
    override func execute() {
        super.execute()
        
        guard HomebrewTool.isAvailable else {
            self.finishHomebrewUnavailable()
            return
        }
        
        self.startUpdate()
    }
    
    override func cancel() {
        super.cancel()
        self.process?.terminate()
    }
    
    override func finish() {
        self.process = nil
        super.finish()
    }
    
    
    // MARK: - Running Commands
    
    private func startUpdate() {
        self.progressDescription = NSLocalizedString("HomebrewRunningUpdateStatus", comment: "Status text while running brew update.")
        self.progressState = .downloading(loadedSize: 1, totalSize: 4)
        self.run(arguments: ["update"]) { success in
            guard success else { return }
            self.startReinstall()
        }
    }
    
    private func startReinstall() {
        let format = NSLocalizedString("HomebrewRunningReinstallStatus", comment: "Status text while running brew reinstall for a cask. The placeholder is the cask token.")
        self.progressDescription = String.localizedStringWithFormat(format, self.caskToken)
        self.progressState = .downloading(loadedSize: 2, totalSize: 4)
        self.run(arguments: ["reinstall", "--cask", "--force", self.caskToken]) { success in
            guard success else { return }
            self.finish()
        }
    }
    
    private func run(arguments: [String], completion: @escaping (Bool) -> Void) {
        guard let executableURL = HomebrewTool.executableURL else {
            self.finishHomebrewUnavailable()
            return
        }
        
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consumeOutput(data, arguments: arguments)
        }
        
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            fileHandle.readabilityHandler = nil
            self.flushOutput(arguments: arguments)
            
            if self.isCancelled {
                self.finish()
                return
            }
            
            guard process.terminationStatus == 0 else {
                self.finish(with: self.homebrewFailureError(for: arguments))
                return
            }
            
            completion(true)
        }
        
        do {
            try process.run()
            self.process = process
        } catch {
            self.finish(with: error)
        }
    }
    
    
    // MARK: - Output Handling
    
    private func consumeOutput(_ data: Data, arguments: [String]) {
        outputQueue.async {
            guard let string = String(data: data, encoding: .utf8), !string.isEmpty else { return }
            self.outputBuffer += string
            
            let lines = self.outputBuffer.components(separatedBy: .newlines)
            self.outputBuffer = lines.last ?? ""
            
            for line in lines.dropLast() {
                self.handleOutputLine(line, arguments: arguments)
            }
        }
    }
    
    private func flushOutput(arguments: [String]) {
        outputQueue.sync {
            guard !self.outputBuffer.isEmpty else { return }
            self.handleOutputLine(self.outputBuffer, arguments: arguments)
            self.outputBuffer = ""
		}
	}

	private func handleOutputLine(_ line: String, arguments: [String]) {
		let cleanedLine = self.clean(line)
		guard !cleanedLine.isEmpty else { return }

		self.recentOutputLines.append(cleanedLine)
		if self.recentOutputLines.count > 20 {
			self.recentOutputLines.removeFirst(self.recentOutputLines.count - 20)
		}

		self.progressDescription = cleanedLine

		if arguments.first == "update" {
			self.progressState = .downloading(loadedSize: 1, totalSize: 4)
			return
		}

		if cleanedLine.localizedCaseInsensitiveContains("Downloading") {
			self.progressState = .downloading(loadedSize: 3, totalSize: 4)
		} else if cleanedLine.hasPrefix("==> Reinstalling") {
			self.progressState = .extracting(progress: 0.4)
		} else if cleanedLine.hasPrefix("==> Installing")
			|| cleanedLine.hasPrefix("==> Pouring")
			|| cleanedLine.hasPrefix("==> Moving App")
			|| cleanedLine.hasPrefix("==> Linking")
			|| cleanedLine.hasPrefix("==> Artifact") {
			self.progressState = .extracting(progress: 0.6)
		} else if cleanedLine.hasPrefix("==> Cleaning")
			|| cleanedLine.hasPrefix("==> Purging") {
			self.progressState = .extracting(progress: 0.9)
		} else {
			self.progressState = .downloading(loadedSize: 2, totalSize: 4)
		}
	}

	private func finishHomebrewUnavailable() {
		let title = NSLocalizedString("HomebrewNotFoundError", comment: "Title of error shown when Homebrew is not installed.")
		let description = NSLocalizedString("HomebrewNotFoundErrorDescription", comment: "Description of error shown when Homebrew is not installed, suggesting the user install it.")
		self.finish(with: LatestError.custom(title: title, description: description))
	}

	private func homebrewFailureError(for arguments: [String]) -> LatestError {
		let description = self.outputQueue.sync {
			self.recentOutputLines.joined(separator: "\n")
		}
		let fallbackFormat = NSLocalizedString("HomebrewCommandFailedError", comment: "Error message shown when a Homebrew command failed. The placeholder is the command arguments.")
		let errorDescription = description.isEmpty ? String.localizedStringWithFormat(fallbackFormat, arguments.joined(separator: " ")) : description
		let title = NSLocalizedString("HomebrewUpdateFailedError", comment: "Title of error shown when a Homebrew update failed.")
		return LatestError.custom(title: title, description: errorDescription)
	}

	private func clean(_ line: String) -> String {
		let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return "" }

		guard let regex = Self.ansiEscapeRegex else {
			return trimmed
		}

		let range = NSRange(location: 0, length: trimmed.utf16.count)
		return regex.stringByReplacingMatches(in: trimmed, options: [], range: range, withTemplate: "")
	}
}

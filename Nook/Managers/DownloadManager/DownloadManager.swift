//
//  DownloadManager.swift
//  Nook
//
//  Created by Maciek Bagiński on 05/08/2025.
//

import AppKit
import Foundation
import OSLog
import QuickLook
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private let logger = Logger(subsystem: "com.baingurley.nook", category: "DownloadManager")

// MARK: - Download Model

@Observable
public class Download: Identifiable {
    public let id: UUID
    let originalURL: URL
    let suggestedFilename: String
    let destinationPreference: DestinationPreference
    let allowedContentTypes: [UTType]?
    var destinationURL: URL?
    var progress: Double
    var state: DownloadState {
        didSet {
            if state == .completed && oldValue != .completed {
                Task {
                    await loadThumbnail()
                }
            }
        }
    }

    var error: Error?
    var fileSize: Int64?
    var downloadedBytes: Int64
    var icon: NSImage?
    var startDate: Date
    var estimatedTimeRemaining: TimeInterval?
    var downloadThumbnail: NSImage?

    /// Called to cancel the underlying download (WKDownload or URLSessionTask).
    var cancelHandler: (() -> Void)?

    enum DownloadState {
        case pending
        case downloading
        case completed
        case failed
        case cancelled

        var description: String {
            switch self {
            case .pending:
                return "Pending"
            case .downloading:
                return "Downloading"
            case .completed:
                return "Completed"
            case .failed:
                return "Failed"
            case .cancelled:
                return "Cancelled"
            }
        }

        var icon: String {
            switch self {
            case .pending:
                return "clock"
            case .downloading:
                return "arrow.down.circle"
            case .completed:
                return "checkmark.circle"
            case .failed:
                return "exclamationmark.circle"
            case .cancelled:
                return "xmark.circle"
            }
        }
    }

    enum DestinationPreference {
        case automaticDownloadsFolder
        case askUser
    }

    init(
        originalURL: URL,
        suggestedFilename: String,
        destinationPreference: DestinationPreference = .automaticDownloadsFolder,
        allowedContentTypes: [UTType]? = nil
    ) {
        id = UUID()
        self.originalURL = originalURL
        self.suggestedFilename = suggestedFilename
        self.destinationPreference = destinationPreference
        self.allowedContentTypes = allowedContentTypes
        progress = 0.0
        state = .pending
        downloadedBytes = 0
        startDate = Date()

        // Set default icon based on file extension
        icon = getIconForFile(suggestedFilename)
    }

    @MainActor
    func loadThumbnail(size: CGSize = CGSize(width: 80, height: 80)) async {
        guard let destinationURL = destinationURL,
              FileManager.default.fileExists(atPath: destinationURL.path),
              downloadThumbnail == nil
        else {
            return
        }

        if shouldGenerateThumbnail(for: destinationURL) {
            if let thumbnail = await getQuickLookThumbnail(for: destinationURL, size: size) {
                downloadThumbnail = thumbnail
                return
            }
        }

        let finderIcon = NSWorkspace.shared.icon(forFile: destinationURL.path)

        let targetSize = NSSize(width: size.width, height: size.height)
        let highResIcon = NSImage(size: targetSize)

        highResIcon.lockFocus()
        finderIcon.draw(in: NSRect(origin: .zero, size: targetSize),
                        from: NSRect(origin: .zero, size: finderIcon.size),
                        operation: .copy,
                        fraction: 1.0)
        highResIcon.unlockFocus()

        downloadThumbnail = highResIcon
    }

    private func shouldGenerateThumbnail(for fileURL: URL) -> Bool {
        let fileExtension = fileURL.pathExtension.lowercased()

        let supportedExtensions: Set<String> = [
            // Images
            "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "webp", "ico", "svg",
            // Videos
            "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v",
            // Documents
            "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "pages", "numbers", "keynote",
            // Text files
            "txt", "rtf", "html", "htm", "md", "swift", "js", "css", "json", "xml",
            // Audio files
            "mp3", "m4a", "flac", "aac",
        ]

        return supportedExtensions.contains(fileExtension)
    }

    private func getQuickLookThumbnail(for fileURL: URL, size: CGSize) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 1.0,
            representationTypes: .thumbnail
        )

        do {
            let thumbnail = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return thumbnail.nsImage
        } catch {
            return nil
        }
    }

    private func getIconForFile(_ filename: String) -> NSImage {
        let fileExtension = (filename as NSString).pathExtension.lowercased()

        let possibleTypes = UTType.types(tag: fileExtension,
                                         tagClass: .filenameExtension,
                                         conformingTo: nil)

        if let utType = possibleTypes.first {
            return NSWorkspace.shared.icon(for: utType)
        } else {
            return NSWorkspace.shared.icon(for: .item)
        }
    }

    var formattedFileSize: String {
        guard let fileSize = fileSize else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedDownloadedSize: String {
        return ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
    }

    var formattedProgress: String {
        return String(format: "%.1f%%", progress * 100)
    }

    var formattedSpeed: String {
        let elapsed = Date().timeIntervalSince(startDate)
        guard elapsed > 0 else { return "0 B/s" }

        let speed = Double(downloadedBytes) / elapsed
        return ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .binary) + "/s"
    }

    var formattedTimeRemaining: String {
        guard let estimatedTimeRemaining = estimatedTimeRemaining else { return "Unknown" }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: estimatedTimeRemaining) ?? "Unknown"
    }
}

// MARK: - Download Manager

@MainActor
@Observable
public class DownloadManager: NSObject {
    public static let shared = DownloadManager()

    private var downloads: [UUID: Download] = [:]

    /// Retains WKDownload delegates (for blob:/data: URL fallback downloads).
    private var wkDownloadDelegates: [UUID: WKDownloadDelegateHandler] = [:]

    /// Retains URLSession coordinators (for http/https disk-streaming downloads).
    private var urlSessionCoordinators: [UUID: URLSessionDownloadCoordinator] = [:]

    var activeDownloads: [Download] {
        return Array(downloads.values).filter { $0.state == .downloading || $0.state == .pending }
    }

    var completedDownloads: [Download] {
        return Array(downloads.values).filter { $0.state == .completed }
    }

    var failedDownloads: [Download] {
        return Array(downloads.values).filter { $0.state == .failed }
    }

    var allDownloads: [Download] {
        return Array(downloads.values).sorted { $0.startDate > $1.startDate }
    }

    var totalDownloads: Int {
        return downloads.count
    }

    var activeDownloadsCount: Int {
        return activeDownloads.count
    }

    override private init() {
        super.init()
    }

    // MARK: - Download Management

    /// Add a download. For http/https URLs, cancels the WKDownload and uses
    /// URLSessionDownloadTask instead, which streams directly to disk with
    /// constant memory usage. For blob:/data: URLs, falls back to WKDownload.
    ///
    /// - Parameter dataStore: The WKWebsiteDataStore from the originating webview,
    ///   used to copy cookies for authenticated URLSession downloads.
    func addDownload(
        _ wkDownload: WKDownload,
        originalURL: URL,
        suggestedFilename: String,
        dataStore: WKWebsiteDataStore? = nil,
        destinationPreference: Download.DestinationPreference = .automaticDownloadsFolder,
        allowedContentTypes: [UTType]? = nil
    ) -> Download {
        let scheme = originalURL.scheme?.lowercased() ?? ""
        let canUseURLSession = (scheme == "http" || scheme == "https")

        if canUseURLSession {
            // Cancel WKDownload — we'll re-request via URLSession which streams to disk
            wkDownload.cancel()
            return addURLSessionDownload(
                url: originalURL,
                suggestedFilename: suggestedFilename,
                dataStore: dataStore,
                destinationPreference: destinationPreference,
                allowedContentTypes: allowedContentTypes
            )
        } else {
            // Fallback: use WKDownload for blob:/data: URLs
            return addWKDownload(
                wkDownload,
                originalURL: originalURL,
                suggestedFilename: suggestedFilename,
                destinationPreference: destinationPreference,
                allowedContentTypes: allowedContentTypes
            )
        }
    }

    // MARK: - URLSession Downloads (http/https)

    private func addURLSessionDownload(
        url: URL,
        suggestedFilename: String,
        dataStore: WKWebsiteDataStore?,
        destinationPreference: Download.DestinationPreference,
        allowedContentTypes: [UTType]?
    ) -> Download {
        let downloadModel = Download(
            originalURL: url,
            suggestedFilename: suggestedFilename,
            destinationPreference: destinationPreference,
            allowedContentTypes: allowedContentTypes
        )

        let coordinator = URLSessionDownloadCoordinator(
            downloadManager: self,
            download: downloadModel
        )

        downloads[downloadModel.id] = downloadModel
        urlSessionCoordinators[downloadModel.id] = coordinator

        downloadModel.cancelHandler = { [weak coordinator] in
            coordinator?.cancel()
        }

        logger.info("Starting URLSession download for \(suggestedFilename, privacy: .public)")

        // Fetch cookies from the webview's data store, then start download
        Task { @MainActor in
            var cookies: [HTTPCookie] = []
            if let dataStore = dataStore {
                cookies = await dataStore.httpCookieStore.allCookies()
            }
            coordinator.start(url: url, cookies: cookies)
        }

        return downloadModel
    }

    // MARK: - WKDownload Fallback (blob:/data: URLs)

    private func addWKDownload(
        _ wkDownload: WKDownload,
        originalURL: URL,
        suggestedFilename: String,
        destinationPreference: Download.DestinationPreference,
        allowedContentTypes: [UTType]?
    ) -> Download {
        let downloadModel = Download(
            originalURL: originalURL,
            suggestedFilename: suggestedFilename,
            destinationPreference: destinationPreference,
            allowedContentTypes: allowedContentTypes
        )
        let delegate = WKDownloadDelegateHandler(downloadManager: self, download: downloadModel)

        downloads[downloadModel.id] = downloadModel
        wkDownloadDelegates[downloadModel.id] = delegate
        wkDownload.delegate = delegate

        downloadModel.cancelHandler = { [weak wkDownload] in
            wkDownload?.cancel()
        }

        logger.info("Using WKDownload fallback for \(originalURL.scheme ?? "unknown", privacy: .public) URL: \(suggestedFilename, privacy: .public)")
        return downloadModel
    }

    // MARK: - Lifecycle

    func removeDownload(_ id: UUID) {
        downloads.removeValue(forKey: id)
        wkDownloadDelegates.removeValue(forKey: id)
        if let coordinator = urlSessionCoordinators.removeValue(forKey: id) {
            coordinator.invalidate()
        }
    }

    func cancelDownload(_ id: UUID) {
        guard let download = downloads[id] else { return }
        download.cancelHandler?()
        download.state = .cancelled
        logger.info("Cancelled download: \(download.suggestedFilename, privacy: .public)")
    }

    func retryDownload(_ id: UUID) {
        guard let download = downloads[id], download.state == .failed else { return }
        logger.debug("Retry not yet supported")
    }

    func clearCompletedDownloads() {
        let completedIds = downloads.values.filter { $0.state == .completed }.map { $0.id }
        for id in completedIds {
            removeDownload(id)
        }
    }

    func clearFailedDownloads() {
        let failedIds = downloads.values.filter { $0.state == .failed }.map { $0.id }
        for id in failedIds {
            removeDownload(id)
        }
    }

    func clearAllDownloads() {
        for (_, coordinator) in urlSessionCoordinators {
            coordinator.invalidate()
        }
        downloads.removeAll()
        wkDownloadDelegates.removeAll()
        urlSessionCoordinators.removeAll()
    }

    // MARK: - Download Updates

    func updateDownloadProgress(_ id: UUID, progress: Double, downloadedBytes: Int64, fileSize: Int64?) {
        guard let download = downloads[id] else { return }

        download.progress = progress
        download.downloadedBytes = downloadedBytes
        download.fileSize = fileSize

        // Calculate estimated time remaining
        if let fileSize = fileSize, downloadedBytes > 0 {
            let elapsed = Date().timeIntervalSince(download.startDate)
            let bytesPerSecond = Double(downloadedBytes) / elapsed
            let remainingBytes = fileSize - downloadedBytes
            download.estimatedTimeRemaining = Double(remainingBytes) / bytesPerSecond
        }
    }

    func updateDownloadState(_ id: UUID, state: Download.DownloadState, error: Error? = nil) {
        guard let download = downloads[id] else { return }

        download.state = state
        download.error = error

        if state == .failed, let error = error {
            logger.error("Download failed: \(download.suggestedFilename, privacy: .public) - \(error.localizedDescription, privacy: .public)")
        }
    }

    func setDownloadDestination(_ id: UUID, destination: URL) {
        guard let download = downloads[id] else { return }
        download.destinationURL = destination
    }
}

// MARK: - URLSession Download Coordinator

/// Handles large file downloads via URLSessionDownloadTask, which streams
/// response data directly to a temporary file on disk — using constant memory
/// regardless of file size.
private class URLSessionDownloadCoordinator: NSObject, URLSessionDownloadDelegate {
    weak var downloadManager: DownloadManager?
    let download: Download
    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    init(downloadManager: DownloadManager, download: Download) {
        self.downloadManager = downloadManager
        self.download = download
        super.init()
    }

    func start(url: URL, cookies: [HTTPCookie]) {
        let config = URLSessionConfiguration.default
        // Disable URL cache — we're writing to a file
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Copy cookies from the webview for authenticated downloads
        let storage = HTTPCookieStorage()
        for cookie in cookies {
            storage.setCookie(cookie)
        }
        config.httpCookieStorage = storage

        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let task = session.downloadTask(with: request)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func invalidate() {
        session?.invalidateAndCancel()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Resolve destination on main actor, then move file
        let suggestedFilename = download.suggestedFilename
        let destinationPreference = download.destinationPreference
        let allowedContentTypes = download.allowedContentTypes
        let downloadId = download.id

        // Determine destination synchronously using the same logic as WKDownload path
        let destination: URL
        switch destinationPreference {
        case .automaticDownloadsFolder:
            destination = Self.resolveAutomaticDestination(filename: suggestedFilename)
        case .askUser:
            // For save panel, we need main thread — use automatic as fallback
            // (save panel flow is handled before download starts in the WKDownload path,
            // but URLSession doesn't have that hook, so we default to Downloads folder)
            destination = Self.resolveAutomaticDestination(filename: suggestedFilename)
        }

        do {
            // Ensure destination directory exists
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // If destination already exists (race condition), remove it
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            Self.setQuarantineAttribute(on: destination)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.downloadManager?.setDownloadDestination(downloadId, destination: destination)
                self.downloadManager?.updateDownloadState(downloadId, state: .completed)
            }
        } catch {
            logger.error("Failed to move download to destination: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.downloadManager?.updateDownloadState(downloadId, state: .failed, error: error)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let fileSize: Int64? = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        let progress = fileSize.map { Double(totalBytesWritten) / Double($0) } ?? 0.0
        let clampedProgress = min(progress, 1.0)
        let downloadId = download.id

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.downloadManager?.updateDownloadProgress(
                downloadId,
                progress: clampedProgress,
                downloadedBytes: totalBytesWritten,
                fileSize: fileSize
            )
            // Transition from pending to downloading on first data
            if self.download.state == .pending {
                self.downloadManager?.updateDownloadState(downloadId, state: .downloading)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let error = error else { return }
        // Don't report cancellation as failure
        if (error as NSError).code == NSURLErrorCancelled { return }

        let downloadId = download.id
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.downloadManager?.updateDownloadState(downloadId, state: .failed, error: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Follow redirects
        completionHandler(request)
    }

    // MARK: - Destination Resolution

    private static func resolveAutomaticDestination(filename: String) -> URL {
        let cleanName = sanitizeFilename(filename)

        guard let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return FileManager.default.temporaryDirectory.appendingPathComponent(cleanName)
        }

        var destination = downloadsDirectory.appendingPathComponent(cleanName)
        let ext = destination.pathExtension
        let base = destination.deletingPathExtension().lastPathComponent
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            let newName = "\(base) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)")
            destination = downloadsDirectory.appendingPathComponent(newName)
            counter += 1
        }

        return destination
    }

    static func sanitizeFilename(_ filename: String) -> String {
        let defaultName = filename.isEmpty ? "download" : filename
        var cleanName = defaultName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\0", with: "")
        while cleanName.hasPrefix(".") {
            cleanName = String(cleanName.dropFirst())
        }
        if cleanName.isEmpty { cleanName = "download" }
        if cleanName.count > 255 {
            let ext = (cleanName as NSString).pathExtension
            let base = (cleanName as NSString).deletingPathExtension
            let maxBase = 255 - (ext.isEmpty ? 0 : ext.count + 1)
            cleanName = String(base.prefix(maxBase)) + (ext.isEmpty ? "" : ".\(ext)")
        }
        cleanName = (cleanName as NSString).lastPathComponent
        return cleanName
    }

    /// Sets the `com.apple.quarantine` extended attribute on a downloaded file.
    static func setQuarantineAttribute(on fileURL: URL) {
        let quarantineValue = "0083;\(String(format: "%08x", Int(Date().timeIntervalSince1970)));Nook;\(UUID().uuidString)"
        guard let data = quarantineValue.data(using: .utf8) else { return }

        fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path = path else { return }
            _ = setxattr(path, "com.apple.quarantine", (data as NSData).bytes, data.count, 0, 0)
        }
    }
}

// MARK: - WKDownload Delegate Handler (fallback for blob:/data: URLs)

private class WKDownloadDelegateHandler: NSObject, WKDownloadDelegate {
    weak var downloadManager: DownloadManager?
    let download: Download

    init(downloadManager: DownloadManager, download: Download) {
        self.downloadManager = downloadManager
        self.download = download
        super.init()
    }

    private enum DestinationDecision {
        case proceed(URL)
        case cancel
    }

    // iOS-style API (older) – keep for compatibility where this signature exists
    public func download(_: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        decideDestination(response: response, suggestedFilename: suggestedFilename) { [weak self] decision in
            guard self != nil else { return }
            switch decision {
            case .proceed(let url):
                completionHandler(url)
            case .cancel:
                completionHandler(nil)
            }
        }
    }

    // macOS 12+/15+ API – WebKit on macOS expects the (URL, Bool) completion to grant a sandbox extension
    public func download(_ wkDownload: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL, Bool) -> Void) {
        decideDestination(response: response, suggestedFilename: suggestedFilename) { [weak self] decision in
            guard self != nil else { return }
            switch decision {
            case .proceed(let url):
                completionHandler(url, true)
            case .cancel:
                wkDownload.cancel()
                completionHandler(URL(fileURLWithPath: "/tmp/cancelled"), false)
            }
        }
    }

    private func decideDestination(response: URLResponse, suggestedFilename: String, completion: @escaping (DestinationDecision) -> Void) {
        let cleanName = URLSessionDownloadCoordinator.sanitizeFilename(
            suggestedFilename.isEmpty ? "download" : suggestedFilename
        )

        switch download.destinationPreference {
        case .automaticDownloadsFolder:
            resolveAutomaticDestination(response: response, cleanName: cleanName, completion: completion)
        case .askUser:
            presentSavePanel(response: response, cleanName: cleanName, completion: completion)
        }
    }

    private func resolveAutomaticDestination(response: URLResponse, cleanName: String, completion: @escaping (DestinationDecision) -> Void) {
        guard let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            presentSavePanel(response: response, cleanName: cleanName, completion: completion)
            return
        }

        var destination = downloadsDirectory.appendingPathComponent(cleanName)
        let ext = destination.pathExtension
        let base = destination.deletingPathExtension().lastPathComponent
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            let newName = "\(base) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)")
            destination = downloadsDirectory.appendingPathComponent(newName)
            counter += 1
        }

        configureDownload(for: destination, response: response)
        completion(.proceed(destination))
    }

    private func presentSavePanel(response: URLResponse, cleanName: String, completion: @escaping (DestinationDecision) -> Void) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = cleanName
        savePanel.allowedContentTypes = download.allowedContentTypes ?? [.data]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        if let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = downloadsDirectory
        }

        DispatchQueue.main.async {
            savePanel.begin { result in
                if result == .OK, let url = savePanel.url {
                    self.configureDownload(for: url, response: response)
                    completion(.proceed(url))
                } else {
                    self.downloadManager?.updateDownloadState(self.download.id, state: .cancelled)
                    completion(.cancel)
                }
            }
        }
    }

    private func configureDownload(for destination: URL, response: URLResponse) {
        let fileSize = response.expectedContentLength
        downloadManager?.updateDownloadProgress(download.id, progress: 0.0, downloadedBytes: 0, fileSize: fileSize)
        downloadManager?.updateDownloadState(download.id, state: .downloading)
        downloadManager?.setDownloadDestination(download.id, destination: destination)
    }

    func download(_: WKDownload, didReceive bytes: UInt64) {
        let downloadedBytes = Int64(bytes)
        let progress = download.fileSize.map { Double(downloadedBytes) / Double($0) } ?? 0.0
        let clampedProgress = min(progress, 1.0)
        downloadManager?.updateDownloadProgress(download.id, progress: clampedProgress, downloadedBytes: downloadedBytes, fileSize: download.fileSize)
    }

    func downloadDidFinish(_: WKDownload) {
        if let destinationURL = download.destinationURL {
            URLSessionDownloadCoordinator.setQuarantineAttribute(on: destinationURL)
        }
        downloadManager?.updateDownloadState(download.id, state: .completed)
    }

    func download(_: WKDownload, didFailWithError error: Error, resumeData _: Data?) {
        downloadManager?.updateDownloadState(download.id, state: .failed, error: error)
    }

    func downloadWillPerformHTTPRedirection(_: WKDownload, navigationResponse _: HTTPURLResponse, newRequest request: URLRequest, decisionHandler: @escaping (URLRequest?) -> Void) {
        decisionHandler(request)
    }

    func download(_: WKDownload, didReceive _: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }
}

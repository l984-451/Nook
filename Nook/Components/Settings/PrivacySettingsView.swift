//
//  PrivacySettingsView.swift
//  Nook
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import SwiftUI
import WebKit

struct PrivacySettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.nookSettings) var nookSettings
    @StateObject private var cookieManager = CookieManager()
    @StateObject private var cacheManager = CacheManager()
    @State private var showingCookieManager = false
    @State private var showingCacheManager = false
    @State private var isClearing = false
    @State private var isUpdatingFilters = false

    var body: some View {
        @Bindable var settings = nookSettings

        return VStack(alignment: .leading, spacing: 20) {
            // Cookie Management Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Cookie Management")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    cookieStatsView
                    
                    HStack {
                        Button("Manage Cookies") {
                            showingCookieManager = true
                        }
                        .buttonStyle(.bordered)
                        
                        Menu("Clear Data") {
                            Button("Clear Expired Cookies") {
                                clearExpiredCookies()
                            }
                            
                            Button("Clear Third-Party Cookies") {
                                clearThirdPartyCookies()
                            }
                            
                            Button("Clear High-Risk Cookies") {
                                clearHighRiskCookies()
                            }
                            
                            Divider()
                            
                            Button("Clear All Cookies") {
                                clearAllCookies()
                            }
                            
                            Button("Privacy Cleanup") {
                                performCookiePrivacyCleanup()
                            }
                            
                            Divider()
                            
                            Button("Clear All Website Data", role: .destructive) {
                                clearAllWebsiteData()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isClearing)
                        
                        if isClearing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Divider()
            
            // Cache Management Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Cache Management")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    cacheStatsView
                    
                    HStack {
                        Button("Manage Cache") {
                            showingCacheManager = true
                        }
                        .buttonStyle(.bordered)
                        
                        Menu("Clear Cache") {
                            Button("Clear Stale Cache") {
                                clearStaleCache()
                            }
                            
                            Button("Clear Personal Data Cache") {
                                clearPersonalDataCache()
                            }
                            
                            Button("Clear Disk Cache") {
                                clearDiskCache()
                            }
                            
                            Button("Clear Memory Cache") {
                                clearMemoryCache()
                            }
                            
                            Divider()
                            
                            Button("Privacy Cleanup") {
                                performCachePrivacyCleanup()
                            }
                            
                            Divider()
                            
                            Button("Clear All Cache", role: .destructive) {
                                clearAllCache()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isClearing)
                        
                        if isClearing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Divider()
            
            // Content Blocking Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Ad & Tracker Blocking")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $settings.adBlockerEnabled) {
                        Text("Ad & Tracker Blocker")
                    }
                    .onChange(of: nookSettings.adBlockerEnabled) { _, enabled in
                        browserManager.contentBlockerManager.setEnabled(enabled)
                    }

                    if nookSettings.adBlockerEnabled {
                        HStack {
                            if isUpdatingFilters {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Updating filter lists...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                if let lastUpdate = nookSettings.adBlockerLastUpdate {
                                    Text("Last updated: \(lastUpdate, style: .relative) ago")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Update Filters") {
                                    isUpdatingFilters = true
                                    Task {
                                        await browserManager.contentBlockerManager.recompileFilterLists()
                                        isUpdatingFilters = false
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }

                    Text("Filter lists update automatically every 24 hours.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Filter list management
                if nookSettings.adBlockerEnabled {
                    filterListManagementSection
                }
            }

            Divider()

            // Privacy Controls Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy Controls")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Block Cross-Site Tracking", isOn: $settings.blockCrossSiteTracking)
                        .onChange(of: nookSettings.blockCrossSiteTracking) { _, enabled in
                            browserManager.contentBlockerManager.setEnabled(enabled)
                        }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Divider()
            
            // Website Data Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Website Data")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    Button("Clear Browsing History") {
                        clearBrowsingHistory()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Clear Cache") {
                        clearCache()
                    }
                    .buttonStyle(.bordered)
                    
                                    }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
        .onAppear {
            Task {
                await cookieManager.loadCookies()
                await cacheManager.loadCacheData()
            }
        }
        .sheet(isPresented: $showingCookieManager) {
            CookieManagementView()
        }
        .sheet(isPresented: $showingCacheManager) {
            CacheManagementView()
        }
    }
    
    // MARK: - Cache Stats View
    
    private var cacheStatsView: some View {
        let stats = cacheManager.getCacheStats()
        
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "internaldrive")
                    .foregroundColor(.blue)
                Text("Stored Cache")
                    .fontWeight(.medium)
                Spacer()
                Text("\(stats.total)")
                    .foregroundColor(.secondary)
            }
            
            if stats.total > 0 {
                HStack {
                    Spacer().frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Disk: \(formatSize(stats.diskSize))")
                            Text("•")
                            Text("Memory: \(formatSize(stats.memorySize))")
                            if stats.staleCount > 0 {
                                Text("•")
                                Text("Stale: \(stats.staleCount)")
                                    .foregroundColor(.orange)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Text("Total size: \(formatSize(stats.totalSize))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Cookie Stats View
    
    private var cookieStatsView: some View {
        let stats = cookieManager.getCookieStats()
        
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.blue)
                Text("Stored Cookies")
                    .fontWeight(.medium)
                Spacer()
                Text("\(stats.total)")
                    .foregroundColor(.secondary)
            }
            
            if stats.total > 0 {
                HStack {
                    Spacer().frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Session: \(stats.session)")
                            Text("•")
                            Text("Persistent: \(stats.persistent)")
                            if stats.expired > 0 {
                                Text("•")
                                Text("Expired: \(stats.expired)")
                                    .foregroundColor(.orange)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Text("Total size: \(formatSize(stats.totalSize))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Filter List Management

    private var filterListManagementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default Filter Lists")
                .font(.subheadline)
                .fontWeight(.medium)

            ForEach(FilterListManager.defaultLists, id: \.filename) { list in
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text(list.name)
                        .font(.caption)
                    Spacer()
                    Text(list.category.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                }
            }

            if !FilterListManager.optionalLists.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                Text("Optional Filter Lists")
                    .font(.subheadline)
                    .fontWeight(.medium)

                ForEach(FilterListManager.FilterListCategory.allCases, id: \.rawValue) { category in
                    let listsInCategory = FilterListManager.optionalLists.filter { $0.category == category }
                    if !listsInCategory.isEmpty {
                        Text(category.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        ForEach(listsInCategory, id: \.filename) { list in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { nookSettings.enabledOptionalFilterLists.contains(list.filename) },
                                    set: { enabled in
                                        if enabled {
                                            nookSettings.enabledOptionalFilterLists.append(list.filename)
                                        } else {
                                            nookSettings.enabledOptionalFilterLists.removeAll { $0 == list.filename }
                                        }
                                        browserManager.contentBlockerManager.filterListManager.enabledOptionalFilterListFilenames = Set(nookSettings.enabledOptionalFilterLists)
                                        Task {
                                            await browserManager.contentBlockerManager.recompileFilterLists()
                                        }
                                    }
                                )) {
                                    Text(list.name)
                                        .font(.caption)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                }

                Text("Enabling additional lists improves blocking but increases memory usage.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Actions
    
    private func clearExpiredCookies() {
        isClearing = true
        Task {
            await cookieManager.deleteExpiredCookies()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearAllCookies() {
        isClearing = true
        Task {
            await cookieManager.deleteAllCookies()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearAllWebsiteData() {
        isClearing = true
        Task {
            let dataStore = WKWebsiteDataStore.default()
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            await dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast)
            await cookieManager.loadCookies()
            await cacheManager.loadCacheData()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearBrowsingHistory() {
        browserManager.historyManager.clearHistory()
    }
    
    private func clearCache() {
        Task {
            let dataStore = WKWebsiteDataStore.default()
            await dataStore.removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache], modifiedSince: Date.distantPast)
        }
    }
    
        
    // MARK: - Helper Methods
    
    // MARK: - Cache Action Methods
    
    private func clearStaleCache() {
        isClearing = true
        Task {
            await cacheManager.clearStaleCache()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearDiskCache() {
        isClearing = true
        Task {
            await cacheManager.clearDiskCache()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearMemoryCache() {
        isClearing = true
        Task {
            await cacheManager.clearMemoryCache()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearAllCache() {
        isClearing = true
        Task {
            await cacheManager.clearAllCache()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    // MARK: - Privacy-Compliant Actions
    
    private func clearThirdPartyCookies() {
        isClearing = true
        Task {
            await cookieManager.deleteThirdPartyCookies()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearHighRiskCookies() {
        isClearing = true
        Task {
            await cookieManager.deleteHighRiskCookies()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func performCookiePrivacyCleanup() {
        isClearing = true
        Task {
            await cookieManager.performPrivacyCleanup()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearPersonalDataCache() {
        isClearing = true
        Task {
            await cacheManager.clearPersonalDataCache()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func performCachePrivacyCleanup() {
        isClearing = true
        Task {
            await cacheManager.performPrivacyCompliantCleanup()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) bytes"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    PrivacySettingsView()
        .environmentObject(BrowserManager())
}

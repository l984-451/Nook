//
//  RedirectResourceManager.swift
//  Nook
//
//  Manages redirect resources for $redirect filter rules. Loads neutered
//  ad-tech script surrogates and empty media files, returns data: URIs
//  for embedding in WKContentRuleList JSON.
//

import Foundation

@MainActor
final class RedirectResourceManager {

    private var resources: [String: (data: Data, mimeType: String)] = [:]

    /// Maps aliases to canonical resource names
    private static let aliasMap: [String: String] = [
        // Google Analytics
        "google-analytics.com/analytics.js": "google-analytics_analytics.js",
        "googletagmanager.com/gtag/js": "google-analytics_analytics.js",
        "google-analytics_analytics.js": "google-analytics_analytics.js",
        "google-analytics.com/ga.js": "google-analytics_ga.js",
        "google-analytics_ga.js": "google-analytics_ga.js",
        "google-analytics.com/cx/api.js": "google-analytics_cx_api.js",
        "google-analytics_cx_api.js": "google-analytics_cx_api.js",
        "google-analytics.com/plugins/ua/inpage_linkid.js": "google-analytics_inpage_linkid.js",
        "google-analytics_inpage_linkid.js": "google-analytics_inpage_linkid.js",
        // Google Ads
        "googlesyndication.com/adsbygoogle.js": "googlesyndication_adsbygoogle.js",
        "googlesyndication_adsbygoogle.js": "googlesyndication_adsbygoogle.js",
        "googletagservices.com/gpt.js": "googletagservices_gpt.js",
        "googletagservices_gpt.js": "googletagservices_gpt.js",
        "doubleclick.net/instream/ad_status.js": "doubleclick_instream_ad_status.js",
        "doubleclick_instream_ad_status.js": "doubleclick_instream_ad_status.js",
        "google-ima.js": "google-ima.js",
        "google-ima3": "google-ima.js",
        // Amazon
        "amazon-adsystem.com/aax2/apstag.js": "amazon_apstag.js",
        "amazon_apstag.js": "amazon_apstag.js",
        "amazon_ads.js": "amazon_ads.js",
        // Others
        "scorecardresearch.com/beacon.js": "scorecardresearch_beacon.js",
        "scorecardresearch_beacon.js": "scorecardresearch_beacon.js",
        "outbrain-widget.js": "outbrain-widget.js",
        "chartbeat.js": "chartbeat.js",
        "hd-main.js": "hd-main.js",
        "prebid-ads.js": "prebid-ads.js",
        "sensors-analytics.js": "sensors-analytics.js",
        "adthrive_abd.js": "adthrive_abd.js",
        "nitropay_ads.js": "nitropay_ads.js",
        // Anti-adblock
        "nobab2.js": "nobab2.js",
        "nobab": "nobab2.js",
        "fingerprint3.js": "fingerprint3.js",
        "fingerprint2.js": "fingerprint3.js",
        "popads.js": "popads.js",
        "popads-dummy": "popads.js",
        "noeval.js": "noeval.js",
        "noeval-silent.js": "noeval-silent.js",
        "ampproject_v0.js": "ampproject_v0.js",
        // Empty/no-op
        "noop.js": "noop.js",
        "noopjs": "noop.js",
        "noop.html": "noop.html",
        "noopframe": "noop.html",
        "noop.txt": "noop.txt",
        "nooptext": "noop.txt",
        "noop.json": "noop.json",
        "1x1.gif": "1x1.gif",
        "1x1-transparent.gif": "1x1.gif",
        "2x2.png": "2x2.png",
        "2x2-transparent.png": "2x2.png",
        "3x2.png": "3x2.png",
        "3x2-transparent.png": "3x2.png",
        "32x32.png": "32x32.png",
        "32x32-transparent.png": "32x32.png",
        "noop-0.1s.mp3": "noop-0.1s.mp3",
        "noopmp3-0.1s": "noop-0.1s.mp3",
        "noop-0.5s.mp3": "noop-0.5s.mp3",
        "noopmp3-0.5s": "noop-0.5s.mp3",
        "noop-1s.mp4": "noop-1s.mp4",
        "noopmp4-1s": "noop-1s.mp4",
        "noop-vast2.xml": "noop-vast2.xml",
        "noop-vast3.xml": "noop-vast3.xml",
        "noop-vast4.xml": "noop-vast4.xml",
        "noop-vmap1.xml": "noop-vmap1.xml",
        "noopvast-2.0": "noop-vast2.xml",
        "noopvast-3.0": "noop-vast3.xml",
        "noopvast-4.0": "noop-vast4.xml",
        "noopvmap-1.0": "noop-vmap1.xml",
        "empty": "empty",
        "click2load.html": "click2load.html",
    ]

    init() {
        loadResources()
    }

    /// Returns a data: URI for the named resource, or nil if not found.
    func dataURL(for name: String) -> String? {
        let canonical = Self.aliasMap[name] ?? name
        guard let resource = resources[canonical] else { return nil }
        let base64 = resource.data.base64EncodedString()
        return "data:\(resource.mimeType);base64,\(base64)"
    }

    /// Check if a resource name is known.
    func hasResource(named name: String) -> Bool {
        let canonical = Self.aliasMap[name] ?? name
        return resources[canonical] != nil
    }

    // MARK: - Private

    private func loadResources() {
        guard let url = Bundle.main.url(forResource: "redirect-resources", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else {
            print("[RedirectResourceManager] Failed to load redirect-resources.json")
            return
        }

        for (name, info) in json {
            guard let content = info["data"],
                  let mimeType = info["mimeType"],
                  let encoding = info["encoding"] else { continue }

            let resourceData: Data
            if encoding == "base64" {
                guard let decoded = Data(base64Encoded: content) else { continue }
                resourceData = decoded
            } else {
                resourceData = Data(content.utf8)
            }

            resources[name] = (data: resourceData, mimeType: mimeType)
        }

        print("[RedirectResourceManager] Loaded \(resources.count) redirect resources")
    }
}

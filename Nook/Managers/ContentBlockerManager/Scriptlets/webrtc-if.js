// webrtc-if.js — Conditional RTCPeerConnection blocking.
// Usage: webrtc-if(urlPattern)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const urlPattern = args[0] || '';

    let urlRe;
    if (urlPattern) {
        try { urlRe = new RegExp(urlPattern); } catch (e) {
            urlRe = { test: (s) => s.includes(urlPattern) };
        }
    }

    if (typeof RTCPeerConnection !== 'undefined') {
        const OrigRTC = RTCPeerConnection;
        window.RTCPeerConnection = function(config) {
            if (urlRe) {
                // Check ICE servers for matching URLs
                const servers = config && config.iceServers;
                if (servers) {
                    for (const server of servers) {
                        const urls = Array.isArray(server.urls) ? server.urls : [server.urls || server.url || ''];
                        for (const u of urls) {
                            if (urlRe.test(String(u))) {
                                throw new DOMException('Blocked by content blocker', 'NotAllowedError');
                            }
                        }
                    }
                }
            } else {
                // No pattern — block all
                throw new DOMException('Blocked by content blocker', 'NotAllowedError');
            }
            return new OrigRTC(config);
        };
        window.RTCPeerConnection.prototype = OrigRTC.prototype;
    }
})();

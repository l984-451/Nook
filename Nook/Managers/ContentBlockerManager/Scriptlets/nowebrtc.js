// nowebrtc.js — Disables WebRTC to prevent IP leaks.
// Usage: nowebrtc()
(function() {
    'use strict';
    const noop = function() {};
    if (typeof RTCPeerConnection !== 'undefined') {
        window.RTCPeerConnection = function() {
            return { close: noop, createDataChannel: () => ({}), createOffer: () => Promise.resolve({}),
                     setLocalDescription: () => Promise.resolve(), addEventListener: noop,
                     removeEventListener: noop, getStats: () => Promise.resolve([]) };
        };
    }
    if (typeof webkitRTCPeerConnection !== 'undefined') {
        window.webkitRTCPeerConnection = window.RTCPeerConnection;
    }
    if (navigator.mediaDevices) {
        navigator.mediaDevices.getUserMedia = () => Promise.reject(new DOMException('Blocked', 'NotAllowedError'));
    }
})();

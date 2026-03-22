// nofab.js — Neutralizes FuckAdBlock scripts.
// Usage: nofab()
(function() {
    'use strict';
    const noop = function() {};
    const noopThis = function() { return this; };
    const Fab = function() {};
    Fab.prototype = {
        check: noop,
        clearEvent: noop,
        emitEvent: noop,
        on: noopThis,
        onDetected: noopThis,
        onNotDetected: noopThis,
    };
    window.FuckAdBlock = window.BlockAdBlock = Fab;
    window.fuckAdBlock = window.blockAdBlock = new Fab();
})();

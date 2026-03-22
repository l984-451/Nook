// nobab.js — Neutralizes BlockAdBlock scripts.
// Usage: nobab()
(function() {
    'use strict';
    const noop = function() {};
    const noopThis = function() { return this; };
    const BlockAdBlock = function() {};
    BlockAdBlock.prototype = {
        bab: false,
        check: noop,
        emitEvent: noop,
        clearEvent: noop,
        on: noopThis,
        onDetected: noopThis,
        onNotDetected: noopThis,
    };
    window.BlockAdBlock = BlockAdBlock;
    window.blockAdBlock = new BlockAdBlock();
    window.sniffAdBlock = new BlockAdBlock();
    window.fuckAdBlock = new BlockAdBlock();
})();

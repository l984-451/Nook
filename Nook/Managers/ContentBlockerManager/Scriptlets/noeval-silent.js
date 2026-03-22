// noeval-silent.js — Replace eval with silent no-op (no console output).
// Usage: noeval-silent()
(function() {
    'use strict';
    window.eval = function() { return undefined; };
})();

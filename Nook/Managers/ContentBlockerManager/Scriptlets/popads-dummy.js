// popads-dummy.js — Neutralizes PopAds/popads.net ad scripts.
// Usage: popads-dummy() or popads.net()
(function() {
    'use strict';
    const noop = function() {};
    window.PopAds = null;
    window.popns = null;
    window.pop_params = null;
    window.pop_config = null;
    window.popad = noop;
    window.popns = noop;
    window.pop_under = noop;
    window.pop_handler = noop;
    window.pop_init = noop;
    Object.defineProperty(window, 'PopAds', { get: () => null, set: noop, configurable: false });
    Object.defineProperty(window, 'popns', { get: () => null, set: noop, configurable: false });
})();

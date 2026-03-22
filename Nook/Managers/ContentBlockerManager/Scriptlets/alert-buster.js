// alert-buster.js — Override alert/confirm/prompt to no-ops.
// Usage: alert-buster()
(function() {
    'use strict';
    window.alert = function() {};
    window.confirm = function() { return false; };
    window.prompt = function() { return null; };
})();

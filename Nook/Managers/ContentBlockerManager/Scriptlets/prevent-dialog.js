// prevent-dialog.js — Override HTMLDialogElement.prototype.showModal/showPopover.
// Usage: prevent-dialog([selector])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const selector = args[0] || '';

    if (typeof HTMLDialogElement !== 'undefined') {
        const origShowModal = HTMLDialogElement.prototype.showModal;
        HTMLDialogElement.prototype.showModal = function() {
            if (selector) {
                try { if (!this.matches(selector)) return origShowModal.apply(this, arguments); } catch (e) {}
            }
            return undefined;
        };

        if (HTMLDialogElement.prototype.show) {
            const origShow = HTMLDialogElement.prototype.show;
            HTMLDialogElement.prototype.show = function() {
                if (selector) {
                    try { if (!this.matches(selector)) return origShow.apply(this, arguments); } catch (e) {}
                }
                return undefined;
            };
        }
    }

    // Also handle showPopover if available
    if (HTMLElement.prototype.showPopover) {
        const origShowPopover = HTMLElement.prototype.showPopover;
        HTMLElement.prototype.showPopover = function() {
            if (selector) {
                try { if (!this.matches(selector)) return origShowPopover.apply(this, arguments); } catch (e) {}
            }
            return undefined;
        };
    }
})();

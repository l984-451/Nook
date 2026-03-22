// prevent-canvas.js — Override toDataURL/getImageData to return randomized/empty data.
// Prevents canvas fingerprinting.
// Usage: prevent-canvas()
(function() {
    'use strict';
    const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
    HTMLCanvasElement.prototype.toDataURL = function() {
        const ctx = this.getContext('2d');
        if (ctx) {
            // Add a tiny invisible noise pixel to randomize the output
            const r = Math.floor(Math.random() * 256);
            const g = Math.floor(Math.random() * 256);
            const b = Math.floor(Math.random() * 256);
            ctx.fillStyle = 'rgba(' + r + ',' + g + ',' + b + ',0.01)';
            ctx.fillRect(0, 0, 1, 1);
        }
        return origToDataURL.apply(this, arguments);
    };

    const origGetImageData = CanvasRenderingContext2D.prototype.getImageData;
    CanvasRenderingContext2D.prototype.getImageData = function() {
        const imageData = origGetImageData.apply(this, arguments);
        // Slightly randomize a few pixels
        for (let i = 0; i < Math.min(imageData.data.length, 16); i += 4) {
            imageData.data[i] = (imageData.data[i] + Math.floor(Math.random() * 3)) & 0xFF;
        }
        return imageData;
    };

    // Also handle toBlob
    const origToBlob = HTMLCanvasElement.prototype.toBlob;
    if (origToBlob) {
        HTMLCanvasElement.prototype.toBlob = function(callback) {
            const ctx = this.getContext('2d');
            if (ctx) {
                const r = Math.floor(Math.random() * 256);
                ctx.fillStyle = 'rgba(' + r + ',0,0,0.01)';
                ctx.fillRect(0, 0, 1, 1);
            }
            return origToBlob.apply(this, arguments);
        };
    }
})();

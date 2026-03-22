// spoof-css.js — Wrap getComputedStyle() to return fake values for specified props.
// Usage: spoof-css(selector, prop, fakeValue)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const selector = args[0] || '';
    const prop = args[1] || '';
    const fakeValue = args[2] || '';
    if (!selector || !prop) return;

    const origGetComputedStyle = window.getComputedStyle;
    window.getComputedStyle = function(element, pseudoElt) {
        const style = origGetComputedStyle.call(this, element, pseudoElt);
        try {
            if (element && element.matches && element.matches(selector)) {
                return new Proxy(style, {
                    get(target, property) {
                        if (property === prop || property === prop.replace(/-([a-z])/g, (_, c) => c.toUpperCase())) {
                            return fakeValue;
                        }
                        const val = Reflect.get(target, property);
                        return typeof val === 'function' ? val.bind(target) : val;
                    }
                });
            }
        } catch (e) {}
        return style;
    };
})();

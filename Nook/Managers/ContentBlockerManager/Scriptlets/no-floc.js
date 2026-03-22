// no-floc.js — Delete FLoC (interestCohort) and Topics API surfaces.
// Usage: no-floc()
(function() {
    'use strict';
    // FLoC
    if (document.interestCohort) {
        try { delete document.interestCohort; } catch (e) {
            Object.defineProperty(document, 'interestCohort', { value: undefined, writable: false, configurable: false });
        }
    }
    // Topics API
    if (document.browsingTopics) {
        try { delete document.browsingTopics; } catch (e) {
            Object.defineProperty(document, 'browsingTopics', { value: undefined, writable: false, configurable: false });
        }
    }
    // Attribution Reporting
    if (document.featurePolicy) {
        try {
            const origAllows = document.featurePolicy.allowsFeature;
            document.featurePolicy.allowsFeature = function(feature) {
                if (feature === 'interest-cohort' || feature === 'browsing-topics' || feature === 'attribution-reporting') {
                    return false;
                }
                return origAllows.call(this, feature);
            };
        } catch (e) {}
    }
})();

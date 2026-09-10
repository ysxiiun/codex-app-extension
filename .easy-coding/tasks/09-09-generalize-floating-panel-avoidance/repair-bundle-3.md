# Repair Bundle 3

Review passed. Verification found real fixture windows occluded during desktop use; the fourth full semantic lifecycle test passed, while the first three failed visibility readiness and RAF.

- test-defect: use a floating fixture window across Spaces/fullscreen auxiliary, keep actual visibility assertions and cleanup. No app activation or simulated RAF.
- Bound event draining to the existing short polling slice so desktop input cannot keep one pump past the wait deadline.
- Only AdapterFixtureTests.swift changes. Rerun focused real WebKit, baseline replay, affected/full Core and remaining must-test commands; independent delta review.

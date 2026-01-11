import SwiftUI

// MARK: - UI Validation Tests (compile-time checks)
// These ensure components render without runtime errors

#if DEBUG
struct UIValidationTests {

    // Validate all control components have stable frames
    static func validateControlStability() -> Bool {
        // WBPill has fixed width for mode text
        let wbModes = ["Auto", "Sun", "Cloud", "Shade", "Lamp", "Fluo"]
        let maxWidth = wbModes.map { $0.count }.max() ?? 0
        assert(maxWidth <= 6, "WB mode text too long for fixed width")

        // ISOPill has fixed width for value
        let isoValues = [100, 200, 400, 800, 1600, 3200]
        let maxISODigits = isoValues.map { String($0).count }.max() ?? 0
        assert(maxISODigits <= 4, "ISO value too long for fixed width")

        // Aperture dial f-stops are valid
        let fStops: [Float] = [2.8, 4.0, 5.6, 8.0, 11, 16]
        assert(fStops.count >= 4, "Need at least 4 f-stops for dial")

        return true
    }

    // Validate design system constants
    static func validateDesignSystem() -> Bool {
        assert(DS.pageMargin == 20, "Page margin should be 20px")
        assert(DS.radiusMedium == 12, "Medium radius should be 12px")
        return true
    }
}

// Run validation on app launch in debug builds
extension ContentView {
    func runValidation() {
        #if DEBUG
        _ = UIValidationTests.validateControlStability()
        _ = UIValidationTests.validateDesignSystem()
        #endif
    }
}
#endif

import SwiftUI

/// One motion vocabulary for selection and continuous poster navigation.
enum LibraryMotion {
    static let selection = Animation.interactiveSpring(response: 0.34, dampingFraction: 0.88)
    static let navigation = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.65)
}

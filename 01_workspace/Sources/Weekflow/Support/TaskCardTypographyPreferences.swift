import CoreGraphics

enum TaskCardTypographyPreferences {
    static let taskTextSizeKey = "weekflow.home.taskTextFontSize"
    static let metadataSizeKey = "weekflow.home.taskMetadataFontSize"
    static let iconSizeKey = "weekflow.home.taskIconSize"

    static let defaultTaskTextSize = 13.0
    static let defaultMetadataSize = 9.0
    static let defaultIconSize = 11.5
    static let completionIconSizeAdjustment: CGFloat = 1.5
    static let taskTextSizeRange = 11.0...15.0
    static let metadataSizeRange = 8.0...11.0
    static let iconSizeRange = 10.0...14.0

    static func taskTextSize(from rawValue: Double) -> CGFloat {
        CGFloat(min(max(rawValue.rounded(), taskTextSizeRange.lowerBound), taskTextSizeRange.upperBound))
    }

    static func metadataSize(from rawValue: Double) -> CGFloat {
        let halfPointValue = (rawValue * 2).rounded() / 2
        return CGFloat(min(max(halfPointValue, metadataSizeRange.lowerBound), metadataSizeRange.upperBound))
    }

    static func iconSize(from rawValue: Double) -> CGFloat {
        let halfPointValue = (rawValue * 2).rounded() / 2
        return CGFloat(min(max(halfPointValue, iconSizeRange.lowerBound), iconSizeRange.upperBound))
    }
}

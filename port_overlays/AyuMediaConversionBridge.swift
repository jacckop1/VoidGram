import Foundation
import CoreGraphics

/// The media picker lives in MediaPickerUI, while the actual Telegram message
/// constructors and chat send logic live in TelegramUI. This bridge keeps the
/// dependency one-way (both modules already depend on TelegramCore).
public enum AyuMediaConversionKind {
    case voice
    case roundVideo
}

/// A unit crop in the video after the track's preferred rotation is applied.
/// The normalized square directly matches the draggable preview on screen.
public struct AyuMediaVideoCrop {
    public let x: CGFloat
    public let y: CGFloat
    public let width: CGFloat
    public let height: CGFloat

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum AyuMediaConversionBridge {
    /// Set when the destination ChatController is visible. The callback
    /// captures that controller weakly; no account/session is retained here.
    public static var send: ((String, AyuMediaConversionKind, AyuMediaVideoCrop?) -> Void)?
}

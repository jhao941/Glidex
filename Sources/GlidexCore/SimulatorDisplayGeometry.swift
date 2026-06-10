import CoreGraphics
import Foundation

public struct DesktopCoordinateSpace: Equatable, Sendable {
    public var mainDisplayHeight: CGFloat

    public init(mainDisplayHeight: CGFloat) {
        self.mainDisplayHeight = mainDisplayHeight
    }

    public func appKitFrame(fromQuartzTopLeft frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX,
            y: mainDisplayHeight - frame.minY - frame.height,
            width: frame.width,
            height: frame.height
        )
    }
}

public struct SimulatorDisplayGeometry: Equatable, Sendable {
    public var desktopFrame: CGRect
    public var simulatorSize: SimulatorPointSize

    public init(desktopFrame: CGRect, nativeSimulatorSize: SimulatorPointSize) {
        self.desktopFrame = desktopFrame
        self.simulatorSize = Self.orientedSize(
            nativeSimulatorSize,
            for: desktopFrame.size
        )
    }

    public var mapper: CoordinateMapper {
        CoordinateMapper(
            captureRect: CGRect(origin: .zero, size: desktopFrame.size),
            simulatorSize: simulatorSize
        )
    }

    public static func orientedSize(
        _ nativeSize: SimulatorPointSize,
        for displaySize: CGSize
    ) -> SimulatorPointSize {
        guard displaySize.width > 0, displaySize.height > 0 else { return nativeSize }
        let displayIsLandscape = displaySize.width > displaySize.height
        let nativeIsLandscape = nativeSize.width > nativeSize.height
        guard displayIsLandscape != nativeIsLandscape else { return nativeSize }
        return SimulatorPointSize(width: nativeSize.height, height: nativeSize.width)
    }
}

public struct OverlayFrameAdjustment: Equatable, Sendable {
    public var originDelta: CGSize
    public var sizeDelta: CGSize

    public init(originDelta: CGSize = .zero, sizeDelta: CGSize = .zero) {
        self.originDelta = originDelta
        self.sizeDelta = sizeDelta
    }

    public init(base: CGRect, adjusted: CGRect) {
        self.init(
            originDelta: CGSize(
                width: adjusted.minX - base.minX,
                height: adjusted.minY - base.minY
            ),
            sizeDelta: CGSize(
                width: adjusted.width - base.width,
                height: adjusted.height - base.height
            )
        )
    }

    public func applying(to frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + originDelta.width,
            y: frame.minY + originDelta.height,
            width: max(1, frame.width + sizeDelta.width),
            height: max(1, frame.height + sizeDelta.height)
        )
    }
}

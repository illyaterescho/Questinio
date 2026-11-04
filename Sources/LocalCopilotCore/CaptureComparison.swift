import CoreGraphics

/// Tells whether two captures of the same area show different content.
public enum CaptureComparison {
    /// A failed comparison counts as different: "visible" is the safe answer for a privacy check.
    public static func differ(_ first: CGImage, _ second: CGImage) -> Bool { changedFraction(first, second) > 0.01 }
    public static func changedFraction(_ first: CGImage, _ second: CGImage) -> Double {
        let width = 256, height = max(1, 256 * first.height / max(1, first.width))
        guard let a = pixels(first, width, height), let b = pixels(second, width, height) else { return 1 }
        var changed = 0
        for index in stride(from: 0, to: a.count, by: 4) where (0..<3).contains(where: { abs(Int(a[index + $0]) - Int(b[index + $0])) > 12 }) { changed += 1 }
        return Double(changed) / Double(width * height)
    }
    private static func pixels(_ image: CGImage, _ width: Int, _ height: Int) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        return drawn ? data : nil
    }
}

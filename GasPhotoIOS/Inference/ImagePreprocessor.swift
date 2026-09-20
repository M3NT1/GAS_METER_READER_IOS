import CoreGraphics
import Foundation

struct FloatTensor: Equatable, Sendable {
    let values: [Float]
    let shape: [Int]
}

enum ImagePreprocessorError: Error, Equatable {
    case invalidImageSize
    case invalidWindowSize
    case failedToCreateContext
}

enum ImagePreprocessor {
    static func detectorTensor(from image: CGImage) throws -> FloatTensor {
        try letterboxedTensor(from: image, targetSize: 960)
    }

    static func classifierTensor(from image: CGImage) throws -> FloatTensor {
        try resizedAndCenterCroppedTensor(from: image, targetSize: 128)
    }

    static func rollerRects(in size: CGSize) throws -> [CGRect] {
        guard size.width >= 8, size.height >= 1 else {
            throw ImagePreprocessorError.invalidWindowSize
        }

        return (0..<8).map { index in
            let left = CGFloat((Double(index) * size.width / 8).rounded())
            let right = CGFloat((Double(index + 1) * size.width / 8).rounded())
            return CGRect(x: left, y: 0, width: right - left, height: size.height)
        }
    }

    private static func letterboxedTensor(from image: CGImage, targetSize: Int) throws -> FloatTensor {
        guard image.width > 0, image.height > 0 else {
            throw ImagePreprocessorError.invalidImageSize
        }

        let pixelCount = targetSize * targetSize
        var pixels = [UInt8](repeating: 0, count: pixelCount * 4)
        guard let context = CGContext(
            data: &pixels,
            width: targetSize,
            height: targetSize,
            bitsPerComponent: 8,
            bytesPerRow: targetSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw ImagePreprocessorError.failedToCreateContext
        }

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
        let scale = min(Double(targetSize) / Double(image.width), Double(targetSize) / Double(image.height))
        let drawSize = CGSize(width: CGFloat(Double(image.width) * scale), height: CGFloat(Double(image.height) * scale))
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(
                x: (CGFloat(targetSize) - drawSize.width) / 2,
                y: (CGFloat(targetSize) - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )
        )

        var values = [Float](repeating: 0, count: pixelCount * 3)
        for pixel in 0..<pixelCount {
            let source = pixel * 4
            values[pixel] = Float(pixels[source]) / 255
            values[pixelCount + pixel] = Float(pixels[source + 1]) / 255
            values[pixelCount * 2 + pixel] = Float(pixels[source + 2]) / 255
        }
        return FloatTensor(values: values, shape: [1, 3, targetSize, targetSize])
    }

    private static func resizedAndCenterCroppedTensor(from image: CGImage, targetSize: Int) throws -> FloatTensor {
        guard image.width > 0, image.height > 0 else {
            throw ImagePreprocessorError.invalidImageSize
        }

        let pixelCount = targetSize * targetSize
        var pixels = [UInt8](repeating: 0, count: pixelCount * 4)
        guard let context = CGContext(
            data: &pixels,
            width: targetSize,
            height: targetSize,
            bitsPerComponent: 8,
            bytesPerRow: targetSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw ImagePreprocessorError.failedToCreateContext
        }

        let scale = max(Double(targetSize) / Double(image.width), Double(targetSize) / Double(image.height))
        let drawWidth = Double(image.width) * scale
        let drawHeight = Double(image.height) * scale
        let drawX = (Double(targetSize) - drawWidth) / 2.0
        let drawY = (Double(targetSize) - drawHeight) / 2.0

        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(
                x: CGFloat(drawX),
                y: CGFloat(drawY),
                width: CGFloat(drawWidth),
                height: CGFloat(drawHeight)
            )
        )

        var values = [Float](repeating: 0, count: pixelCount * 3)
        for pixel in 0..<pixelCount {
            let source = pixel * 4
            values[pixel] = Float(pixels[source]) / 255
            values[pixelCount + pixel] = Float(pixels[source + 1]) / 255
            values[pixelCount * 2 + pixel] = Float(pixels[source + 2]) / 255
        }
        return FloatTensor(values: values, shape: [1, 3, targetSize, targetSize])
    }
}

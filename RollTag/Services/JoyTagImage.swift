import AppKit
import CoreGraphics
import Foundation

enum JoyTagImage {
    static let mean: [Float] = [0.48145466, 0.4578275, 0.40821073]
    static let std: [Float] = [0.26862954, 0.26130258, 0.27577711]

    static func nchwTensor(from jpeg: Data, size: Int = JoyTagStore.imageSize) throws -> Data {
        guard let image = NSImage(data: jpeg), let cgImage = raster(image) else {
            throw AITagError.requestFailed("joytag_decode")
        }
        let width = cgImage.width
        let height = cgImage.height
        let maxDim = max(width, height)
        guard maxDim > 0 else { throw AITagError.requestFailed("joytag_empty") }

        let color = CGColorSpaceCreateDeviceRGB()
        guard let padded = CGContext(
            data: nil,
            width: maxDim,
            height: maxDim,
            bitsPerComponent: 8,
            bytesPerRow: maxDim * 4,
            space: color,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AITagError.requestFailed("joytag_pad")
        }
        padded.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        padded.fill(CGRect(x: 0, y: 0, width: maxDim, height: maxDim))
        let origin = CGPoint(x: (maxDim - width) / 2, y: (maxDim - height) / 2)
        padded.draw(cgImage, in: CGRect(origin: origin, size: CGSize(width: width, height: height)))
        guard let square = padded.makeImage() else { throw AITagError.requestFailed("joytag_square") }

        guard let scaledContext = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: color,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AITagError.requestFailed("joytag_resize")
        }
        scaledContext.interpolationQuality = .high
        scaledContext.draw(square, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let bytes = scaledContext.data else { throw AITagError.requestFailed("joytag_pixels") }

        let count = size * size
        var tensor = [Float](repeating: 0, count: 3 * count)
        let pixels = bytes.bindMemory(to: UInt8.self, capacity: count * 4)
        for i in 0..<count {
            let o = i * 4
            let r = Float(pixels[o]) / 255
            let g = Float(pixels[o + 1]) / 255
            let b = Float(pixels[o + 2]) / 255
            tensor[i] = (r - mean[0]) / std[0]
            tensor[count + i] = (g - mean[1]) / std[1]
            tensor[count * 2 + i] = (b - mean[2]) / std[2]
        }
        return tensor.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func raster(_ image: NSImage) -> CGImage? {
        if let existing = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return existing
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.cgImage
    }
}

import ImageIO
import SwiftUI

struct CoverCropRequest: Identifiable {
  let id = UUID()
  let image: CGImage
  let list: PlaylistKey

  init(url: URL, list: PlaylistKey) throws {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 2048,
    ]
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { throw Issue("This image could not be opened.") }
    self.image = image
    self.list = list
  }

  func rect(zoom: CGFloat, center: CGPoint) -> CGRect {
    let w = CGFloat(image.width), h = CGFloat(image.height)
    let side = max(1, floor(min(w, h) / max(1, zoom)))
    return CGRect(x: round(min(w - side, max(0, center.x - side / 2))),
                  y: round(min(h - side, max(0, center.y - side / 2))), width: side, height: side)
  }

  func cropped(_ rect: CGRect) throws -> CGImage {
    guard let crop = image.cropping(to: rect) else { throw Issue("This image could not be opened.") }
    let side = min(600, crop.width)
    guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw Issue("This image could not be opened.") }
    context.interpolationQuality = .high
    context.draw(crop, in: CGRect(x: 0, y: 0, width: side, height: side))
    guard let result = context.makeImage() else { throw Issue("This image could not be opened.") }
    return result
  }
}

struct CropCoverSheet: View {
  @ObservedObject var s: Session
  let request: CoverCropRequest
  @Environment(\.dismiss) private var dismiss
  @State private var zoom: CGFloat = 1
  @State private var center: CGPoint?
  @GestureState private var drag: CGSize = .zero
  @State private var issue: String?
  private let preview: CGFloat = 288

  var body: some View {
    let middle = center ?? CGPoint(x: CGFloat(request.image.width)/2, y: CGFloat(request.image.height)/2)
    let base = request.rect(zoom: zoom, center: middle)
    let ratio = base.width / preview
    let crop = request.rect(zoom: zoom, center: CGPoint(x: base.midX - drag.width * ratio,
                                                       y: base.midY - drag.height * ratio))
    VStack(alignment: .leading, spacing: 14) {
      Text("Crop cover").font(.title2.bold())
      Text("Drag the image to frame your cover.").foregroundStyle(.secondary)
      Color(white: 0.14).frame(width: preview, height: preview)
        .overlay(alignment: .topLeading) {
          Image(decorative: request.image, scale: 1).resizable()
            .frame(width: CGFloat(request.image.width)/ratio, height: CGFloat(request.image.height)/ratio)
            .offset(x: -crop.minX/ratio, y: -crop.minY/ratio)
        }.clipped().contentShape(Rectangle())
        .gesture(DragGesture().updating($drag) { value, state, _ in state = value.translation }
          .onEnded { value in
            let result = request.rect(zoom: zoom, center: CGPoint(x: base.midX - value.translation.width * ratio,
                                                               y: base.midY - value.translation.height * ratio))
            center = CGPoint(x: result.midX, y: result.midY)
          })
      Slider(value: $zoom, in: 1...4) { Text("Zoom") }
      if let issue { Text(issue).foregroundStyle(.secondary) }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save") {
          do { try s.setCover(request.cropped(crop), for: request.list); dismiss() }
          catch { issue = error.localizedDescription }
        }.keyboardShortcut(.defaultAction)
      }
    }.padding(22).frame(width: preview + 44)
  }
}

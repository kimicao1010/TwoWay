import Foundation
import CoreGraphics
import ImageIO

// 内容包围盒 + 四角圆角检测
guard CommandLine.arguments.count >= 2,
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
      let data = img.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { exit(3) }
let w = img.width, h = img.height, bpr = img.bytesPerRow, bpp = img.bitsPerPixel / 8
func a(_ x: Int, _ y: Int) -> Int { Int(ptr[y * bpr + x * bpp + 3]) }

var top = -1, bottom = -1, left = -1, right = -1
for y in 0..<h where (0..<w).contains(where: { a($0, y) > 8 }) { top = y; break }
for y in stride(from: h - 1, through: 0, by: -1) where (0..<w).contains(where: { a($0, y) > 8 }) { bottom = y; break }
for x in 0..<w where (0..<h).contains(where: { a(x, $0) > 8 }) { left = x; break }
for x in stride(from: w - 1, through: 0, by: -1) where (0..<h).contains(where: { a(x, $0) > 8 }) { right = x; break }

print("图像 \(w)x\(h)")
print("内容 bbox: x[\(left)…\(right)] y[\(top)…\(bottom)]  → 尺寸 \(right-left+1) x \(bottom-top+1)")

func insetAt(_ y: Int, fromLeft: Bool) -> Int {
    if fromLeft { for x in 0..<w where a(x, y) > 8 { return x } }
    else { for x in stride(from: w-1, through: 0, by: -1) where a(x, y) > 8 { return w-1-x } }
    return -1
}
print("\n顶部 3 行的内缩（看上角圆角）：")
for y in top..<(top + 4) { print("  y=\(y)  左缩=\(insetAt(y, fromLeft: true))  右缩=\(insetAt(y, fromLeft: false))") }
print("底部 3 行的内缩（看下角是否方角）：")
for y in stride(from: bottom, to: max(top, bottom - 4), by: -1) {
    print("  y=\(y)  左缩=\(insetAt(y, fromLeft: true))  右缩=\(insetAt(y, fromLeft: false))")
}

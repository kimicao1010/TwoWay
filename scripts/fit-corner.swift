import Foundation
import CoreGraphics
import ImageIO

// 圆角半径拟合：读截图左上角 1px 精度轮廓，用圆方程最小二乘拟合
// 用法: swift scripts/fit-corner.swift <png>
guard CommandLine.arguments.count >= 2,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else {
    print("无法读取"); exit(3)
}
let w = image.width, h = image.height, bpr = image.bytesPerRow, bpp = image.bitsPerPixel / 8
func alphaAt(_ x: Int, _ y: Int) -> Int { Int(ptr[y * bpr + x * bpp + 3]) }

// 实际内容边界（窗口可能比截图矮）
var contentHeight = h
outer: for y in stride(from: h - 1, through: 0, by: -1) {
    for x in stride(from: 0, to: w, by: 4) where alphaAt(x, y) > 8 { contentHeight = y + 1; break outer }
}
var contentWidth = w
outer2: for x in stride(from: w - 1, through: 0, by: -1) {
    for y in stride(from: 0, to: min(contentHeight, h), by: 4) where alphaAt(x, y) > 8 { contentWidth = x + 1; break outer2 }
}
print("实际内容边界：\(contentWidth) x \(contentHeight)")

// 左上角 1px 轮廓：每个 y 的第一个不透明 x
print("\n左上角轮廓：")
var points: [(Int, Int)] = []
for y in 0...30 {
    var firstX = -1
    for x in 0...40 where alphaAt(x, y) > 8 { firstX = x; break }
    if firstX >= 0 {
        points.append((x: firstX, y: y))
        print("  y=\(y)  x=\(firstX)")
    }
}

// 最小二乘拟合 (x - r)² + (y - r)² = r²，即 x² + y² - 2rx - 2ry + r² = 0
// 线性化：令 A = 2x, B = 2y, C = r²；则 r² + ... 非线性。
// 改用代数拟合 (x² + y²) = 2rx + 2ry - r² → 令 c0 = -r², c1 = 2r, c2 = 2r
// 直接网格搜索 r ∈ [5, 40]，取残差最小者
var bestR = -1.0
var bestErr = Double.greatestFiniteMagnitude
var candidates: [(Double, Double)] = []
for r in stride(from: 5.0, through: 40.0, by: 0.25) {
    var err = 0.0
    var n = 0
    for (x, y) in points {
        // 圆心 (r, r)；边界上 y 处的 x = r - sqrt(r² - (r-y)²)
        let dy = Double(r) - Double(y)
        if dy < 0 { continue }
        let root = r * r - dy * dy
        guard root >= 0 else { continue }
        let predicted = r - root.squareRoot()
        err += pow(Double(x) - predicted, 2)
        n += 1
    }
    guard n >= 5 else { continue }
    err /= Double(n)
    if err < bestErr { bestErr = err; bestR = r }
    candidates.append((r, err))
}
print("\n拟合结果：r ≈ \(String(format: "%.2f", bestR)) px  （均方残差 \(String(format: "%.3f", bestErr))）")
print("PRD 目标 12 px → 差 \(String(format: "%.2f", 12.0 - bestR)) px")

// 右上 / 左下 同样测一遍交叉验证
func firstOpaqueXAt(_ y: Int, reversed: Bool) -> Int {
    if reversed {
        for x in stride(from: w - 1, through: w - 45, by: -1) where alphaAt(x, y) > 8 { return w - 1 - x }
    } else {
        for x in 0...40 where alphaAt(x, y) > 8 { return x }
    }
    return -1
}
var topRight: [(Int, Int)] = []
for y in 0...30 {
    let d = firstOpaqueXAt(y, reversed: true)
    if d >= 0 { topRight.append((d, y)) }
}
var bestR2 = -1.0, bestErr2 = Double.greatestFiniteMagnitude
for r in stride(from: 5.0, through: 40.0, by: 0.25) {
    var err = 0.0, n = 0
    for (dx, y) in topRight {
        let dy = Double(r) - Double(y)
        guard dy >= 0 else { continue }
        let root = r * r - dy * dy
        guard root >= 0 else { continue }
        err += pow(Double(dx) - (r - root.squareRoot()), 2)
        n += 1
    }
    guard n >= 5 else { continue }
    err /= Double(n)
    if err < bestErr2 { bestErr2 = err; bestR2 = r }
}
print("右上角交叉验证：r ≈ \(String(format: "%.2f", bestR2)) px（残差 \(String(format: "%.3f", bestErr2))）")

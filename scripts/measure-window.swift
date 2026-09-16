import Foundation
import CoreGraphics
import ImageIO

// C0-3 窗口 spike 测量脚本 v2
// 用法: swift scripts/measure-window.swift <screenshot.png>
//
// v2 改用 **alpha 通道** 判定窗口形状（v1 用底色比对不可靠）：
//   backgroundColor = .clear 且 isOpaque = false 时，窗口圆角外是全透明像素，
//   因此「顶行第一个 alpha>0 的 x」就是圆角半径。

guard CommandLine.arguments.count >= 2 else {
    print("用法: measure-window.swift <png>")
    exit(2)
}
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("无法读取图像"); exit(3)
}

let width = image.width, height = image.height
guard let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else {
    print("无法读取像素"); exit(5)
}
let bytesPerRow = image.bytesPerRow
let bpp = image.bitsPerPixel / 8

print("图像 \(width)x\(height)  bitsPerPixel=\(image.bitsPerPixel)  alphaInfo=\(image.alphaInfo.rawValue)")

func alphaAt(_ x: Int, _ y: Int) -> Int {
    Int(ptr[y * bytesPerRow + x * bpp + 3])
}
func rgbaAt(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
    let o = y * bytesPerRow + x * bpp
    return (Int(ptr[o]), Int(ptr[o+1]), Int(ptr[o+2]), Int(ptr[o+3]))
}

// 顶行 / 左列 / 底行 / 右列：第一个 alpha>0 的位置
func firstOpaqueX(_ y: Int) -> Int {
    for x in 0..<width where alphaAt(x, y) > 8 { return x }
    return -1
}
func firstOpaqueY(_ x: Int) -> Int {
    for y in 0..<height where alphaAt(x, y) > 8 { return y }
    return -1
}

let topRowOpaque = (0..<width).first { alphaAt($0, 0) > 8 } ?? -1
let bottomRowOpaque = (0..<width).first { alphaAt($0, height - 1) > 8 } ?? -1
let leftColOpaque = (0..<height).first { alphaAt(0, $0) > 8 } ?? -1

print("顶行 y=0   第一个不透明 x = \(topRowOpaque) px")
print("左列 x=0   第一个不透明 y = \(leftColOpaque) px")
print("底行 y=H-1 第一个不透明 x = \(bottomRowOpaque) px")

if topRowOpaque > 0 {
    print("→ 顶部圆角半径 ≈ \(topRowOpaque) px（scale 1 时即 pt）")
}
if leftColOpaque > 0 {
    print("→ 左侧圆角半径 ≈ \(leftColOpaque) px")
}

// 四角采样，报告 alpha 值，便于确认形状
let corners = [("左上", 0, 0), ("右上", width - 1, 0), ("左下", 0, height - 1), ("右下", width - 1, height - 1)]
for (name, x, y) in corners {
    let (r, g, b, a) = rgbaAt(x, y)
    print("角 \(name) (\(x),\(y)) rgba=(\(r),\(g),\(b),\(a))")
}

// 采样半径附近几个点的 alpha，画出角部轮廓
print("左上角轮廓（每 2px 采样一次 alpha，直到连续不透明）:")
var line = ""
var y = 0
while y < 40 {
    var x = 0
    var row = ""
    while x < 40 {
        row += alphaAt(x, y) > 8 ? "██" : "··"
        x += 2
    }
    line += String(format: "  y=%02d %@", y, row) + "\n"
    y += 2
}
print(line)

// 交通灯
let targets: [(String, (Int, Int, Int))] = [
    ("close(red)", (0xFF, 0x5F, 0x57)),
    ("min(yellow)", (0xFE, 0xBC, 0x2E)),
    ("zoom(green)", (0x28, 0xC8, 0x40)),
]
for (name, color) in targets {
    var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
    var count = 0
    for y in 0..<min(70, height) {
        for x in 0..<min(140, width) {
            let p = rgbaAt(x, y)
            if abs(p.0 - color.0) < 40 && abs(p.1 - color.1) < 40 && abs(p.2 - color.2) < 40 {
                count += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    if count > 0 {
        print("\(name): 中心 (\((minX+maxX)/2), \((minY+maxY)/2)) pt  直径 ≈ \(maxX - minX) pt  像素数 \(count)")
    } else {
        print("\(name): 未找到（可能处于淡出/失焦态）")
    }
}

let width = 200, height = 120
var bytes: [UInt8] = []
for y in 0..<height { for _ in 0..<width { bytes += y < 60 ? [0,0,255,255] : [255,0,0,255] } }
let image = CGImage(width: width,height: height,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: width*4,
  space: CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
  provider: CGDataProvider(data: Data(bytes) as CFData)!,decode: nil,shouldInterpolate: false,intent: .defaultIntent)!
let pin: [String: Any] = ["id":1,"rect":["left":30,"top":50,"right":130,"bottom":90],"label":"100 × 40 px"]
let png = AnnotationRenderer.png(image: image,annotations: [pin])!

let bitmap = NSBitmapImageRep(data: png)!
let top = bitmap.colorAt(x: 2,y: 2)!.usingColorSpace(.sRGB)!
let bottom = bitmap.colorAt(x: 2,y: bitmap.pixelsHigh-2)!.usingColorSpace(.sRGB)!
precondition(top.blueComponent > 0.9 && top.redComponent < 0.1,"PNG 顶部颜色或方向错误")
precondition(bottom.redComponent > 0.9 && bottom.blueComponent < 0.1,"PNG 底部颜色或方向错误")
precondition(bitmap.pixelsWide <= width && bitmap.pixelsHigh <= height,"PNG 未裁剪")
precondition(AnnotationRenderer.png(image: image,annotations: []) == nil)
precondition(AnnotationRenderer.png(image: image,annotations: [["rect":["left": -1,"top": 0,"right": 5,"bottom": 5]]]) == nil)
print("PNG 原生回归通过：裁剪、方向、sRGB 像素和无效标注；尺寸 \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")

let canvas = NSRect(x: 0,y: 0,width: 200,height: 120)
let firstLabel = AnnotationRenderer.labelFrame(rect: NSRect(x: 30,y: 50,width: 1,height: 1),size: NSSize(width: 100,height: 16),canvas: canvas,occupied: [])
let secondLabel = AnnotationRenderer.labelFrame(rect: NSRect(x: 31,y: 51,width: 20,height: 12),size: NSSize(width: 100,height: 16),canvas: canvas,occupied: [firstLabel])
precondition(!firstLabel.intersects(secondLabel),"相邻标注尺寸标签发生重叠")
precondition(canvas.contains(firstLabel) && canvas.contains(secondLabel),"标签移出了画布")
print("相邻标注尺寸标签错开排布回归通过")

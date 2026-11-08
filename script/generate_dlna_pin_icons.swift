import Cocoa
import CoreText

// 从投屏窗口同源的 CupertinoIcons 字体导出矢量图标，供原生标题栏复用。
// 用法：swift script/generate_dlna_pin_icons.swift <CupertinoIcons.ttf> <Assets.xcassets>
let arguments = CommandLine.arguments
precondition(arguments.count == 3, "Expected font path and asset catalog path")
let fontURL = URL(fileURLWithPath: arguments[1])
let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as! [CTFontDescriptor]
let font = CTFontCreateWithFontDescriptor(descriptors[0], 16, nil)
for (name, codePoint) in [("DlnaPin", UniChar(0xf76b)), ("DlnaPinFilled", UniChar(0xf76c))] {
  var character = codePoint
  var glyph: CGGlyph = 0
  precondition(CTFontGetGlyphsForCharacters(font, &character, &glyph, 1))
  let path = CTFontCreatePathForGlyph(font, glyph, nil)!
  let folder = URL(fileURLWithPath: arguments[2]).appendingPathComponent("\(name).imageset")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  var page = CGRect(x: 0, y: 0, width: 16, height: 16)
  let output = folder.appendingPathComponent("\(name).pdf")
  let context = CGContext(output as CFURL, mediaBox: &page, nil)!
  context.beginPDFPage(nil)
  let bounds = path.boundingBoxOfPath
  context.translateBy(x: (16 - bounds.width) / 2 - bounds.minX,
                      y: (16 - bounds.height) / 2 - bounds.minY)
  context.addPath(path)
  context.setFillColor(CGColor(gray: 0, alpha: 1))
  context.fillPath()
  context.endPDFPage()
  context.closePDF()
  let contents: [String: Any] = [
    "images": [["filename": "\(name).pdf", "idiom": "universal"]],
    "info": ["author": "xcode", "version": 1],
    "properties": ["preserves-vector-representation": true, "template-rendering-intent": "template"]
  ]
  try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: folder.appendingPathComponent("Contents.json"))
}

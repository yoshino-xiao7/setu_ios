import AppKit
let sizes = [(600,800),(800,600),(500,2000),(600,800)]
try FileManager.default.createDirectory(atPath: "/tmp/setu-image-layout-art", withIntermediateDirectories: true)
for (i, dimensions) in sizes.enumerated() {
 let (w,h) = dimensions
 let image = NSImage(size: NSSize(width:w,height:h))
 image.lockFocus()
 let rect = NSRect(x:0,y:0,width:w,height:h)
 NSGradient(starting: NSColor(red:0.35,green:0.38,blue:0.64,alpha:1), ending:NSColor(red:1,green:0.82,blue:0.82,alpha:1))!.draw(in:rect, angle:270)
 NSColor.white.withAlphaComponent(0.8).setFill()
 NSBezierPath(ovalIn:NSRect(x:Double(w)*0.63,y:Double(h)*0.6,width:100,height:100)).fill()
 for n in 0..<4 {
  let path=NSBezierPath(); let y=Double(h)*Double(n+1)/7
  path.move(to:NSPoint(x:0,y:y));path.curve(to:NSPoint(x:Double(w),y:y),controlPoint1:NSPoint(x:Double(w)*0.3,y:y+120),controlPoint2:NSPoint(x:Double(w)*0.6,y:y-90));path.line(to:NSPoint(x:w,y:0));path.line(to:.zero);path.close()
  NSColor(red:0.20+Double(n)*0.1,green:0.25+Double(n)*0.08,blue:0.43+Double(n)*0.06,alpha:0.7).setFill();path.fill()
 }
 image.unlockFocus()
 let data=NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
 try data.write(to:URL(fileURLWithPath:"/tmp/setu-image-layout-art/\(i).png"))
}

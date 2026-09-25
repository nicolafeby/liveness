import Flutter
import MediaPipeTasksVision
import onnxruntime_objc
import UIKit

public class LivenessEdgeFlutterPlugin: NSObject, FlutterPlugin {
  private let queue = DispatchQueue(label: "liveness-edge", qos: .userInitiated)
  private var landmarker: FaceLandmarker?
  private var environment: ORTEnv?
  private var antiSpoof: ORTSession?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "liveness_edge_flutter", binaryMessenger: registrar.messenger())
    let instance = LivenessEdgeFlutterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      queue.async { self.respond(result) { try self.initializeModels(); return nil } }
    case "analyze":
      guard let data = call.arguments as? FlutterStandardTypedData else {
        result(FlutterError(code: "invalid_frame", message: "The frame must be a byte array", details: nil)); return
      }
      queue.async { self.respond(result) { try self.analyze(data.data) } }
    case "close":
      queue.async { self.landmarker = nil; self.antiSpoof = nil; self.environment = nil; DispatchQueue.main.async { result(nil) } }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func respond(_ callback: @escaping FlutterResult, work: () throws -> Any?) {
    do { let value = try work(); DispatchQueue.main.async { callback(value) } }
    catch { DispatchQueue.main.async { callback(FlutterError(code: "edge_error", message: error.localizedDescription, details: nil)) } }
  }

  private func asset(_ name: String, _ ext: String) throws -> String {
    let bundle = Bundle(for: LivenessEdgeFlutterPlugin.self)
    guard let path = bundle.path(forResource: name, ofType: ext) else {
      throw NSError(domain: "LivenessEdge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model \(name).\(ext) was not found"])
    }
    return path
  }

  private func initializeModels() throws {
    if landmarker != nil { return }
    let options = FaceLandmarkerOptions()
    options.baseOptions.modelAssetPath = try asset("face_landmarker", "task")
    options.runningMode = .image
    options.numFaces = 2
    options.outputFaceBlendshapes = true
    landmarker = try FaceLandmarker(options: options)
    let env = try ORTEnv(loggingLevel: .warning)
    environment = env
    antiSpoof = try ORTSession(env: env, modelPath: try asset("minifasnet_v2", "onnx"), sessionOptions: nil)
  }

  private func analyze(_ data: Data) throws -> [String: Any] {
    try initializeModels()
    guard data.count >= 8, String(data: data.prefix(4), encoding: .ascii) == "LVC1" else { throw edge("Invalid frame format") }
    let width = Int(data[4]) << 8 | Int(data[5]); let height = Int(data[6]) << 8 | Int(data[7])
    guard data.count == 8 + width * height * 3 else { throw edge("Invalid frame dimensions") }
    var rgba = [UInt8](repeating: 255, count: width * height * 4)
    data.withUnsafeBytes { raw in
      let source = raw.bindMemory(to: UInt8.self)
      for i in 0..<(width * height) { rgba[i*4]=source[8+i*3+2]; rgba[i*4+1]=source[8+i*3+1]; rgba[i*4+2]=source[8+i*3] }
    }
    let color = CGColorSpaceCreateDeviceRGB()
    guard let provider = CGDataProvider(data: Data(rgba) as CFData), let cg = CGImage(width: width, height: height,
      bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4, space: color,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw edge("The frame could not be read") }
    let detected = try landmarker!.detect(image: MPImage(uiImage: UIImage(cgImage: cg)))
    guard detected.faceLandmarks.count == 1 else { return ["faceCount": detected.faceLandmarks.count] }
    let points = detected.faceLandmarks[0]
    let minX=points.map{$0.x}.min()!, maxX=points.map{$0.x}.max()!, minY=points.map{$0.y}.min()!, maxY=points.map{$0.y}.max()!
    var blend:[String:Float]=[:]
    if let shapes=detected.faceBlendshapes.first?.categories { for item in shapes { blend[item.categoryName ?? ""] = item.score } }
    let eyesDetected=blend["eyeBlinkLeft"] != nil && blend["eyeBlinkRight"] != nil
    let eyesOpen=max(blend["eyeBlinkLeft"] ?? 1, blend["eyeBlinkRight"] ?? 1) < 0.55
    let left=points[33], right=points[263], nose=points[1]; let dx=right.x-left.x, dy=right.y-left.y
    let offset=((nose.x-(left.x+right.x)/2)*dx+(nose.y-(left.y+right.y)/2)*dy)/(dx*dx+dy*dy)
    var output:[String:Any] = ["faceCount":1,"eyesDetected":eyesDetected,"eyesOpen":eyesOpen,"faceCenterX":Double((minX+maxX)/2),
      "faceCenterY":Double((minY+maxY)/2),"faceWidth":Double(maxX-minX),"faceHeight":Double(maxY-minY),
      "yaw":Double(atan2(2*offset,1))*180/Double.pi,"liveScore":try passive(data,width,height,minX,minY,maxX,maxY),
      "faceIdentity":faceIdentity(points)]
    let mean = luminance(data,width,height,minX,minY,maxX,maxY)
    if mean < 55 { output["lighting"]="dark" } else if mean > 205 { output["lighting"]="bright" }
    return output
  }

  private func faceIdentity(_ points: [NormalizedLandmark]) -> [Double] {
    let left=points[33],right=points[263],dx=right.x-left.x,dy=right.y-left.y
    let scale=max(0.0001,sqrt(dx*dx+dy*dy)),angle=atan2(dy,dx),c=cos(angle),s=sin(angle)
    let cx=(left.x+right.x)/2,cy=(left.y+right.y)/2
    // Use rigid face regions across the contour, eyes, brows, and nose. Mouth
    // landmarks are excluded so expression changes do not look like a new face.
    let indices = [
      10, 152, 127, 356, 234, 454, 93, 323, 132, 361,
      33, 133, 159, 145, 263, 362, 386, 374,
      70, 105, 107, 336, 334, 300,
      1, 2, 4, 5, 168, 197, 195, 6
    ]
    return indices.flatMap { index -> [Double] in
      let x=points[index].x-cx,y=points[index].y-cy
      return [Double((x*c+y*s)/scale),Double((-x*s+y*c)/scale)]
    }
  }

  private func luminance(_ data:Data,_ w:Int,_ h:Int,_ x0:Float,_ y0:Float,_ x1:Float,_ y1:Float)->Double {
    var sum=0.0,count=0; data.withUnsafeBytes { raw in let p=raw.bindMemory(to:UInt8.self)
      for y in stride(from:max(0,Int(y0*Float(h))),to:min(h,Int(y1*Float(h))),by:4){for x in stride(from:max(0,Int(x0*Float(w))),to:min(w,Int(x1*Float(w))),by:4){let i=8+(y*w+x)*3;sum += 0.114*Double(p[i])+0.587*Double(p[i+1])+0.299*Double(p[i+2]);count += 1}}}
    return sum/Double(max(1,count))
  }

  private func passive(_ data:Data,_ w:Int,_ h:Int,_ x0:Float,_ y0:Float,_ x1:Float,_ y1:Float)throws->Double {
    let faceW=(x1-x0)*Float(w),faceH=(y1-y0)*Float(h),scale=min(Float(w-1)/faceW,Float(h-1)/faceH,2.7)
    let cropW=max(1,Int(faceW*scale)),cropH=max(1,Int(faceH*scale)),cx=(x0+x1)*Float(w)/2,cy=(y0+y1)*Float(h)/2
    let left=max(0,min(w-1-cropW,Int(cx-Float(cropW)/2))),top=max(0,min(h-1-cropH,Int(cy-Float(cropH)/2)))
    var input=[Float](repeating:0,count:19200);data.withUnsafeBytes{raw in let p=raw.bindMemory(to:UInt8.self)
      for y in 0..<80{for x in 0..<80{let sx=left+x*cropW/80,sy=top+y*cropH/80,i=8+(sy*w+sx)*3,o=y*80+x;input[o]=Float(p[i]);input[6400+o]=Float(p[i+1]);input[12800+o]=Float(p[i+2])}}}
    let tensorData=input.withUnsafeBytes{Data($0)};let value=try ORTValue(tensorData:NSMutableData(data:tensorData),elementType:.float,shape:[1,3,80,80])
    let session=antiSpoof!,inputName=try session.inputNames()[0],outputName=try session.outputNames()[0]
    let outputs=try session.run(withInputs:[inputName:value],outputNames:[outputName],runOptions:nil)
    guard let bytes=try outputs[outputName]?.tensorData() as Data? else { throw edge("The anti-spoofing output is empty") }
    let logits:[Float]=bytes.withUnsafeBytes{Array($0.bindMemory(to:Float.self))};let peak=logits.max() ?? 0;let exps=logits.map{exp(Double($0-peak))}
    return exps[1]/exps.reduce(0,+)
  }

  private func edge(_ message:String)->NSError { NSError(domain:"LivenessEdge",code:2,userInfo:[NSLocalizedDescriptionKey:message]) }
}

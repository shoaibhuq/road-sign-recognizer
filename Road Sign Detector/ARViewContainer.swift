//
//  ARVIew.swift
//  Road Sign Detector
//
//  Created by Jake Spann on 11/13/22.
//

import SwiftUI
import ARKit
import RealityKit
import Combine

struct ARViewContainer: UIViewRepresentable {
    //typealias UIViewControllerType = MyViewController
    
    @ObservedObject var results: ScanResults
    
    func makeUIView(context: Context) -> ARView {
           
           let arView = context.coordinator.arView
           
           let primeAnchor = context.coordinator.primeAnchor
           arView.scene.anchors.append(primeAnchor)
        
        let config = ARWorldTrackingConfiguration()
        
        config.userFaceTrackingEnabled = true
       // let session = ARSession()
        //print(ARWorldTrackingConfiguration.supportedVideoFormats)
        //config.videoFormat = ARConfiguration.supportedVideoFormats
        arView.session.delegate = context.coordinator
        context.coordinator.setupVision()
       arView.session.run(config)
           
        return arView
           
       }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
           Coordinator(arView: ARView(frame: .zero),
                       primeAnchor: AnchorEntity(plane: .horizontal), parent: self, results: results)
       }
       
    class Coordinator: NSObject, ObservableObject, ARSessionDelegate {
           var primeAnchor: AnchorEntity
           var arView: ARView
        private var requests = [VNRequest]()
        var bufferSize: CGSize = .zero
        var speechController = SpeechManger()
        var timer: Timer?
        private var scannedResults: ScanResults
        
        var parent: ARViewContainer
           
           var cancellables = Set<AnyCancellable>()
           
        init(arView: ARView, primeAnchor: AnchorEntity, parent: ARViewContainer, results: ScanResults) {
               self.arView = arView
               self.primeAnchor = primeAnchor
               self.parent = parent
               self.scannedResults = results
               // Assuming you have a Star.reality file in your Resources area
               //let realityFile = Bundle.main.url(forResource: "Star", withExtension: "reality")!
               
               super.init()
           }
           
           func session(_ session: ARSession, didUpdate frame: ARFrame) {
               let exifOrientation = exifOrientationFromDeviceOrientation()
               
               let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: exifOrientation, options: [:])
               do {
                   try imageRequestHandler.perform(self.requests)
               } catch {
                   print(error)
               }
               
               let requestHandler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage)

               // Create a new request to recognize text.
               let request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)
               request.recognitionLevel = .fast

               do {
                   // Perform the text-recognition request.
                //   try requestHandler.perform([request])
               } catch {
                   print("Unable to perform the requests: \(error).")
               }
           }
        
        func recognizeTextHandler(request: VNRequest, error: Error?) {
            guard let observations =
                    request.results as? [VNRecognizedTextObservation] else {
                return
            }
            let recognizedStrings = observations.compactMap { observation in
                // Return the string of the top VNRecognizedText instance.
                return observation.topCandidates(1).first?.string
            }
            
            // Process the recognized strings.
            //processResults(recognizedStrings)
            print(recognizedStrings)
        }
        
        public func exifOrientationFromDeviceOrientation() -> CGImagePropertyOrientation {
            let curDeviceOrientation = UIDevice.current.orientation
            let exifOrientation: CGImagePropertyOrientation
            
            switch curDeviceOrientation {
            case UIDeviceOrientation.portraitUpsideDown:  // Device oriented vertically, home button on the top
                exifOrientation = .left
            case UIDeviceOrientation.landscapeLeft:       // Device oriented horizontally, home button on the right
                exifOrientation = .upMirrored
            case UIDeviceOrientation.landscapeRight:      // Device oriented horizontally, home button on the left
                exifOrientation = .down
            case UIDeviceOrientation.portrait:            // Device oriented vertically, home button on the bottom
                exifOrientation = .up
            default:
                exifOrientation = .up
            }
            return exifOrientation
        }
        
        @discardableResult
        func setupVision() -> NSError? {
            // Setup Vision parts
            let error: NSError! = nil
            
            guard let modelURL = Bundle.main.url(forResource: "SignDetection3 1 Iteration 14220", withExtension: "mlmodelc") else {
                return NSError(domain: "VisionObjectRecognitionViewController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model file is missing"])
            }
            do {
                let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
                let objectRecognition = VNCoreMLRequest(model: visionModel, completionHandler: { (request, error) in
                    DispatchQueue.main.async(execute: {
                        // perform all the UI updates on the main queue
                        if let results = request.results {
                            self.classifyResults(results)
                        }
                    })
                })
                self.requests = [objectRecognition]
            } catch let error as NSError {
                print("Model loading went wrong: \(error)")
            }
            
            return error
        }
        
        func classifyResults(_ results: [Any]) {
            //detectionOverlay.sublayers = nil // remove all the old recognized objects
            for observation in results where observation is VNRecognizedObjectObservation {
                guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                    continue
                }
                // Select only the label with the highest confidence.
                let topLabelObservation = objectObservation.labels[0]
                let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(bufferSize.width), Int(bufferSize.height))
                
                print(topLabelObservation.identifier)
                switch topLabelObservation.identifier {
                case "W11-2":
                    if scannedResults.signType != .pedestrianCrossing {
                        scannedResults.signType = .pedestrianCrossing
                        scannedResults.severity = .warning
                        speechController.speak(text: "Caution, pedestrian crossing ahead", urgency: .warning)
                        //print(parent.results.currentSign?.rawValue)
                    }
                case "R1-1":
                    if scannedResults.signType != .stopSign {
                        scannedResults.signType = .stopSign
                        scannedResults.severity = .warning
                        speechController.speak(text: "Stop sign ahead", urgency: .warning)
                    }
                case "R5-1":
                    if scannedResults.signType != .doNotEnter {
                        scannedResults.signType = .doNotEnter
                        scannedResults.severity = .informative
                        speechController.speak(text: "Do not enter", urgency: .informative)
                    }
                case "R1-2":
                    if scannedResults.signType != .yield {
                        scannedResults.signType = .yield
                        scannedResults.severity = .warning
                        speechController.speak(text: "Caution, yield to oncoming traffic", urgency: .warning)
                    }
                case "R2-140":
                    if scannedResults.signType != .spdlmt40 {
                        scannedResults.signType = .spdlmt40
                        scannedResults.severity = .informative
                        speechController.speak(text: "Speed limit 40 miles per hour", urgency: .informative)
                    }
                case "R2-125":
                    if scannedResults.signType != .speedLimit25 {
                        scannedResults.signType = .speedLimit25
                        scannedResults.severity = .informative
                        speechController.speak(text: "Speed limit 25 miles per hour", urgency: .informative)
                    }
                case "R3-4":
                    if scannedResults.signType != .noUTurn {
                        scannedResults.signType = .noUTurn
                        scannedResults.severity = .informative
                        speechController.speak(text: "No U-Turn ahead", urgency: .informative)
                    }
                case "R6-1":
                    if scannedResults.signType != .oneWay {
                        scannedResults.signType = .oneWay
                        scannedResults.severity = .informative
                        speechController.speak(text: "One Way road", urgency: .informative)
                    }
                default:
                    print(topLabelObservation.identifier)
                }
            }
        }
        
        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            for anchor in anchors {
                guard let faceAnchor = anchor as? ARFaceAnchor else { return }
                let left = faceAnchor.blendShapes[.eyeBlinkLeft]
                let right = faceAnchor.blendShapes[.eyeBlinkRight]
                if timer == nil && ((left?.doubleValue ?? 0.0 >= 0.8) || (right?.doubleValue ?? 0.0 >= 0.8)) {
                    timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false, block: {timer in
                        print("timer expired!!")
                        self.speechController.speak(text: "Drowsiness Detected", urgency: .hazard)
                    })
                    RunLoop.current.add(timer!, forMode: RunLoop.Mode.common)
                } else if (timer != nil) && (left?.doubleValue ?? 1.0 <= 0.8) && (right?.doubleValue ?? 1.0 <= 0.8) {
                    timer?.invalidate()
                    timer = nil
                }
                
            }
        }
        
       }
   }

class ScanResults: ObservableObject {
    @Published var signType: SignType
    @Published var severity: SignSeverity
    
    init(signType: SignType) {
        self.signType = signType
        self.severity = .warning
    }
}

enum SignSeverity {
    case informative
    case warning
    case critical
}

enum SignType: String {
    case pedestrianCrossing = "Pedestrian Crossing"
    case stopSign = "Stop Sign"
    case doNotEnter = "Do Not Enter"
    case yield = "Yield"
    case spdlmt40 = "Speed Limit 40"
    case speedLimit25 = "Speed Limit 25"
    case noUTurn = "No U-Turn"
    case oneWay = "One Way"
    case empty
}

enum SignClass {
    case warning
}

class ScannedResults: ObservableObject, Equatable {
    static func == (lhs: ScannedResults, rhs: ScannedResults) -> Bool {
        return lhs.currentSign == rhs.currentSign
    }
    
    @Published var currentSign: SignType?
    @Published var signName: String?
    @Published var signGlass : SignClass?
}

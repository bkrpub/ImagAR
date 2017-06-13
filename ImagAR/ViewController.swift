//
//  ViewController.swift
//  ImagAR
//
//  Created by Bjoern Kriews on 12/6/17.
//  Copyright © 2017 Bjoern Kriews. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import Vision
import Metal

class ViewController: UIViewController {

    @IBOutlet var sceneView: ARSCNView!
	var shapeLayer : CAShapeLayer = {
		$0.lineWidth = 5
		$0.strokeColor = UIColor.green.cgColor
		$0.fillColor = UIColor.black.withAlphaComponent(0.2).cgColor
		$0.isOpaque = false
		return $0
	}(CAShapeLayer())
	
	var rectangleDetector : CIDetector?
	var frameNumber : Int = 0
	var visionRequestInProgress = false
	
	var lastTime : CFTimeInterval? = nil
	var lastPointsInSceneView : [CGPoint]? = nil
	var lastBoundingBoxInSceneView : CGRect? = nil
	
    override func viewDidLoad() {
        super.viewDidLoad()
        
		setupGestureRecognizers()
		
		sceneView.layer.addSublayer(shapeLayer)
		
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        
		sceneView.debugOptions.insert(ARSCNDebugOptions.showFeaturePoints)
		//sceneView.debugOptions.insert(ARSCNDebugOptions.showWorldOrigin)
		

		let context = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)
		
		print("CIContext:", context)			
		rectangleDetector = CIDetector(ofType: CIDetectorTypeRectangle, context: context, options: nil)
		
        // Create a new scene
        //let scene = SCNScene(named: "art.scnassets/ship.scn")!
        
        // Set the scene to the view
        //sceneView.scene = scene
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingSessionConfiguration()
        
		//configuration.planeDetection = .horizontal
		
		sceneView.session.delegate = self
		
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		shapeLayer.frame = view.layer.bounds
		shapeLayer.path = CGPath(ellipseIn: shapeLayer.bounds, transform: nil)
	}
	
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }

}

/// Gesture Recognition
extension ViewController {
	
	func setupGestureRecognizers() {
		sceneView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
	}
	
	@IBAction func handleTap(_ sender: UITapGestureRecognizer) {
		guard let sceneView = sender.view as? ARSCNView,
			sender.state == .ended 
			else { return }

		let location = sender.location(in: sceneView)
		print("tap", location)
		
		guard let currentFrame = sceneView.session.currentFrame else {
			print("no currentFrame")
			return
		}
		
		
		print("rawPoints", currentFrame.rawFeaturePoints?.count ?? -1)

		/*
		for result in sceneView.hitTest(loc, types: .estimatedHorizontalPlane) {
			print("hit ehp", result.type, result.distance)
		}

		for result in sceneView.hitTest(loc, types: .existingPlane) {
			print("hit epl", result.type, result.distance)
		}

		for result in sceneView.hitTest(loc, types: .existingPlaneUsingExtent) {
			print("hit epu", result.type, result.distance)
		}
		*/

		guard var pointsInSceneView = lastPointsInSceneView else {
			print("no lastPoints")
			return
		}

		guard shapeLayer.path?.contains(location) ?? false else {
			print("tap not in current rect")
			return
		} 

		pointsInSceneView.append(location)
		
		var markerSize = lastBoundingBoxInSceneView!.size
		markerSize.width /= 10000
		markerSize.height = markerSize.width

		
		for point in pointsInSceneView	 {
		
			for result in sceneView.hitTest(point, types: .featurePoint) {
				print("featurePoint", result.type, result.distance)
			
				//let plane = SCNPlane(width: markerSize.width, height: markerSize.height)

				let plane = SCNSphere(radius: markerSize.width)
				
				let color = point == location ? UIColor.magenta : UIColor.cyan	
				
				let markerLayer : CALayer = {
					$0.backgroundColor = color.withAlphaComponent(0.5).cgColor
					$0.borderColor = color.cgColor
					$0.borderWidth = 10
					$0.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
					$0.isOpaque = false
					$0.isDoubleSided = true
					return $0
				}(CALayer())


				
				plane.firstMaterial?.diffuse.contents = markerLayer
				plane.firstMaterial?.lightingModel = .constant
				
				let planeNode = SCNNode(geometry: plane)
				sceneView.scene.rootNode.addChildNode(planeNode)
				
				var translation = matrix_identity_float4x4
				//translation.columns.3.z = 0.1
				planeNode.simdTransform = matrix_multiply(result.worldTransform, translation)
			}
		}

	}
}

extension ViewController : ARSessionDelegate {

	public func session(_ session: ARSession, didUpdate frame: ARFrame) {

		frameNumber = (frameNumber + 1) // % 10
		if /*frameNumber == 0*/ !visionRequestInProgress {
			//print("frame", frameNumber)
			
			let image = CIImage(cvPixelBuffer: frame.capturedImage)
		
			let extent = image.extent
			
			let viewPortSize = shapeLayer.bounds.size
			
			let displayTransform = frame.displayTransform(withViewportSize: viewPortSize, orientation: .portrait)
			
			let flipTransform = CGAffineTransform(translationX: 0, y: 1).scaledBy(x: 1, y: -1)
			
			let toViewPortTransform = CGAffineTransform(scaleX: viewPortSize.width, y: viewPortSize.height)
			
			let normalizedToViewPortTransform = flipTransform.concatenating(displayTransform).concatenating(toViewPortTransform)
			
			func pathForNormalizedRect(_ normalizedRect: CGRect) -> CGPath {
				//let transformedDisplayBounds = normalizedRect.applying(flip).applying(displayTransform)
				//let viewBounds = transformedDisplayBounds.applying(toViewPortTransform)
				//print(extent.size, viewPortSize, "\n\t", normalizedRect, "\n\t", displayTransform, "\n\t", transformedDisplayBounds, "\n\t", viewBounds)

				let viewBounds = normalizedRect.applying(normalizedToViewPortTransform)
				
				return CGPath(rect: viewBounds, transform: nil)
			}

			func pathForNormalizedPoints(_ points: [CGPoint], transform: CGAffineTransform) -> CGPath {
				let path = CGMutablePath()
				path.addLines(between: points, transform: transform)
				path.closeSubpath()
				
				return path
			}

			
			
			#if false
			if let features = rectangleDetector?.features(in: image), features.count > 0 {
				
				shapeLayer.strokeColor = (features.count > 1 ? UIColor.yellow : UIColor.green).cgColor
				
				for (idx, f) in zip(features.indices, features) {
					let normalizedBounds = f.bounds.applying(CGAffineTransform(scaleX: 1 / extent.width, y: 1 / extent.height))
					let transformedDisplayBounds = normalizedBounds.applying(transform)
					let viewBounds = transformedDisplayBounds.applying(CGAffineTransform(scaleX: viewPortSize.width, y: viewPortSize.height))
					
					print(UIApplication.shared.statusBarOrientation, idx, extent.size, viewPortSize, "\n\t", f.bounds, "\n\t", normalizedBounds, "\n\t", transform, "\n\t", transformedDisplayBounds, "\n\t", viewBounds)
					
					shapeLayer.path = CGPath(rect: viewBounds, transform: nil)
				}
			} else {
				shapeLayer.path = CGPath(rect: shapeLayer.bounds, transform: nil)
				shapeLayer.strokeColor = UIColor.brown.cgColor
			}
			#else
				let orientation : CGImagePropertyOrientation = .up
				let handler = VNImageRequestHandler(ciImage: image, orientation: Int32(orientation.rawValue))

				visionRequestInProgress = true

				let rectanglesRequest = VNDetectRectanglesRequest() { (request: VNRequest, error: Error?) in
					
					guard let observations = request.results as? [VNRectangleObservation]
						else { fatalError("unexpected result type from VNDetectRectanglesRequest") }
					
					if observations.isEmpty {
						//print("observe none")
						DispatchQueue.main.async {
							if let lastTime = self.lastTime, CACurrentMediaTime() - lastTime > 1 {
								self.lastTime = nil
								self.lastPointsInSceneView	 = nil
								self.lastBoundingBoxInSceneView = nil
								self.shapeLayer.opacity = 0
								self.shapeLayer.path = nil
							}
						}
					} else {
						//print("observe rectangles")
						for (_, observation) in zip(observations.indices, observations) {
							//print("\t", idx, observation.confidence, observation.boundingBox)
							
							//let path = pathForNormalizedRect(observation.boundingBox)
							
							let pointsInSceneView = [observation.bottomLeft, observation.topLeft, observation.topRight, observation.bottomRight].map {
								$0.applying(normalizedToViewPortTransform)
							}
							
							let path = pathForNormalizedPoints(
								pointsInSceneView,
								transform: CGAffineTransform.identity
							)
							
							
							DispatchQueue.main.async {
								self.lastTime = CACurrentMediaTime()								
								self.lastPointsInSceneView = pointsInSceneView
								self.lastBoundingBoxInSceneView = observation.boundingBox.applying(normalizedToViewPortTransform)

								self.shapeLayer.opacity = 1.0
								self.shapeLayer.strokeColor = UIColor.green.cgColor
								self.shapeLayer.path = path
							}
							
						}
					}
					
					DispatchQueue.main.async { self.visionRequestInProgress = false }
				}
				
				DispatchQueue.global(qos: .userInteractive).async {
					do {
						try handler.perform([rectanglesRequest])
					} catch {
						print("imageRequestError:", error)
						DispatchQueue.main.async { self.visionRequestInProgress = false }
					}
				}
			#endif
		}
		
	}
	
}

extension ViewController : ARSCNViewDelegate {
    
	public func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
		
	}
	
/*
    // Override to create and configure nodes for anchors added to the view's session.
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        let node = SCNNode()
     
        return node
    }
*/
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
}

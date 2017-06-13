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

class ViewController: UIViewController {

    @IBOutlet var sceneView: ARSCNView!

	var shapeLayer : CAShapeLayer = {
		$0.lineWidth = 5
		$0.strokeColor = UIColor.green.cgColor
		$0.fillColor = UIColor.white.withAlphaComponent(0.2).cgColor
		$0.isOpaque = false
		$0.opacity = 0 // changed on detection
		return $0
	}(CAShapeLayer())
	
	var frameNumber : Int64 = 0
	var visionRequestInProgress = false
	
	var lastTime : CFTimeInterval? = nil
	var lastPointsInSceneView : [CGPoint]? = nil
	var lastBoundingBoxInSceneView : CGRect? = nil
	
    override func viewDidLoad() {
        super.viewDidLoad()
        
		setupGestureRecognizers()
		
		sceneView.layer.addSublayer(shapeLayer)
		
        sceneView.delegate = self
        
        sceneView.showsStatistics = true
        
		sceneView.debugOptions.insert(ARSCNDebugOptions.showFeaturePoints)
		//sceneView.debugOptions.insert(ARSCNDebugOptions.showWorldOrigin)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let configuration = ARWorldTrackingSessionConfiguration()
		//configuration.planeDetection = .horizontal
		
		sceneView.session.delegate = self
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

		sceneView.session.pause()
    }
    
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		shapeLayer.frame = view.layer.bounds
	}
	
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
		print("memory warning")
    }

	func makeMarkerLayer(_ color: UIColor = UIColor.red) -> CALayer {
		return {
			$0.backgroundColor = color.withAlphaComponent(0.5).cgColor
			$0.borderColor = color.cgColor
			$0.borderWidth = 10
			$0.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
			$0.isOpaque = false
			$0.isDoubleSided = true
			return $0
			}(CALayer())
	}
	
}

// MARK: Gesture Recognition
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

				let markerGeometry = SCNSphere(radius: markerSize.width)
				
				let color = point == location ? UIColor.magenta : UIColor.cyan	
				
				markerGeometry.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.5)		
				markerGeometry.firstMaterial?.lightingModel = .constant
				
				let markerNode = SCNNode(geometry: markerGeometry)
				sceneView.scene.rootNode.addChildNode(markerNode)
				
				let translation = matrix_identity_float4x4
				//translation.columns.3.z = 0.1
				markerNode.simdTransform = matrix_multiply(result.worldTransform, translation)
			}
		}

	}
}

extension ViewController : ARSessionDelegate {

	public func session(_ session: ARSession, didUpdate frame: ARFrame) {

		frameNumber += 1
		
		if !visionRequestInProgress {
			//print("frame", frameNumber)
			
			let image = CIImage(cvPixelBuffer: frame.capturedImage)
					
			let viewPortSize = shapeLayer.bounds.size
			
			let displayTransform = frame.displayTransform(withViewportSize: viewPortSize, orientation: .portrait)
			
			let flipTransform = CGAffineTransform(translationX: 0, y: 1).scaledBy(x: 1, y: -1)
			
			let toViewPortTransform = CGAffineTransform(scaleX: viewPortSize.width, y: viewPortSize.height)
			
			let normalizedToViewPortTransform = flipTransform.concatenating(displayTransform).concatenating(toViewPortTransform)
			
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
												
						let pointsInSceneView = [observation.bottomLeft, observation.topLeft, observation.topRight, observation.bottomRight].map {
							$0.applying(normalizedToViewPortTransform)
						}
						
						let path = CGMutablePath()
						path.addLines(between: pointsInSceneView)
						path.closeSubpath()
						
						DispatchQueue.main.async {
							self.lastTime = CACurrentMediaTime()								
							self.lastPointsInSceneView = pointsInSceneView
							self.lastBoundingBoxInSceneView = observation.boundingBox.applying(normalizedToViewPortTransform)
							
							self.shapeLayer.opacity = 0.75
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

//
//  ViewController.swift
//  PGH Bus Tracker
//
//  Created by Eric Fang on 4/19/17.
//  Copyright © 2017 Eric Fang. All rights reserved.
//

import UIKit
import GoogleMaps
import Alamofire
import SWXMLHash


class ViewController: UIViewController, GMSMapViewDelegate {

    @IBOutlet weak var mapView: GMSMapView!
    let locationManager = CLLocationManager()
    var currentLocation: CLLocation?
    var firstUpdate = true;
    var busIcons = [String: (UIImage, String)]()
    var routesWithDetails = [String: String]()
    var routes = [String]()
    var visibleMarkers = [String]()
    let topLevel = "http://truetime.portauthority.org/bustime/api/v1/"
    var markers = [String: GMSMarker]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        let routeParams = ["key": Constants.key]
        Alamofire.request(topLevel + "getroutes", parameters: routeParams).response { response in
                let xml = SWXMLHash.parse(response.data!)
                for elem in xml["bustime-response"]["route"].all {
                    self.routesWithDetails[(elem["rt"].element?.text)!] = elem["rtnm"].element?.text
                    self.routes.append((elem["rt"].element?.text)!)
                }
                self.createAllBusIcons()
                self.updateVisibleMarkers()
                self.createMarkers()
        }
        
        Timer.scheduledTimer(withTimeInterval: 2.0,
                                         repeats: true,
                                         block: { timer in
                                            self.updateMarkers()
            }
        )
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
        mapView.delegate = self
    }
    
    func createMarkers() {
        
        let chunkSize = 10
        let chunks: [[String]] = stride(from: 0, to: routes.count, by: chunkSize).map {
            let end = routes.endIndex
            let chunkEnd = routes.index($0, offsetBy: chunkSize, limitedBy: end) ?? end
            return Array(routes[$0..<chunkEnd])
        }
        
        print("chunks: \(chunks.count)")
        
        for chunk in chunks {
            let rt = chunk.joined(separator: ",")
            let vehicleParams = ["key": Constants.key, "rt": rt]
            Alamofire.request(topLevel + "getvehicles", parameters: vehicleParams).response { response in
                let xml = SWXMLHash.parse(response.data!)
                for elem in xml["bustime-response"]["vehicle"].all {
                    let lat = Double((elem["lat"].element?.text)!)
                    let lon = Double((elem["lon"].element?.text)!)
                    let route = (elem["rt"].element?.text)!
                    let marker = GMSMarker(position: CLLocationCoordinate2DMake(lat!, lon!))
                    marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                    marker.title = self.busIcons[route]!.1
                    marker.map = self.mapView
                    marker.icon = self.busIcons[route]!.0
                    marker.snippet = (elem["spd"].element?.text)! + " mph"
                    marker.rotation = Double((elem["hdg"].element?.text)!)! + 90.0
                    self.markers[(elem["vid"].element?.text)!] = marker
                }
            }
        }
    }
    
    func updateVisibleMarkers() {
        var tmpMarkers = [String]()
        for (name, marker) in markers {
            if mapView.projection.contains(marker.position) {
                tmpMarkers.append(name)
            }
        }
        visibleMarkers = tmpMarkers
    }
    
    func updateMarkers() {
        
        let chunkSize = 10
        let chunks: [[String]] = stride(from: 0, to: visibleMarkers.count, by: chunkSize).map {
            let end = visibleMarkers.endIndex
            let chunkEnd = visibleMarkers.index($0, offsetBy: chunkSize, limitedBy: end) ?? end
            return Array(visibleMarkers[$0..<chunkEnd])
        }
        print("chunk count: \(chunks.count)")
        for chunk in chunks {
            let vid = chunk.joined(separator: ",")
            let vehicleParams = ["key": Constants.key, "vid": vid]
            Alamofire.request(topLevel + "getvehicles", parameters: vehicleParams).response { response in
                let xml = SWXMLHash.parse(response.data!)
                for elem in xml["bustime-response"]["vehicle"].all {
                    let lat = Double((elem["lat"].element?.text)!)
                    let lon = Double((elem["lon"].element?.text)!)
                    self.markers[(elem["vid"].element?.text)!]?.position = CLLocationCoordinate2DMake(lat!, lon!)
                    self.markers[(elem["vid"].element?.text)!]?.rotation = Double((elem["hdg"].element?.text)!)! + 90.0
                }
            }
        }
        
    }

    func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
        updateVisibleMarkers()
    }
    
    func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
        mapView.selectedMarker = marker;
        return true;
    }
    
    func createAllBusIcons() {
        let bus = UILabel(frame: CGRect(x: 0, y: 0, width: 30, height: 20))
        bus.backgroundColor = UIColor.blue
        bus.font = UIFont.boldSystemFont(ofSize: 12)
        bus.textColor = UIColor.white
        bus.textAlignment = .center
        bus.layer.cornerRadius = 5
        bus.layer.masksToBounds = true
        bus.layer.borderColor = UIColor.black.cgColor
        bus.layer.borderWidth = 1
        for (name, detail) in self.routesWithDetails {
            bus.text = name
            let value = (bus.asImage(), detail)
            busIcons[name] = value
        }
    }

}

extension UIView {
    
    // Using a function since `var image` might conflict with an existing variable
    // (like on `UIImageView`)
    func asImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { rendererContext in
            layer.render(in: rendererContext.cgContext)
        }
    }
}

extension ViewController: CLLocationManagerDelegate {
    
    // Handle incoming location events.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            if firstUpdate {
                mapView.camera = GMSCameraPosition(target: location.coordinate, zoom: 15, bearing: 0, viewingAngle: 0)
                firstUpdate = false
            }
//            currentMarker!.position = location.coordinate
        }
        
    }
    
    // Handle authorization for the location manager.
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .restricted:
            print("Location access was restricted.")
        case .denied:
            print("User denied access to location.")
            // Display the map using the default location.
            mapView.isHidden = false
        case .notDetermined:
            print("Location status not determined.")
        case .authorizedAlways: fallthrough
        case .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
            mapView.isMyLocationEnabled = true
            mapView.settings.myLocationButton = true
            mapView.settings.compassButton = true
        }
    }
    
    // Handle location manager errors.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationManager.stopUpdatingLocation()
        print("Error: \(error)")
    }
}


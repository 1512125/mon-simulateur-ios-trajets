import MapKit

struct RoadTrip {
    let id = UUID()
    let line: MKPolyline
    let points: [CLLocation]
    private var index = 0
    private var offset = 0.0
    var finished: Bool { index == points.count - 1 }

    init?(_ line: MKPolyline) {
        guard line.pointCount >= 2 else { return nil }
        self.line = line
        self.points = (0..<line.pointCount).map {
            let c = line.points()[$0].coordinate
            return CLLocation(latitude: c.latitude, longitude: c.longitude)
        }
    }

    mutating func advance(meters: Double) -> SelectedCoordinate {
        var remaining = meters
        while !finished {
            let a = points[index], b = points[index + 1]
            let length = a.distance(from: b)
            let available = length - offset
            if remaining >= available {
                remaining -= available
                index += 1
                offset = 0
                continue
            }
            offset += remaining
            let fraction = offset / length
            let start = MKMapPoint(a.coordinate), end = MKMapPoint(b.coordinate)
            let width = MKMapRect.world.size.width
            var dx = end.x - start.x
            if abs(dx) > width / 2 { dx += dx > 0 ? -width : width }
            let x = (start.x + dx * fraction + width).truncatingRemainder(dividingBy: width)
            return SelectedCoordinate(MKMapPoint(x: x, y: start.y + (end.y - start.y) * fraction).coordinate)
        }
        return SelectedCoordinate(points[index].coordinate)
    }
}

extension AppModel {
    func calculateTrip(to destination: SelectedCoordinate) async {
        guard let source = simulatedCoordinate, let sessionID = simulationSessionID,
              source != destination, !areLocationWritesPausedForCellularHandoff,
              routeRequest == nil, trip == nil else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source.coreLocationCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coreLocationCoordinate))
        request.transportType = .automobile
        let directions = MKDirections(request: request)
        routeRequest = directions
        defer { if routeRequest === directions { routeRequest = nil } }
        do {
            let response = try await directions.calculate()
            guard simulationSessionID == sessionID, routeRequest === directions else { return }
            guard let line = response.routes.first?.polyline, let route = RoadTrip(line) else {
                presentError(title: "Trajet indisponible", message: "Aucun itinéraire routier trouvé entre ces points.")
                return
            }
            tripPaused = false
            trip = route
            beginResendLoop(for: sessionID)
        } catch {
            guard simulationSessionID == sessionID, routeRequest === directions else { return }
            presentError(title: "Calcul du trajet impossible", error: error)
        }
    }

    func endTrip() {
        routeRequest?.cancel()
        routeRequest = nil
        trip = nil
        tripPaused = false
    }
}

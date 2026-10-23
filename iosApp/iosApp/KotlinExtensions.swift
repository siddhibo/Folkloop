import CoreLocation
import Shared

// Kotlin models already have a String `id`, so SwiftUI lists can use them directly.
extension TrackingGroup: @retroactive Identifiable {}
extension Geofence: @retroactive Identifiable {}
extension GroupMember: @retroactive Identifiable {}

extension GeoPoint {
    convenience init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

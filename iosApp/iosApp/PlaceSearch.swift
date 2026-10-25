import MapKit
import Observation

struct SelectedPlace {
    let name: String
    let detail: String?
    let coordinate: CLLocationCoordinate2D

    var summary: String {
        guard let detail, !detail.isEmpty, detail != name else { return name }
        return "\(name), \(detail)"
    }
}

@MainActor
@Observable
final class PlaceSearch: NSObject {
    private(set) var suggestions: [MKLocalSearchCompletion] = []
    private(set) var message: String?
    var query = "" {
        didSet { updateSuggestions() }
    }

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func place(for completion: MKLocalSearchCompletion) async -> SelectedPlace? {
        let request = MKLocalSearch.Request(completion: completion)
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else {
                message = "That place couldn't be found. Try a more specific search."
                return nil
            }
            let placemark = item.placemark
            let detail = [placemark.locality, placemark.administrativeArea, placemark.country]
                .compactMap { $0 }
                .joined(separator: ", ")
            return SelectedPlace(name: item.name ?? completion.title, detail: detail, coordinate: placemark.coordinate)
        } catch {
            message = "Place search isn't available right now. Check your connection and try again."
            return nil
        }
    }

    private func updateSuggestions() {
        message = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            completer.cancel()
            suggestions = []
        } else {
            completer.queryFragment = trimmed
        }
    }
}

extension PlaceSearch: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            let results = self.completer.results
            suggestions = results
            message = results.isEmpty ? "No places match \u{201C}\(query)\u{201D}." : nil
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            suggestions = []
            message = "Place search isn't available right now. Check your connection and try again."
        }
    }
}

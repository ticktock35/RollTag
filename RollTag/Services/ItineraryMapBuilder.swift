import Foundation

enum ItineraryMapBuilder {
    static func pins(
        itinerary: ItineraryRecord,
        warehouse: WarehouseRuntime,
        preview: ItineraryGapPreview? = nil
    ) -> [ItineraryMapPin] {
        let members = itinerary.memberIDs.compactMap { warehouse.footageByID[$0] }
        let gpx = fallbackGPX(itinerary: itinerary, warehouse: warehouse)
        let offsets = itinerary.source == .gpx ? warehouse.gpx.offsets : [:]
        return members.compactMap { footage in
            let guess = footage.captureMetadata.hasGPS
                ? nil
                : ItineraryBuilder.placeGuess(
                    for: footage,
                    members: members,
                    offsets: offsets,
                    fallbackGPX: gpx
                )
            guard let coordinate = ItineraryBuilder.mapCoordinate(
                for: footage,
                guess: guess,
                preview: preview
            ) else {
                return nil
            }
            return ItineraryMapPin(
                id: footage.id,
                warehouseID: footage.warehouseID,
                relativePath: footage.relativePath,
                filename: footage.filename,
                mediaKind: footage.mediaKind,
                capturedAt: footage.capturedAt,
                timeText: cheapTimeText(footage.captureMetadata),
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                selected: false,
                guessed: coordinate.guessed
            )
        }
    }

    static func sharedTrack(itinerary: ItineraryRecord, warehouse: WarehouseRuntime) -> GPXTrack? {
        let members = itinerary.memberIDs.compactMap { warehouse.footageByID[$0] }
        return ItineraryBuilder.guessTrack(members: members, fallbackGPX: fallbackGPX(itinerary: itinerary, warehouse: warehouse))
    }

    static func fallbackGPX(itinerary: ItineraryRecord, warehouse: WarehouseRuntime) -> GPXTrack? {
        guard itinerary.source == .gpx, let filename = itinerary.gpxFilename else { return nil }
        return warehouse.gpx.track(named: filename)?.track
    }

    private static func cheapTimeText(_ capture: MediaMetadataSnapshot) -> String? {
        if let local = capture.capturedAtLocal, !local.isEmpty, !capture.capturedAtHasTimeZone {
            return local.replacingOccurrences(of: "T", with: " ")
        }
        return nil
    }
}

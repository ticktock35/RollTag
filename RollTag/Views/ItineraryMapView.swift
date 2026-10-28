import MapKit
import SwiftUI

struct ItineraryMapPin: Identifiable, Equatable, Hashable {
    var id: UUID
    var warehouseID: UUID
    var relativePath: String
    var filename: String
    var mediaKind: MediaKind
    var capturedAt: Date?
    var timeText: String?
    var latitude: Double
    var longitude: Double
    var selected: Bool
    var guessed: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var shortName: String {
        (filename as NSString).deletingPathExtension
    }
}

struct ItineraryMapView: View {
    @Bindable var model: AppModel
    @State private var cameraToken = UUID()
    @State private var cameraRegion: FittedMapRegion?

    var body: some View {
        ZStack(alignment: .top) {
            ItineraryNativeMapView(
                pins: model.itineraryMapPins,
                segments: model.itineraryRouteSegments,
                selectedID: model.focusedFootageID,
                isPinning: model.isPinningItineraryLocation,
                camera: cameraRegion,
                cameraToken: cameraToken,
                warehouseRoot: currentWarehouseRoot,
                onSelect: { model.selectItineraryPin($0) },
                onCamera: { model.rememberItineraryMapRegion($0) },
                onPinAt: { model.placeItineraryLocation(latitude: $0.latitude, longitude: $0.longitude) }
            )

            if model.isPinningItineraryLocation {
                banner(String(localized: "itinerary.pin.hint"))
            } else if model.itineraryMapPins.isEmpty {
                banner(String(localized: "itinerary.map.empty"))
            }
        }
        .onAppear {
            applyRestoredCamera()
        }
        .onDisappear {
            if case .itinerary(let warehouseID, let itineraryID) = model.sidebarSelection {
                model.persistItineraryMapRegion(warehouseID: warehouseID, itineraryID: itineraryID)
            }
        }
        .onChange(of: model.currentItinerary?.id) { _, _ in
            applyRestoredCamera()
        }
        .onChange(of: model.focusedFootageID) { _, id in
            guard let id, let pin = model.itineraryMapPins.first(where: { $0.id == id }) else { return }
            cameraRegion = ItineraryMapCamera.region(focusing: (pin.latitude, pin.longitude))
            cameraToken = UUID()
        }
        .onChange(of: model.itineraryMapFocusToken) { _, _ in
            guard let region = model.itineraryMapFocusRegion else { return }
            cameraRegion = region
            cameraToken = UUID()
        }
    }

    private var currentWarehouseRoot: URL? {
        guard case .itinerary(let warehouseID, _) = model.sidebarSelection else { return nil }
        return model.warehouses.first(where: { $0.id == warehouseID })?.preference.url
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(12)
    }

    private func applyRestoredCamera() {
        let fit = ItineraryMapCamera.region(fitting: model.itineraryFitCoordinates)
        let saved = model.currentItinerary?.savedMapRegion ?? model.itineraryMapRegionDraft
        if let saved, saved.isPlausible(forContent: fit) {
            cameraRegion = saved
        } else {
            cameraRegion = fit
        }
        cameraToken = UUID()
    }
}

private struct ItineraryNativeMapView: NSViewRepresentable {
    var pins: [ItineraryMapPin]
    var segments: [ItineraryRoute.Segment]
    var selectedID: UUID?
    var isPinning: Bool
    var camera: FittedMapRegion?
    var cameraToken: UUID
    var warehouseRoot: URL?
    var onSelect: (UUID) -> Void
    var onCamera: (FittedMapRegion) -> Void
    var onPinAt: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.isPitchEnabled = false
        map.isRotateEnabled = true
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.showsCompass = true
        map.showsScale = true
        map.showsZoomControls = true
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.pinReuse)
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.clusterReuse)
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinOnMap(_:)))
        click.delegate = context.coordinator
        map.addGestureRecognizer(click)
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, NSGestureRecognizerDelegate {
        static let pinReuse = "rolltag.itinerary.pin"
        static let clusterReuse = "rolltag.itinerary.cluster"
        static let navy = NSColor(red: 0.07, green: 0.20, blue: 0.45, alpha: 1)

        var parent: ItineraryNativeMapView
        private var pinSignature = ""
        private var overlaySignature = ""
        private var appliedCameraToken: UUID?
        private var settingRegion = false
        private var selectingProgrammatically = false
        private var lastClustered: Bool?

        init(_ parent: ItineraryNativeMapView) {
            self.parent = parent
        }

        func sync(_ map: MKMapView) {
            let nextPins = signature(for: parent.pins)
            if nextPins != pinSignature {
                pinSignature = nextPins
                let existing = map.annotations.filter { !($0 is MKUserLocation) }
                map.removeAnnotations(existing)
                map.addAnnotations(parent.pins.map(ItineraryPointAnnotation.init))
            }
            let nextOverlays = overlayKey(parent.segments)
            if nextOverlays != overlaySignature {
                overlaySignature = nextOverlays
                map.removeOverlays(map.overlays)
                map.addOverlays(parent.segments.compactMap(Self.polyline(from:)))
            }
            if appliedCameraToken != parent.cameraToken {
                appliedCameraToken = parent.cameraToken
                if let camera = parent.camera, camera.isUsable {
                    settingRegion = true
                    map.setRegion(
                        MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: camera.latitude, longitude: camera.longitude),
                            span: MKCoordinateSpan(
                                latitudeDelta: camera.latitudeDelta,
                                longitudeDelta: camera.longitudeDelta
                            )
                        ),
                        animated: false
                    )
                } else if !parent.pins.isEmpty {
                    settingRegion = true
                    map.showAnnotations(map.annotations.filter { $0 is ItineraryPointAnnotation }, animated: false)
                }
            }
            syncSelection(on: map)
            applyZoomPresentation(map)
        }

        private func syncSelection(on map: MKMapView) {
            let current = (map.selectedAnnotations.first as? ItineraryPointAnnotation)?.footageID
            guard current != parent.selectedID else { return }
            if let id = parent.selectedID,
               let annotation = map.annotations.compactMap({ $0 as? ItineraryPointAnnotation }).first(where: { $0.footageID == id }) {
                selectingProgrammatically = true
                map.selectAnnotation(annotation, animated: true)
            } else if current != nil {
                selectingProgrammatically = true
                map.deselectAnnotation(map.selectedAnnotations.first, animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: Self.clusterReuse,
                    for: annotation
                ) as! MKMarkerAnnotationView
                view.markerTintColor = Self.navy
                view.glyphText = "\(cluster.memberAnnotations.count)"
                view.canShowCallout = false
                view.displayPriority = .required
                view.clusteringIdentifier = nil
                return view
            }
            let pin = annotation as? ItineraryPointAnnotation
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.pinReuse,
                for: annotation
            ) as! MKMarkerAnnotationView
            view.annotation = annotation
            let clustered = ItineraryMapCamera.clustersPins(latitudeDelta: mapView.region.span.latitudeDelta)
            view.markerTintColor = pin?.guessed == true ? .systemOrange : Self.navy
            view.glyphImage = NSImage(
                systemSymbolName: pin?.mediaKind == .video ? "video.fill" : "photo",
                accessibilityDescription: nil
            )
            view.clusteringIdentifier = clustered ? "rolltag.itinerary" : nil
            view.canShowCallout = true
            view.titleVisibility = clustered ? .adaptive : .visible
            view.subtitleVisibility = .adaptive
            view.displayPriority = clustered ? .defaultLow : .required
            view.leftCalloutAccessoryView = nil
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = Self.navy.withAlphaComponent(0.85)
            renderer.lineWidth = 2.4
            renderer.lineDashPattern = [8, 6]
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            applyZoomPresentation(mapView)
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(cluster, animated: false)
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                return
            }
            defer { selectingProgrammatically = false }
            guard let pin = view.annotation as? ItineraryPointAnnotation else { return }
            if !selectingProgrammatically {
                parent.onSelect(pin.footageID)
            }
            attachCallout(for: pin, on: mapView)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            applyZoomPresentation(mapView)
            if settingRegion {
                settingRegion = false
                return
            }
            let region = mapView.region
            parent.onCamera(
                FittedMapRegion(
                    latitude: region.center.latitude,
                    longitude: region.center.longitude,
                    latitudeDelta: region.span.latitudeDelta,
                    longitudeDelta: region.span.longitudeDelta
                )
            )
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
            parent.isPinning
        }

        @objc func pinOnMap(_ gesture: NSClickGestureRecognizer) {
            guard parent.isPinning, let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            parent.onPinAt(map.convert(point, toCoordinateFrom: map))
        }

        private func attachCallout(for pin: ItineraryPointAnnotation, on map: MKMapView) {
            guard pin.mediaKind != .audio, let root = parent.warehouseRoot else { return }
            let footageID = pin.footageID
            let relativePath = pin.relativePath
            let kind = pin.mediaKind
            Task {
                let source = root.appendingPathComponent(relativePath)
                let thumbURL = ThumbnailService.thumbnailFileURL(warehouseRoot: root, footageID: footageID)
                let image: NSImage?
                if kind == .image {
                    image = await ThumbnailService.ensureImageThumbnail(
                        source: source,
                        thumbnailURL: thumbURL,
                        maxEdge: 192,
                        allowCreate: !ThumbnailService.deferGeneration
                    )
                } else {
                    image = await ThumbnailService.ensureVideoThumbnail(
                        source: source,
                        thumbnailURL: thumbURL,
                        maxEdge: 192,
                        allowCreate: !ThumbnailService.deferGeneration
                    )
                }
                await MainActor.run {
                    guard let image,
                          let annotation = map.annotations.compactMap({ $0 as? ItineraryPointAnnotation })
                            .first(where: { $0.footageID == footageID }),
                          let view = map.view(for: annotation)
                    else { return }
                    let preview = NSImageView(image: image)
                    preview.imageScaling = .scaleProportionallyUpOrDown
                    preview.frame = NSRect(x: 0, y: 0, width: 72, height: 54)
                    view.leftCalloutAccessoryView = preview
                }
            }
        }

        private func applyZoomPresentation(_ map: MKMapView) {
            let clustered = ItineraryMapCamera.clustersPins(latitudeDelta: map.region.span.latitudeDelta)
            if let previous = lastClustered, previous != clustered {
                lastClustered = clustered
                let pins = map.annotations.compactMap { $0 as? ItineraryPointAnnotation }
                if !pins.isEmpty {
                    let selected = parent.selectedID
                    map.removeAnnotations(pins)
                    map.addAnnotations(pins)
                    if let selected,
                       let annotation = map.annotations.compactMap({ $0 as? ItineraryPointAnnotation })
                            .first(where: { $0.footageID == selected }) {
                        selectingProgrammatically = true
                        map.selectAnnotation(annotation, animated: false)
                    }
                    return
                }
            }
            lastClustered = clustered
            for annotation in map.annotations {
                guard let pin = annotation as? ItineraryPointAnnotation,
                      let view = map.view(for: pin) as? MKMarkerAnnotationView
                else { continue }
                view.clusteringIdentifier = clustered ? "rolltag.itinerary" : nil
                view.displayPriority = clustered ? .defaultLow : .required
                view.titleVisibility = clustered ? .adaptive : .visible
                if clustered {
                    view.centerOffset = .zero
                }
            }
            if clustered { return }
            spreadStackedPins(on: map)
        }

        private func spreadStackedPins(on map: MKMapView) {
            let pins = map.annotations.compactMap { $0 as? ItineraryPointAnnotation }
            var remaining = pins
            while let pin = remaining.first {
                var group = [pin]
                remaining.removeAll { $0 === pin }
                remaining.removeAll { other in
                    let meters = ItineraryRoute.distanceMeters(
                        from: (pin.coordinate.latitude, pin.coordinate.longitude),
                        to: (other.coordinate.latitude, other.coordinate.longitude)
                    )
                    if meters <= ItineraryMapCamera.stackMeters {
                        group.append(other)
                        return true
                    }
                    return false
                }
                if let selected = group.firstIndex(where: { $0.footageID == parent.selectedID }), selected != 0 {
                    group.swapAt(0, selected)
                }
                let offsets = ItineraryMapCamera.spreadOffsets(count: group.count)
                for (index, member) in group.enumerated() {
                    guard let view = map.view(for: member) else { continue }
                    view.centerOffset = offsets[index]
                    view.zPriority = member.footageID == parent.selectedID
                        ? .defaultSelected
                        : .defaultUnselected
                }
            }
        }

        private func signature(for pins: [ItineraryMapPin]) -> String {
            pins.map { "\($0.id.uuidString):\($0.latitude):\($0.longitude):\($0.guessed)" }.joined(separator: "|")
        }

        private func overlayKey(_ segments: [ItineraryRoute.Segment]) -> String {
            segments.map { segment in
                let first = segment.points.first
                let last = segment.points.last
                return "\(segment.kind.rawValue):\(segment.points.count):\(first?.latitude ?? 0):\(last?.longitude ?? 0)"
            }.joined(separator: "|")
        }

        private static func polyline(from segment: ItineraryRoute.Segment) -> MKPolyline? {
            guard segment.points.count >= 2 else { return nil }
            var coordinates = segment.points.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            return MKPolyline(coordinates: &coordinates, count: coordinates.count)
        }
    }
}

private final class ItineraryPointAnnotation: MKPointAnnotation {
    let footageID: UUID
    let guessed: Bool
    let mediaKind: MediaKind
    let relativePath: String

    init(pin: ItineraryMapPin) {
        footageID = pin.id
        guessed = pin.guessed
        mediaKind = pin.mediaKind
        relativePath = pin.relativePath
        super.init()
        coordinate = pin.coordinate
        title = pin.shortName
        subtitle = pin.timeText
    }
}

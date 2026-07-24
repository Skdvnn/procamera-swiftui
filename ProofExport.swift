import SwiftUI
import UIKit
import MapKit
import Photos
import CoreLocation

// MARK: - Session map helpers

extension ShootSession {
    /// Approximate center from Photos asset locations (nil if none).
    var mapCoordinate: CLLocationCoordinate2D? {
        var lats: [CLLocationDegrees] = []
        var lons: [CLLocationDegrees] = []
        for shot in shots {
            guard let id = shot.photosAssetLocalIdentifier,
                  let asset = PhotosLibraryService.asset(withLocalIdentifier: id),
                  let loc = asset.location else { continue }
            lats.append(loc.coordinate.latitude)
            lons.append(loc.coordinate.longitude)
        }
        guard !lats.isEmpty else { return nil }
        return CLLocationCoordinate2D(
            latitude: lats.reduce(0, +) / Double(lats.count),
            longitude: lons.reduce(0, +) / Double(lons.count)
        )
    }
}

struct SessionMapChip: View {
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))) {
            Marker("Shoot", coordinate: coordinate)
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .allowsHitTesting(false)
    }
}

// MARK: - Proof PDF (contact sheet of keepers)

enum ProofPDFExporter {
    @MainActor
    static func makePDF(
        title: String,
        shots: [ShotMetadata],
        store: GalleryStore
    ) -> URL? {
        guard !shots.isEmpty else { return nil }

        let page = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Shutter-Proof-\(UUID().uuidString.prefix(8)).pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: page)
        do {
            try renderer.writePDF(to: url) { ctx in
                let cols = 3
                let margin: CGFloat = 36
                let gap: CGFloat = 10
                let headerH: CGFloat = 56
                let usableW = page.width - margin * 2
                let cellW = (usableW - gap * CGFloat(cols - 1)) / CGFloat(cols)
                let cellH = cellW * 1.15
                var index = 0

                func newPage() {
                    ctx.beginPage()
                    let titleRect = CGRect(x: margin, y: 28, width: usableW, height: 20)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .bold),
                        .foregroundColor: UIColor.darkGray
                    ]
                    ("SHUTTER · PROOF · " + title.uppercased() as NSString)
                        .draw(in: titleRect, withAttributes: attrs)
                    let sub = "\(shots.count) frames · \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))"
                    (sub as NSString).draw(
                        in: CGRect(x: margin, y: 46, width: usableW, height: 14),
                        withAttributes: [
                            .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                            .foregroundColor: UIColor.gray
                        ]
                    )
                }

                newPage()
                var row = 0
                var col = 0

                for shot in shots {
                    if row > 0 && col == 0 {
                        let y = headerH + margin + CGFloat(row) * (cellH + gap)
                        if y + cellH > page.height - margin {
                            newPage()
                            row = 0
                            col = 0
                        }
                    }

                    let x = margin + CGFloat(col) * (cellW + gap)
                    let y = headerH + margin + CGFloat(row) * (cellH + gap)
                    let rect = CGRect(x: x, y: y, width: cellW, height: cellH - 18)

                    UIColor(white: 0.92, alpha: 1).setFill()
                    UIBezierPath(rect: rect).fill()

                    if let img = store.thumbnail(for: shot) ?? store.image(for: shot) {
                        let fitted = aspectFill(img, in: rect)
                        fitted.draw(in: rect)
                    }

                    let meta = "\(shot.filmFilter) · ISO \(shot.iso) · \(shot.shutter)"
                    (meta as NSString).draw(
                        in: CGRect(x: x, y: y + cellH - 16, width: cellW, height: 14),
                        withAttributes: [
                            .font: UIFont.monospacedSystemFont(ofSize: 7, weight: .medium),
                            .foregroundColor: UIColor.darkGray
                        ]
                    )

                    index += 1
                    col += 1
                    if col >= cols {
                        col = 0
                        row += 1
                    }
                }
            }
            return url
        } catch {
            print("Proof PDF failed: \(error)")
            return nil
        }
    }

    private static func aspectFill(_ image: UIImage, in rect: CGRect) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        return renderer.image { _ in
            let scale = max(rect.width / image.size.width, rect.height / image.size.height)
            let w = image.size.width * scale
            let h = image.size.height * scale
            let origin = CGPoint(x: (rect.width - w) / 2, y: (rect.height - h) / 2)
            image.draw(in: CGRect(origin: origin, size: CGSize(width: w, height: h)))
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

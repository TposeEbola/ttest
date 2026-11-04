import Foundation

extension FloorPlan {
    /// Exports model-space millimetres as a monochrome drawing at 1:50 scale.
    /// SVG retains exact geometry; print at 100% to preserve the stated scale.
    public func svg() throws -> String {
        try validate()

        let margin = 500.0
        let junctions = Geometry.junctionPatches(for: walls)
        var minX = walls.map { min($0.start.x, $0.end.x) - $0.thickness / 2 }.min() ?? 0
        var minY = walls.map { min($0.start.y, $0.end.y) - $0.thickness / 2 }.min() ?? 0
        var maxX = walls.map { max($0.start.x, $0.end.x) + $0.thickness / 2 }.max() ?? 0
        var maxY = walls.map { max($0.start.y, $0.end.y) + $0.thickness / 2 }.max() ?? 0
        for point in junctions.flatMap({ $0 }) {
            minX = min(minX, point.x); minY = min(minY, point.y)
            maxX = max(maxX, point.x); maxY = max(maxY, point.y)
        }
        if walls.isEmpty, let first = dimensions.first {
            minX = first.start.x; maxX = first.start.x
            minY = first.start.y; maxY = first.start.y
        }
        for point in dimensions.flatMap({ [$0.start, $0.end] }) {
            minX = min(minX, point.x); minY = min(minY, point.y)
            maxX = max(maxX, point.x); maxY = max(maxY, point.y)
        }
        if walls.isEmpty, dimensions.isEmpty, let first = areas.first?.vertices.first {
            minX = first.x; maxX = first.x
            minY = first.y; maxY = first.y
        }
        for point in areas.flatMap({ $0.vertices }) {
            minX = min(minX, point.x); minY = min(minY, point.y)
            maxX = max(maxX, point.x); maxY = max(maxY, point.y)
        }
        // Include a conservative bounding circle for each swing, including rotated doors.
        for opening in openings where opening.kind == .door {
            guard let wall = walls.first(where: { $0.id == opening.wallID }) else { continue }
            let hingeDistance = opening.offset + (opening.hingeAtEnd ? 1 : -1) * opening.width / 2
            let wallPoint = wall.point(at: hingeDistance)
            let direction = wall.direction
            let jamb = PlanPoint(x: wallPoint.x - direction.y * wall.thickness / 2,
                                 y: wallPoint.y + direction.x * wall.thickness / 2)
            minX = min(minX, jamb.x - opening.width)
            minY = min(minY, jamb.y - opening.width)
            maxX = max(maxX, jamb.x + opening.width)
            maxY = max(maxY, jamb.y + opening.width)
        }
        let width = maxX - minX + margin * 2
        let height = maxY - minY + margin * 2
        var parts = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(svgNumber(width / 50))mm\" height=\"\(svgNumber(height / 50))mm\" viewBox=\"\(svgNumber(minX - margin)) \(svgNumber(minY - margin)) \(svgNumber(width)) \(svgNumber(height))\">",
            "<title>QuickPlan floor plan</title>",
            "<desc>Wall dimensions are in millimetres. Drawing scale 1:50 when printed at 100 percent.</desc>",
            "<metadata>Model units: mm; drawing scale: 1:50</metadata>",
            "<rect x=\"\(svgNumber(minX - margin))\" y=\"\(svgNumber(minY - margin))\" width=\"\(svgNumber(width))\" height=\"\(svgNumber(height))\" fill=\"white\"/>"
        ]

        if !areas.isEmpty {
            parts.append("<metadata>Area geometry: mm²; area labels: square feet (sq ft)</metadata>")
        }
        // Area fills sit below walls and openings so room overlays never obscure
        // the accurate wall footprint or door/window symbols.
        for area in areas {
            let points = area.vertices.map { "\(svgNumber($0.x)),\(svgNumber($0.y))" }.joined(separator: " ")
            let center = svgAreaCenter(area.vertices)
            let x = svgNumber(center.x)
            let y = svgNumber(center.y)
            let label = svgText(MeasurementUnit.imperial.formatArea(area.areaSquareMillimetres))
            parts.append("<g class=\"room-area\">")
            parts.append("<polygon class=\"area-boundary\" points=\"\(points)\" fill=\"black\" fill-opacity=\"0.035\" stroke=\"black\" stroke-width=\"5\"/>")
            parts.append("<text class=\"area-label\" x=\"\(x)\" y=\"\(y)\" text-anchor=\"middle\" font-family=\"Helvetica,Arial,sans-serif\" font-size=\"80\" fill=\"black\" stroke=\"white\" stroke-width=\"12\" paint-order=\"stroke\"><tspan x=\"\(x)\" dy=\"-45\" font-weight=\"600\">\(svgText(area.name))</tspan><tspan x=\"\(x)\" dy=\"100\" font-size=\"75\">\(label)</tspan></text>")
            parts.append("</g>")
        }

        // Draw all walls before cutting openings, so a joined wall cannot cover a symbol.
        for wall in walls {
            parts.append("<line class=\"wall\" x1=\"\(svgNumber(wall.start.x))\" y1=\"\(svgNumber(wall.start.y))\" x2=\"\(svgNumber(wall.end.x))\" y2=\"\(svgNumber(wall.end.y))\" stroke=\"black\" stroke-width=\"\(svgNumber(wall.thickness))\" stroke-linecap=\"butt\"/>")
        }
        for polygon in junctions {
            let points = polygon.map { "\(svgNumber($0.x)),\(svgNumber($0.y))" }.joined(separator: " ")
            parts.append("<polygon class=\"wall-junction\" points=\"\(points)\" fill=\"black\"/>")
        }

        for opening in openings {
            guard let wall = walls.first(where: { $0.id == opening.wallID }) else { continue }
            let angle = atan2(wall.end.y - wall.start.y, wall.end.x - wall.start.x) * 180 / .pi
            let jamb = wall.point(at: opening.offset - opening.width / 2)
            let w = svgNumber(opening.width)
            parts.append("<g class=\"\(opening.kind.rawValue)\" transform=\"translate(\(svgNumber(jamb.x)) \(svgNumber(jamb.y))) rotate(\(svgNumber(angle)))\">")
            parts.append("<line class=\"opening-cutout\" x1=\"0\" y1=\"0\" x2=\"\(w)\" y2=\"0\" stroke=\"white\" stroke-width=\"\(svgNumber(wall.thickness + 2))\" stroke-linecap=\"butt\"/>")
            switch opening.kind {
            case .door:
                let hingeX = opening.hingeAtEnd ? opening.width : 0
                let baseDegrees = opening.hingeAtEnd ? 180.0 : 0
                let radians = (baseDegrees + opening.doorSwingDegrees) * .pi / 180
                let tipX = opening.width * cos(radians)
                let tipY = opening.width * sin(radians)
                let closedX = opening.hingeAtEnd ? -opening.width : opening.width
                var path = "M 0 0 L \(svgNumber(tipX)) \(svgNumber(tipY))"
                if opening.doorSwingDegrees != 0 {
                    let sweep = opening.doorSwingDegrees > 0 ? 1 : 0
                    path += " M \(svgNumber(closedX)) 0 A \(w) \(w) 0 0 \(sweep) \(svgNumber(tipX)) \(svgNumber(tipY))"
                }
                parts.append("<path class=\"door-leaf\" transform=\"translate(\(svgNumber(hingeX)) \(svgNumber(wall.thickness / 2)))\" d=\"\(path)\" stroke=\"black\" stroke-width=\"10\" fill=\"none\"/>")
            case .window:
                let separation = svgNumber(wall.thickness * 0.22)
                parts.append("<path d=\"M 0 -\(separation) H \(w) M 0 \(separation) H \(w) M 0 -\(svgNumber(wall.thickness / 2)) V \(svgNumber(wall.thickness / 2)) M \(w) -\(svgNumber(wall.thickness / 2)) V \(svgNumber(wall.thickness / 2))\" stroke=\"black\" stroke-width=\"10\" fill=\"none\"/>")
            }
            parts.append("</g>")
        }

        for wall in walls {
            let ux = (wall.end.x - wall.start.x) / wall.length
            let uy = (wall.end.y - wall.start.y) / wall.length
            let offset = wall.thickness / 2 + 150
            let ax = wall.start.x - uy * offset
            let ay = wall.start.y + ux * offset
            let bx = wall.end.x - uy * offset
            let by = wall.end.y + ux * offset
            let mx = (ax + bx) / 2
            let my = (ay + by) / 2
            var angle = atan2(uy, ux) * 180 / .pi
            if angle > 90 { angle -= 180 }
            if angle < -90 { angle += 180 }
            let tick = 35.0
            parts.append("<g class=\"dimension\" stroke=\"black\" stroke-width=\"5\" fill=\"none\">")
            parts.append("<path d=\"M \(svgNumber(ax)) \(svgNumber(ay)) L \(svgNumber(bx)) \(svgNumber(by)) M \(svgNumber(ax + uy * tick)) \(svgNumber(ay - ux * tick)) L \(svgNumber(ax - uy * tick)) \(svgNumber(ay + ux * tick)) M \(svgNumber(bx + uy * tick)) \(svgNumber(by - ux * tick)) L \(svgNumber(bx - uy * tick)) \(svgNumber(by + ux * tick))\"/>")
            parts.append("</g>")
            parts.append("<text class=\"dimension-label\" transform=\"translate(\(svgNumber(mx)) \(svgNumber(my))) rotate(\(svgNumber(angle)))\" y=\"-25\" text-anchor=\"middle\" font-family=\"Helvetica,Arial,sans-serif\" font-size=\"80\" fill=\"black\" stroke=\"white\" stroke-width=\"12\" paint-order=\"stroke\">\(svgNumber(wall.length)) mm</text>")
        }
        for measurement in dimensions {
            let start = measurement.start
            let end = measurement.end
            let ux = (end.x - start.x) / measurement.length
            let uy = (end.y - start.y) / measurement.length
            let tick = 45.0
            var angle = atan2(uy, ux) * 180 / .pi
            if angle > 90 { angle -= 180 }
            if angle < -90 { angle += 180 }
            parts.append("<g class=\"measurement\" stroke=\"black\" stroke-width=\"7\" fill=\"none\">")
            parts.append("<path d=\"M \(svgNumber(start.x)) \(svgNumber(start.y)) L \(svgNumber(end.x)) \(svgNumber(end.y)) M \(svgNumber(start.x + uy * tick)) \(svgNumber(start.y - ux * tick)) L \(svgNumber(start.x - uy * tick)) \(svgNumber(start.y + ux * tick)) M \(svgNumber(end.x + uy * tick)) \(svgNumber(end.y - ux * tick)) L \(svgNumber(end.x - uy * tick)) \(svgNumber(end.y + ux * tick))\"/>")
            parts.append("</g>")
            parts.append("<text class=\"measurement-label\" transform=\"translate(\(svgNumber((start.x + end.x) / 2)) \(svgNumber((start.y + end.y) / 2))) rotate(\(svgNumber(angle)))\" y=\"-25\" text-anchor=\"middle\" font-family=\"Helvetica,Arial,sans-serif\" font-size=\"80\" fill=\"black\" stroke=\"white\" stroke-width=\"12\" paint-order=\"stroke\">\(svgNumber(measurement.length)) mm</text>")
        }
        parts.append("</svg>")
        return parts.joined(separator: "\n")
    }
}

private func svgNumber(_ value: Double) -> String {
    // A fixed locale keeps XML numeric syntax independent of the user's region.
    let normalized = abs(value) < 0.000_000_5 ? 0 : value
    let text = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), normalized)
    return text.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
}

private func svgAreaCenter(_ vertices: [PlanPoint]) -> PlanPoint {
    guard let origin = vertices.first else { return PlanPoint(x: 0, y: 0) }
    var twiceArea = 0.0
    var weightedX = 0.0
    var weightedY = 0.0
    for (start, end) in zip(vertices, vertices.dropFirst() + [origin]) {
        // Work relative to one vertex to retain precision at distant origins.
        let ax = start.x - origin.x, ay = start.y - origin.y
        let bx = end.x - origin.x, by = end.y - origin.y
        let cross = ax * by - bx * ay
        twiceArea += cross
        weightedX += (ax + bx) * cross
        weightedY += (ay + by) * cross
    }
    guard twiceArea.isFinite, abs(twiceArea) > 0.000_001 else { return origin }
    return PlanPoint(x: origin.x + weightedX / (3 * twiceArea),
                     y: origin.y + weightedY / (3 * twiceArea))
}

private func svgText(_ text: String) -> String {
    // XML 1.0 cannot represent control characters such as NUL, even as numeric
    // references. Keep valid Unicode and escape every markup delimiter.
    let validScalars = text.unicodeScalars.filter {
        $0.value == 0x9 || $0.value == 0xA || $0.value == 0xD
            || (0x20...0xD7FF).contains($0.value)
            || (0xE000...0xFFFD).contains($0.value)
            || (0x10000...0x10FFFF).contains($0.value)
    }
    return String(String.UnicodeScalarView(validScalars))
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

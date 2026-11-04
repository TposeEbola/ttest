import Foundation

/// A symbol's coordinates are centered on the item's origin and normalized to
/// its width and depth. Keeping this geometry shared makes the canvas and SVG
/// export show the same measured, rotatable object.
public enum ItemPrimitive: Equatable, Sendable {
    case polyline(points: [PlanPoint], closed: Bool)
    case ellipse(center: PlanPoint, width: Double, depth: Double)
}

public enum ItemSymbols {
    public static func primitives(for kind: PlanItemKind) -> [ItemPrimitive] {
        switch kind {
        case .bed:
            return [rectangle(-0.5, -0.5, 0.5, 0.5),
                    rectangle(-0.44, -0.43, -0.04, -0.22),
                    rectangle(0.04, -0.43, 0.44, -0.22),
                    line([(-0.5, -0.14), (0.5, -0.14)]),
                    line([(-0.5, -0.08), (0.5, -0.08)])]
        case .nightstand:
            return [rectangle(-0.5, -0.5, 0.5, 0.5),
                    rectangle(-0.42, -0.42, 0.42, 0.42),
                    line([(-0.12, 0.3), (0.12, 0.3)])]
        case .dresser:
            return [rectangle(-0.5, -0.5, 0.5, 0.5),
                    line([(-0.5, -0.16), (0.5, -0.16)]),
                    line([(-0.5, 0.17), (0.5, 0.17)]),
                    line([(-0.1, -0.33), (0.1, -0.33)]),
                    line([(-0.1, 0), (0.1, 0)]),
                    line([(-0.1, 0.34), (0.1, 0.34)])]
        case .wardrobe:
            return [rectangle(-0.5, -0.5, 0.5, 0.5),
                    line([(0, -0.5), (0, 0.5)]),
                    line([(-0.06, -0.08), (-0.06, 0.08)]),
                    line([(0.06, -0.08), (0.06, 0.08)]),
                    line([(-0.4, -0.38), (0.4, -0.38)])]
        case .toilet:
            return [rectangle(-0.4, -0.5, 0.4, -0.24),
                    oval(0, 0.12, 0.76, 0.76),
                    oval(0, 0.13, 0.48, 0.51),
                    line([(0.18, -0.37), (0.3, -0.37)])]
        case .bathSink:
            return [rectangle(-0.5, -0.5, 0.5, 0.5),
                    oval(0, 0.08, 0.76, 0.64),
                    oval(0, 0.13, 0.06, 0.06),
                    line([(0, -0.36), (0, -0.17)]),
                    oval(-0.16, -0.34, 0.08, 0.08),
                    oval(0.16, -0.34, 0.08, 0.08)]
        case .bathtub:
            return [rectangle(-0.5, -0.5, 0.5, 0.5),
                    oval(0, 0, 0.8, 0.9),
                    oval(0, -0.3, 0.07, 0.04),
                    line([(0, -0.48), (0, -0.36)])]
        case .shower:
            return [rectangle(-0.5, -0.5, 0.5, 0.5),
                    line([(-0.5, -0.5), (0.5, 0.5)]),
                    line([(0.5, -0.5), (-0.5, 0.5)]),
                    oval(0, 0, 0.13, 0.13),
                    line([(-0.2, -0.42), (0.2, -0.42)])]
        case .storage:
            return [rectangle(-0.5, -0.5, 0.5, 0.5),
                    line([(-0.5, -0.5), (0.5, 0.5)]),
                    line([(0.5, -0.5), (-0.5, 0.5)])]
        case .plant:
            var result: [ItemPrimitive] = [oval(0, 0, 0.44, 0.44)]
            for index in 0..<8 {
                let angle = Double(index) * .pi / 4
                let center = polar(radius: 0.29, angle: angle)
                result.append(oval(center.x, center.y, 0.28, 0.28))
            }
            return result
        case .rug:
            var result = [rectangle(-0.42, -0.5, 0.42, 0.5),
                          rectangle(-0.34, -0.42, 0.34, 0.42)]
            for index in 0..<11 {
                let y = -0.45 + Double(index) * 0.09
                result += [line([(-0.5, y), (-0.42, y)]), line([(0.42, y), (0.5, y)])]
            }
            return result
        case .car:
            return [line([(-0.3, -0.5), (0.3, -0.5), (0.4, -0.38), (0.4, 0.4),
                          (0.3, 0.5), (-0.3, 0.5), (-0.4, 0.4), (-0.4, -0.38)], closed: true),
                    line([(-0.32, -0.25), (0.32, -0.25), (0.27, -0.07), (-0.27, -0.07)], closed: true),
                    rectangle(-0.27, 0, 0.27, 0.24),
                    line([(-0.32, 0.3), (0.32, 0.3)]),
                    rectangle(-0.5, -0.31, -0.4, -0.11),
                    rectangle(0.4, -0.31, 0.5, -0.11),
                    rectangle(-0.5, 0.17, -0.4, 0.37),
                    rectangle(0.4, 0.17, 0.5, 0.37)]
        case .kitchenSink:
            return [rectangle(-0.5, -0.5, 0.5, 0.5),
                    rectangle(-0.43, -0.24, -0.03, 0.39),
                    rectangle(0.03, -0.24, 0.43, 0.39),
                    oval(-0.23, 0.08, 0.06, 0.08),
                    oval(0.23, 0.08, 0.06, 0.08),
                    line([(0, -0.41), (0, -0.12)])]
        case .stove:
            return [rectangle(-0.5, -0.5, 0.5, 0.5),
                    line([(-0.5, -0.33), (0.5, -0.33)]),
                    oval(-0.23, -0.09, 0.29, 0.29), oval(0.23, -0.09, 0.29, 0.29),
                    oval(-0.23, 0.28, 0.29, 0.29), oval(0.23, 0.28, 0.29, 0.29),
                    oval(-0.26, -0.41, 0.07, 0.07), oval(0, -0.41, 0.07, 0.07),
                    oval(0.26, -0.41, 0.07, 0.07)]
        case .refrigerator:
            return [rectangle(-0.5, -0.5, 0.5, 0.5),
                    line([(-0.5, -0.16), (0.5, -0.16)]),
                    line([(-0.36, -0.4), (-0.36, -0.25)]),
                    line([(-0.36, -0.03), (-0.36, 0.22)])]
        case .counter:
            return [rectangle(-0.5, -0.5, 0.5, 0.5),
                    line([(-0.5, -0.4), (0.5, -0.4)]),
                    line([(-0.5, 0.4), (0.5, 0.4)])]
        case .diningTable:
            return tableWithLegs(inset: 0.13)
        case .person, .child:
            return [oval(0, -0.22, 0.36, 0.36),
                    oval(0, 0.12, 0.82, 0.35),
                    line([(-0.14, 0.21), (-0.14, 0.43)]),
                    line([(0.14, 0.21), (0.14, 0.43)])]
        case .wheelchair:
            return [oval(-0.4, 0.12, 0.2, 0.62), oval(0.4, 0.12, 0.2, 0.62),
                    rectangle(-0.25, -0.08, 0.25, 0.29),
                    line([(-0.28, -0.18), (0.28, -0.18)]),
                    oval(0, -0.33, 0.28, 0.28),
                    line([(-0.12, 0.29), (-0.12, 0.47), (0.12, 0.47), (0.12, 0.29)])]
        case .ceilingLight:
            return [oval(0, 0, 1, 1),
                    line([(-0.35, -0.35), (0.35, 0.35)]),
                    line([(0.35, -0.35), (-0.35, 0.35)])]
        case .wallLight:
            return [line([(-0.5, -0.5), (0.5, -0.5)]),
                    line([(-0.4, -0.5), (-0.4, -0.08), (0.4, -0.08), (0.4, -0.5)], closed: false),
                    line([(0, 0.05), (0, 0.5)]),
                    line([(-0.18, 0.02), (-0.39, 0.38)]),
                    line([(0.18, 0.02), (0.39, 0.38)])]
        case .floorLamp:
            return [oval(0, 0, 0.95, 0.95), oval(0, 0, 0.28, 0.28),
                    line([(-0.33, -0.33), (0.33, 0.33)]),
                    line([(0.33, -0.33), (-0.33, 0.33)])]
        case .desk:
            return [rectangle(-0.5, -0.5, 0.5, 0.5),
                    rectangle(-0.43, -0.39, -0.18, 0.39),
                    line([(-0.43, -0.13), (-0.18, -0.13)]),
                    line([(-0.43, 0.13), (-0.18, 0.13)]),
                    rectangle(-0.04, -0.31, 0.32, -0.11),
                    line([(0.14, -0.11), (0.14, -0.02)]),
                    line([(0.05, -0.02), (0.23, -0.02)])]
        case .officeChair:
            return [rectangle(-0.31, -0.18, 0.31, 0.29),
                    rectangle(-0.38, -0.45, 0.38, -0.25),
                    line([(-0.46, -0.08), (-0.46, 0.24)]),
                    line([(0.46, -0.08), (0.46, 0.24)]),
                    line([(-0.32, 0.46), (0, 0.14), (0.32, 0.46)]),
                    line([(0, 0.14), (0, 0.5)])]
        case .bookcase:
            var result = [rectangle(-0.5, -0.5, 0.5, 0.5),
                          line([(-0.5, 0.36), (0.5, 0.36)])]
            for x in [-0.36, -0.26, -0.15, 0.01, 0.12, 0.31] {
                result.append(line([(x, -0.38), (x, 0.36)]))
            }
            result.append(line([(0.18, -0.38), (0.27, 0.36)]))
            return result
        case .sofa:
            return [rectangle(-0.5, -0.5, 0.5, 0.5),
                    rectangle(-0.5, -0.5, 0.5, -0.27),
                    rectangle(-0.5, -0.27, -0.36, 0.5),
                    rectangle(0.36, -0.27, 0.5, 0.5),
                    rectangle(-0.34, -0.24, -0.12, 0.42),
                    rectangle(-0.11, -0.24, 0.11, 0.42),
                    rectangle(0.12, -0.24, 0.34, 0.42)]
        case .armchair:
            return [rectangle(-0.5, -0.5, 0.5, 0.5),
                    rectangle(-0.5, -0.5, 0.5, -0.27),
                    rectangle(-0.5, -0.27, -0.29, 0.5),
                    rectangle(0.29, -0.27, 0.5, 0.5),
                    rectangle(-0.26, -0.24, 0.26, 0.42)]
        case .coffeeTable:
            return tableWithLegs(inset: 0.2) + [rectangle(-0.42, -0.4, 0.42, 0.4)]
        case .television:
            return [rectangle(-0.5, -0.35, 0.5, 0.05),
                    rectangle(-0.43, -0.29, 0.43, -0.02),
                    line([(0, 0.05), (0, 0.39)]),
                    line([(-0.25, 0.47), (0, 0.39), (0.25, 0.47)])]
        case .straightStairs:
            var result = [rectangle(-0.5, -0.5, 0.5, 0.5)]
            for index in 0..<10 {
                let y = -0.45 + Double(index) * 0.1
                result.append(line([(-0.5, y), (0.5, y)]))
            }
            result += [line([(0, 0.36), (0, -0.34)]),
                       line([(-0.09, -0.2), (0, -0.34), (0.09, -0.2)])]
            return result
        case .spiralStairs:
            var result = [oval(0, 0, 1, 1), oval(0, 0, 0.14, 0.14)]
            for index in 0..<12 {
                let angle = Double(index) * .pi / 6
                result.append(.polyline(points: [polar(radius: 0.07, angle: angle),
                                                  polar(radius: 0.5, angle: angle)], closed: false))
            }
            let arc = (0...12).map { polar(radius: 0.34, angle: Double($0) * .pi / 12) }
            result += [.polyline(points: arc, closed: false),
                       line([(-0.25, 0.09), (-0.34, 0), (-0.43, 0.09)])]
            return result
        case .rectangle:
            return [rectangle(-0.5, -0.5, 0.5, 0.5)]
        case .circle, .ellipse:
            return [oval(0, 0, 1, 1)]
        case .triangle:
            return [line([(0, -0.5), (0.5, 0.5), (-0.5, 0.5)], closed: true)]
        case .line:
            return [line([(-0.5, 0), (0.5, 0)])]
        }
    }

    private static func line(_ points: [(Double, Double)], closed: Bool = false) -> ItemPrimitive {
        .polyline(points: points.map { PlanPoint(x: $0.0, y: $0.1) }, closed: closed)
    }

    private static func rectangle(_ minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double) -> ItemPrimitive {
        line([(minX, minY), (maxX, minY), (maxX, maxY), (minX, maxY)], closed: true)
    }

    private static func oval(_ x: Double, _ y: Double, _ width: Double, _ depth: Double) -> ItemPrimitive {
        .ellipse(center: PlanPoint(x: x, y: y), width: width, depth: depth)
    }

    private static func polar(radius: Double, angle: Double) -> PlanPoint {
        PlanPoint(x: radius * cos(angle), y: radius * sin(angle))
    }

    private static func tableWithLegs(inset: Double) -> [ItemPrimitive] {
        let edge = 0.5 - inset
        let legSize = 0.07
        var result = [rectangle(-0.5, -0.5, 0.5, 0.5)]
        for x in [-edge, edge] {
            for y in [-edge, edge] {
                result.append(rectangle(x - legSize / 2, y - legSize / 2,
                                        x + legSize / 2, y + legSize / 2))
            }
        }
        return result
    }
}

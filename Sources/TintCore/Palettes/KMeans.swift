/// K-means clustering over Lab colours: groups similar pixels together, and each
/// group's average becomes one palette colour. Seeded, so the same image always
/// gives the same palette.
enum KMeans {
    struct Cluster {
        var center: Lab
        var count: Int
    }

    static func run(_ points: [Lab], k: Int, seed: UInt64, maxIterations: Int = 40) -> [Cluster] {
        guard !points.isEmpty, k > 0 else { return [] }

        var random = SeededRandom(seed: seed)
        var centers = seedPlusPlus(points, k: min(k, points.count), random: &random)
        var assignment = [Int](repeating: -1, count: points.count)
        var sums = [(l: Double, a: Double, b: Double)](repeating: (0, 0, 0), count: centers.count)
        var counts = [Int](repeating: 0, count: centers.count)

        for _ in 0..<maxIterations {
            // Assignment step: every point joins its nearest centre.
            var changed = false
            for i in points.indices {
                let n = nearest(points[i], centers)
                if n != assignment[i] {
                    assignment[i] = n
                    changed = true
                }
            }

            if !changed { break }

            // Update step: every centre moves to the mean of its points.
            for c in sums.indices {
                sums[c] = (0, 0, 0)
                counts[c] = 0
            }
            for i in points.indices {
                let c = assignment[i]
                sums[c].l += points[i].l
                sums[c].a += points[i].a
                sums[c].b += points[i].b
                counts[c] += 1
            }
            for c in centers.indices where counts[c] > 0 {
                let n = Double(counts[c])
                centers[c] = Lab(l: sums[c].l / n, a: sums[c].a / n, b: sums[c].b / n)
            }
        }

        // Final counts, since the loop can exit right after reassigning.
        counts = [Int](repeating: 0, count: centers.count)
        for c in assignment { counts[c] += 1 }

        return centers.indices.compactMap { c in
            counts[c] > 0 ? Cluster(center: centers[c], count: counts[c]) : nil
        }
    }

    /// k-means++ seeding: each new starting centre is picked with probability
    /// proportional to its squared distance from the centres chosen so far, so
    /// the starting points are spread out instead of bunched together.
    private static func seedPlusPlus(_ points: [Lab], k: Int, random: inout SeededRandom) -> [Lab] {
        var centers = [points[random.nextInt(points.count)]]
        var distances = points.map { $0.distanceSquared(to: centers[0]) }

        while centers.count < k {
            let total = distances.reduce(0, +)

            // Every point already sits on a centre: the image has fewer distinct
            // colours than requested, so stop early rather than duplicate one.
            if total <= 0 { break }

            var target = random.nextDouble() * total
            var pick = points.count - 1
            for i in distances.indices {
                target -= distances[i]
                if target <= 0 {
                    pick = i
                    break
                }
            }

            let next = points[pick]
            centers.append(next)
            for i in points.indices {
                distances[i] = min(distances[i], points[i].distanceSquared(to: next))
            }
        }

        return centers
    }

    @inline(__always)
    private static func nearest(_ point: Lab, _ centers: [Lab]) -> Int {
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for c in centers.indices {
            let d = point.distanceSquared(to: centers[c])
            if d < bestDistance {
                bestDistance = d
                best = c
            }
        }
        return best
    }
}

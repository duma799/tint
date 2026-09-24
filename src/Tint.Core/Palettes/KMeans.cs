using Tint.Core.Colors;

namespace Tint.Core.Palettes;

/// <summary>
/// K-means clustering over Lab colours: groups similar pixels together, and each
/// group's average becomes one palette colour. Seeded, so the same image always
/// gives the same palette.
/// </summary>
internal static class KMeans
{
    public readonly record struct Cluster(Lab Center, int Count);

    public static Cluster[] Run(ReadOnlySpan<Lab> points, int k, int seed, int maxIterations = 40)
    {
        if (points.IsEmpty || k <= 0)
        {
            return [];
        }

        var random = new Random(seed);
        List<Lab> centers = SeedPlusPlus(points, Math.Min(k, points.Length), random);
        var assignment = new int[points.Length];
        Array.Fill(assignment, -1);

        var sums = new (double L, double A, double B)[centers.Count];
        var counts = new int[centers.Count];

        for (int iteration = 0; iteration < maxIterations; iteration++)
        {
            // Assignment step: every point joins its nearest centre.
            bool changed = false;
            for (int i = 0; i < points.Length; i++)
            {
                int nearest = Nearest(points[i], centers);
                if (nearest != assignment[i])
                {
                    assignment[i] = nearest;
                    changed = true;
                }
            }

            if (!changed)
            {
                break;
            }

            // Update step: every centre moves to the mean of its points.
            Array.Clear(sums);
            Array.Clear(counts);
            for (int i = 0; i < points.Length; i++)
            {
                int c = assignment[i];
                sums[c].L += points[i].L;
                sums[c].A += points[i].A;
                sums[c].B += points[i].B;
                counts[c]++;
            }

            for (int c = 0; c < centers.Count; c++)
            {
                if (counts[c] > 0)
                {
                    centers[c] = new Lab(sums[c].L / counts[c], sums[c].A / counts[c], sums[c].B / counts[c]);
                }
            }
        }

        // Final counts, since the loop can exit right after reassigning.
        Array.Clear(counts);
        foreach (int c in assignment)
        {
            counts[c]++;
        }

        var result = new List<Cluster>(centers.Count);
        for (int c = 0; c < centers.Count; c++)
        {
            if (counts[c] > 0)
            {
                result.Add(new Cluster(centers[c], counts[c]));
            }
        }

        return [.. result];
    }

    /// <summary>
    /// k-means++ seeding: each new starting centre is picked with probability
    /// proportional to its squared distance from the centres chosen so far, so
    /// the starting points are spread out instead of bunched together.
    /// </summary>
    private static List<Lab> SeedPlusPlus(ReadOnlySpan<Lab> points, int k, Random random)
    {
        var centers = new List<Lab>(k) { points[random.Next(points.Length)] };
        var distances = new double[points.Length];
        for (int i = 0; i < points.Length; i++)
        {
            distances[i] = points[i].DistanceSquared(centers[0]);
        }

        while (centers.Count < k)
        {
            double total = 0;
            foreach (double d in distances)
            {
                total += d;
            }

            // Every point already sits on a centre: the image has fewer distinct
            // colours than requested, so stop early rather than duplicate one.
            if (total <= 0)
            {
                break;
            }

            double target = random.NextDouble() * total;
            int pick = points.Length - 1;
            for (int i = 0; i < points.Length; i++)
            {
                target -= distances[i];
                if (target <= 0)
                {
                    pick = i;
                    break;
                }
            }

            Lab next = points[pick];
            centers.Add(next);
            for (int i = 0; i < points.Length; i++)
            {
                distances[i] = Math.Min(distances[i], points[i].DistanceSquared(next));
            }
        }

        return centers;
    }

    private static int Nearest(Lab point, List<Lab> centers)
    {
        int best = 0;
        double bestDistance = double.MaxValue;
        for (int c = 0; c < centers.Count; c++)
        {
            double d = point.DistanceSquared(centers[c]);
            if (d < bestDistance)
            {
                bestDistance = d;
                best = c;
            }
        }

        return best;
    }
}

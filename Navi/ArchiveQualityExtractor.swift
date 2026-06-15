//
//  ArchiveQualityExtractor.swift
//  Navi
//

import AstrophotoKit
import TabularData

enum ArchiveQualityExtractor {

    static func extractPerFrameQuality(from tables: [TableData])
        -> [(filePath: String, starCount: Int?, medianFWHM: Double?, medianEccentricity: Double?)]
    {
        for table in tables {
            guard let df = table.dataFrame else { continue }
            let colNames = Set(df.columns.map { $0.name })
            guard colNames.contains("file_path"), colNames.contains("median_fwhm"),
                  colNames.contains("star_count") else { continue }
            return df.rows.compactMap { row -> (String, Int?, Double?, Double?)? in
                guard let path = row["file_path"] as? String, !path.isEmpty else { return nil }
                let starCount: Int? = (row["star_count"] as? Int32).map { Int($0) } ?? (row["star_count"] as? Int)
                return (path, starCount, row["median_fwhm"] as? Double, row["mean_eccentricity"] as? Double)
            }
        }
        return []
    }

    static func extractGlobalQuality(from tables: [TableData])
        -> (starCount: Int?, medianFWHM: Double?, backgroundNoise: Double?,
            backgroundNoiseIsADU: Bool, medianEccentricity: Double?,
            saturatedStarCount: Int?, hotPixelCount: Int?)
    {
        var starCount: Int? = nil, medianFWHM: Double? = nil, backgroundNoise: Double? = nil
        var backgroundNoiseIsADU = false, medianEccentricity: Double? = nil
        var saturatedStarCount: Int? = nil, hotPixelCount: Int? = nil
        for table in tables {
            guard let df = table.dataFrame else { continue }
            let colNames = Set(df.columns.map { $0.name })
            if colNames.contains("star_count") && colNames.contains("saturated_star_count"),
               let row = df.rows.first {
                if let v = row["star_count"]           as? Int  { starCount = v }
                if let v = row["saturated_star_count"] as? Int  { saturatedStarCount = v }
                if let v = row["median_fwhm"]          as? Double, v > 0 { medianFWHM = v }
                if let v = row["median_eccentricity"]  as? Double { medianEccentricity = v }
                if colNames.contains("background_level_adu"), let v = row["background_level_adu"] as? Double {
                    backgroundNoise = v; backgroundNoiseIsADU = true
                } else if let v = row["background_level"] as? Double { backgroundNoise = v }
            }
            if colNames.contains("noise_sigma") && colNames.contains("hot_pixel_count"),
               let row = df.rows.first {
                if let v = row["hot_pixel_count"] as? Int { hotPixelCount = v }
                if colNames.contains("noise_sigma_adu"), let v = row["noise_sigma_adu"] as? Double {
                    backgroundNoise = v; backgroundNoiseIsADU = true
                } else if let v = row["noise_sigma"] as? Double { backgroundNoise = v }
            }
            if colNames.contains("centroid_x") && colNames.contains("centroid_y") {
                if starCount == nil { starCount = df.rows.count }
                if medianEccentricity == nil {
                    let eccs = df.rows.compactMap { $0["eccentricity"] as? Double }.filter { !$0.isNaN }
                    if !eccs.isEmpty { medianEccentricity = eccs.reduce(0, +) / Double(eccs.count) }
                }
            }
            if colNames.contains("sigma_clipped_mean_fwhm_major"),
               colNames.contains("sigma_clipped_mean_fwhm_minor"),
               let row = df.rows.first,
               let major = row["sigma_clipped_mean_fwhm_major"] as? Double,
               let minor = row["sigma_clipped_mean_fwhm_minor"] as? Double,
               major > 0, medianFWHM == nil { medianFWHM = (major + minor) / 2.0 }
            if colNames.contains("background_level"), !colNames.contains("star_count"),
               let row = df.rows.first, backgroundNoise == nil {
                if colNames.contains("background_level_adu"), let v = row["background_level_adu"] as? Double {
                    backgroundNoise = v; backgroundNoiseIsADU = true
                } else if let v = row["background_level"] as? Double { backgroundNoise = v }
            }
            if colNames.contains("global_mean_eccentricity"), let row = df.rows.first,
               let ecc = row["global_mean_eccentricity"] as? Double, medianEccentricity == nil {
                medianEccentricity = ecc
            }
        }
        return (starCount, medianFWHM, backgroundNoise, backgroundNoiseIsADU, medianEccentricity, saturatedStarCount, hotPixelCount)
    }
}

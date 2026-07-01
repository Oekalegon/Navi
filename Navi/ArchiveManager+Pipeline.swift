//
//  ArchiveManager+Pipeline.swift
//  Navi
//

import AstrophotoArchiveKit
import AstrophotoKit
import AstrophotoToolDefinitions
import Foundation
import Metal
import TabularData

// MARK: - Pipeline tool definitions and implementations

extension ArchiveManager {

    func listPipelines() -> String {
        let all = PipelineRegistry.shared.getAll()
        guard !all.isEmpty else { return "No pipelines registered." }
        var lines = ["Available pipelines (\(all.count)):"]
        for p in all.values.sorted(by: { $0.id < $1.id }) {
            lines.append("• \(p.id)\(p.description.map { ": \($0)" } ?? "")")
        }
        return lines.joined(separator: "\n")
    }

    func inspectPipeline(_ args: [String: Any]) throws -> String {
        guard let id = args["pipeline_id"] as? String else {
            throw ArchiveManagerError.missingArgument("pipeline_id")
        }
        guard let pipeline = PipelineRegistry.shared.get(id: id) else {
            throw ArchiveManagerError.missingArgument("Pipeline not found: '\(id)'. Call list_pipelines to see what's available.")
        }
        let inputNames = Array(Set(pipeline.steps.flatMap { step in
            step.dataInputs.compactMap { di in di.from.contains(".") ? nil : di.from }
        })).sorted()
        let paramSpecs: [String: ParameterSpec] = pipeline.steps
            .flatMap { $0.parameters }
            .filter { $0.from != nil }
            .reduce(into: [:]) { acc, spec in if acc[spec.from!] == nil { acc[spec.from!] = spec } }

        var lines = ["Pipeline: \(pipeline.id)", "Name: \(pipeline.name)"]
        if let desc = pipeline.description { lines.append("Description: \(desc)") }
        lines.append("")
        lines.append("Inputs (\(inputNames.count)): \(inputNames.joined(separator: ", "))")
        lines.append("Steps: \(pipeline.steps.count)")
        if !paramSpecs.isEmpty {
            lines.append(""); lines.append("Parameters:")
            for key in paramSpecs.keys.sorted() {
                let spec = paramSpecs[key]!
                let def = spec.defaultValue.map { " [default: \($0.stringValue)]" } ?? " [required]"
                let desc = spec.description.map { " — \($0)" } ?? ""
                lines.append("  \(key)\(def)\(desc)")
            }
        }
        lines.append(""); lines.append("Steps:")
        for step in pipeline.steps {
            lines.append("  \(step.id) — \(step.type)\(step.name.map { " (\($0))" } ?? "")")
        }
        return lines.joined(separator: "\n")
    }

    func runPipeline(_ args: [String: Any], archive: Archive) async throws -> String {
        guard let pipelineID = args["pipeline_id"] as? String, !pipelineID.isEmpty else {
            throw ArchiveManagerError.missingArgument("pipeline_id")
        }
        let outputPath   = args["output_path"]   as? String
        let outputFormat = args["output_format"] as? String ?? "fits"

        guard let pipeline = PipelineRegistry.shared.get(id: pipelineID) else {
            throw ArchiveManagerError.missingArgument("Pipeline not found: '\(pipelineID)'. Call list_pipelines first.")
        }
        let expectedInputs = Array(Set(pipeline.steps.flatMap { step in
            step.dataInputs.compactMap { di in di.from.contains(".") ? nil : di.from }
        }))
        guard let device = AstrophotoKit.makeDefaultDevice() else {
            throw ArchiveManagerError.missingArgument("No Metal GPU device available.")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw ArchiveManagerError.missingArgument("Failed to create Metal command queue.")
        }

        // Convert params
        let params = args["parameters"] as? [String: Any] ?? [:]
        var parameters: [String: Parameter] = [:]
        for (key, val) in params {
            switch val {
            case let i as Int:    parameters[key] = .int(i)
            case let d as Double: parameters[key] = .double(d)
            case let s as String:
                if let i = Int(s)         { parameters[key] = .int(i) }
                else if let d = Double(s) { parameters[key] = .double(d) }
                else                      { parameters[key] = .string(s) }
            default: parameters[key] = .string("\(val)")
            }
        }

        let inputFrameSetID = args["input_frameset_id"] as? String
        let inputFrameID    = args["input_frame_id"]    as? String
        let inputDir        = args["input_dir"]         as? String
        let inputPaths      = args["input_paths"]       as? [String]
        let inputPath       = args["input_path"]        as? String
        let inputName       = args["input_name"]        as? String

        let resolvedPaths: [String]? = try {
            guard let dir = inputDir else { return nil }
            let expanded = (dir as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
                throw ArchiveManagerError.missingArgument("input_dir not found or is not a directory: \(dir)")
            }
            let extensions = Set(["fits", "fit", "fts"])
            let files = try FileManager.default.contentsOfDirectory(atPath: expanded)
            let fits = files
                .filter { extensions.contains(($0 as NSString).pathExtension.lowercased()) }
                .sorted()
                .map { (expanded as NSString).appendingPathComponent($0) }
            guard !fits.isEmpty else {
                throw ArchiveManagerError.missingArgument("No FITS files found in directory: \(dir)")
            }
            return fits
        }()

        var pipelineInputs: [String: Any] = [:]

        if let frameSetID = inputFrameSetID {
            guard let uuid = UUID(uuidString: frameSetID) else {
                throw ArchiveManagerError.missingArgument("input_frameset_id must be a valid UUID")
            }
            guard try await archive.frameSet(id: uuid) != nil else {
                throw ArchiveManagerError.missingArgument("No frameset with id '\(frameSetID)' found.")
            }
            let archivedFrames = try await archive.frames(inFrameSet: uuid)
            guard !archivedFrames.isEmpty else {
                throw ArchiveManagerError.missingArgument("Frameset '\(frameSetID)' contains no frames.")
            }
            let resolvedName = try resolveInputName(inputName, expectedInputs: expectedInputs, pipelineID: pipelineID)
            let topLevelInputType = pipeline.steps.flatMap { $0.dataInputs }
                .first { !$0.from.contains(".") && $0.name == resolvedName }?.type
            if topLevelInputType == .frameSet {
                var frames: [Frame] = []
                for af in archivedFrames {
                    guard FileManager.default.fileExists(atPath: af.filePath) else { continue }
                    let fitsFile = try FITSFile(path: af.filePath)
                    let img = try fitsFile.readFITSImage()
                    frames.append(try Frame(fitsImage: img, device: device, filePath: af.filePath))
                }
                pipelineInputs[resolvedName] = FrameSet(frames: frames, outputProcess: nil, inputProcesses: [])
            } else {
                return try await runPipelinePerFrame(
                    pipelineID: pipelineID, pipeline: pipeline,
                    resolvedInputName: resolvedName, archivedFrames: archivedFrames,
                    parameters: parameters, device: device, commandQueue: commandQueue,
                    archive: archive)
            }
        } else if let frameID = inputFrameID {
            guard let uuid = UUID(uuidString: frameID) else {
                throw ArchiveManagerError.missingArgument("input_frame_id must be a valid UUID")
            }
            guard let af = try await archive.frame(id: uuid) else {
                throw ArchiveManagerError.missingArgument("No frame with id '\(frameID)' found.")
            }
            let resolvedName = try resolveInputName(inputName, expectedInputs: expectedInputs, pipelineID: pipelineID)
            let fitsFile = try FITSFile(path: af.filePath)
            let img = try fitsFile.readFITSImage()
            pipelineInputs[resolvedName] = try Frame(fitsImage: img, device: device, filePath: af.filePath)
        } else if let paths = resolvedPaths ?? inputPaths, !paths.isEmpty {
            let resolvedName = try resolveInputName(inputName, expectedInputs: expectedInputs, pipelineID: pipelineID)
            var frames: [Frame] = []
            for path in paths {
                let expanded = (path as NSString).expandingTildeInPath
                guard FileManager.default.fileExists(atPath: expanded) else {
                    throw ArchiveManagerError.missingArgument("File not found: \(path)")
                }
                let fitsFile = try FITSFile(path: expanded)
                let img = try fitsFile.readFITSImage()
                frames.append(try Frame(fitsImage: img, device: device, filePath: expanded))
            }
            pipelineInputs[resolvedName] = FrameSet(frames: frames, outputProcess: nil, inputProcesses: [])
        } else if let path = inputPath {
            let expanded = (path as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded) else {
                throw ArchiveManagerError.missingArgument("File not found: \(path)")
            }
            let resolvedName = try resolveInputName(inputName, expectedInputs: expectedInputs, pipelineID: pipelineID)
            let fitsFile = try FITSFile(path: expanded)
            pipelineInputs[resolvedName] = try fitsFile.readFITSImage()
        } else {
            throw ArchiveManagerError.missingArgument(
                "Provide input_frameset_id, input_frame_id, input_path, input_paths, or input_dir for pipeline '\(pipelineID)'."
            )
        }

        let start = Date()
        let runner = PipelineRunner(pipeline: pipeline)
        let outputs = try await runner.execute(inputs: pipelineInputs, parameters: parameters,
                                               device: device, commandQueue: commandQueue)
        let elapsed = Date().timeIntervalSince(start)

        let tables = outputs.compactMap { $0 as? TableData }.filter { $0.isInstantiated }
        let frames = outputs.compactMap { $0 as? Frame }.filter { $0.isInstantiated }

        var savedNote = ""
        if let outPath = outputPath {
            if let firstFrame = frames.first, let firstTable = tables.first,
               let df = firstTable.dataFrame, outputFormat.lowercased() != "csv" {
                guard let texture = firstFrame.texture else {
                    throw ArchiveManagerError.missingArgument("Output frame has no texture data")
                }
                let w = texture.width, h = texture.height
                let stackMethod  = parameters["method"]?.stringValue         ?? "average"
                let stackNorm    = parameters["normalisation"]?.stringValue   ?? "none"
                let stackRej     = parameters["pixel_rejection"]?.stringValue ?? "sigma_clip"
                let stackRejLow  = parameters["rejection_low"]?.doubleValue   ?? 3.0
                let stackRejHigh = parameters["rejection_high"]?.doubleValue  ?? 3.0
                let inputMeta    = unanimousFrameMetadata(from: pipelineInputs)
                // GPU readback and FITS write are synchronous; hop off the main actor.
                let pixels = try await Task.detached(priority: .userInitiated) {
                    var buf = [Float](repeating: 0, count: w * h)
                    texture.getBytes(&buf, bytesPerRow: w * MemoryLayout<Float>.size,
                                     from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                    try FITSTableWriter.writeStackedOutput(
                        pixelData: buf, width: w, height: h, registrationTable: df,
                        method: stackMethod, normalisation: stackNorm, rejection: stackRej,
                        rejectionLow: stackRejLow, rejectionHigh: stackRejHigh,
                        objectName: inputMeta.objectName, camera: inputMeta.camera,
                        telescope: inputMeta.telescope, site: inputMeta.site, to: outPath)
                    return buf
                }.value
                let inputFrameSet = pipelineInputs.values.compactMap { $0 as? FrameSet }.first
                let summary = stackSummaryLine(pixels: pixels, registrationTable: df, inputFrameSet: inputFrameSet)
                savedNote = "\nSaved stacked FITS to \(outPath).\(summary.map { "\n\($0)" } ?? "")"
            } else if let firstTable = tables.first, let df = firstTable.dataFrame {
                let fmt: FITSTableWriter.OutputFormat = (outputFormat.lowercased() == "csv") ? .csv : .fits
                // File write is synchronous; hop off the main actor.
                try await Task.detached(priority: .userInitiated) {
                    try FITSTableWriter.writeRegistrationTable(df, to: outPath, format: fmt)
                }.value
                savedNote = "\nSaved table to \(outPath) (\(outputFormat.lowercased()))."
            }
        }

        if !frames.isEmpty {
            if let note = await autoArchiveResults(frames: frames, pipelineID: pipelineID,
                                                   parameters: parameters, pipelineInputs: pipelineInputs,
                                                   existingOutputPath: (outputPath?.hasSuffix(".fits") == true || outputPath?.hasSuffix(".fit") == true) ? outputPath : nil,
                                                   archive: archive) {
                savedNote += "\n\(note)"
            }
        }
        if let note = await backUpdateQuality(tables: tables,
                                              inputFrameID: (args["input_frame_id"] as? String).flatMap { UUID(uuidString: $0) },
                                              inputFilePath: args["input_path"] as? String,
                                              archive: archive) {
            savedNote += "\n\(note)"
        }

        var lines = [
            "Pipeline '\(pipelineID)' completed in \(String(format: "%.2f", elapsed))s.",
            "\(frames.count) frame(s) produced, \(tables.count) table(s) produced.\(savedNote)"
        ]
        for (i, table) in tables.enumerated() {
            guard let df = table.dataFrame else { continue }
            let cols = df.columns.map { $0.name }
            lines.append("")
            lines.append("Table \(i + 1) — \(df.rows.count) rows, columns: \(cols.joined(separator: ", "))")
            for row in df.rows.prefix(50) {
                let entries = cols.compactMap { col -> String? in
                    guard let v = row[col] else { return nil }
                    if let d = v as? Double { return "\(col): \(String(format: "%.4f", d))" }
                    if let f = v as? Float  { return "\(col): \(String(format: "%.4f", f))" }
                    return "\(col): \(v)"
                }
                lines.append("  { \(entries.joined(separator: ", ")) }")
            }
            if df.rows.count > 50 { lines.append("  … \(df.rows.count - 50) more rows omitted.") }
        }
        return lines.joined(separator: "\n")
    }

    private func runPipelinePerFrame(
        pipelineID: String,
        pipeline: Pipeline,
        resolvedInputName: String,
        archivedFrames: [ArchivedFrame],
        parameters: [String: Parameter],
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        archive: Archive
    ) async throws -> String {
        let start = Date()
        var processedCount = 0, errorCount = 0
        var qualityNotes: [String] = []
        for af in archivedFrames {
            guard FileManager.default.fileExists(atPath: af.filePath) else { errorCount += 1; continue }
            do {
                let fitsFile = try FITSFile(path: af.filePath)
                let img = try fitsFile.readFITSImage()
                let frame = try Frame(fitsImage: img, device: device, filePath: af.filePath)
                let runner = PipelineRunner(pipeline: pipeline)
                let outputs = try await runner.execute(inputs: [resolvedInputName: frame],
                                                       parameters: parameters, device: device,
                                                       commandQueue: commandQueue)
                let tables = outputs.compactMap { $0 as? TableData }.filter { $0.isInstantiated }
                if let note = await backUpdateQuality(tables: tables, inputFrameID: af.id,
                                                      inputFilePath: nil, archive: archive) {
                    qualityNotes.append(note)
                }
                processedCount += 1
            } catch { errorCount += 1 }
        }
        let elapsed = Date().timeIntervalSince(start)
        var lines = [
            "Pipeline '\(pipelineID)' completed in \(String(format: "%.2f", elapsed))s.",
            "\(processedCount) frame(s) processed" + (errorCount > 0 ? ", \(errorCount) failed." : ".")
        ]
        if !qualityNotes.isEmpty { lines.append(contentsOf: qualityNotes) }
        return lines.joined(separator: "\n")
    }

    private func autoArchiveResults(
        frames: [Frame],
        pipelineID: String,
        parameters: [String: Parameter],
        pipelineInputs: [String: Any],
        existingOutputPath: String?,
        archive: Archive
    ) async -> String? {
        do {
            var runInputs: [ProcessingRunInputRef] = []
            var objectNamesSet: Set<String> = [], filterNamesSet: Set<String> = []
            var camerasSet: Set<String> = [], telescopesSet: Set<String> = [], sitesSet: Set<String> = []
            var pixelScalesSet: Set<Double> = [], focalLengthsSet: Set<Double> = []
            var totalExposure = 0.0, inputCount = 0
            var gainsSet: Set<Double> = [], offsetsSet: Set<Double> = []
            var temperatures: [Double] = [], timestamps: [Date] = []
            var refRA: Double? = nil, refDec: Double? = nil

            let stackFilter: String?
            for (name, value) in pipelineInputs.sorted(by: { $0.key < $1.key }) {
                let pathsAndFrames: [(String, Frame?)]
                if let fs = value as? FrameSet      { pathsAndFrames = fs.frames.compactMap { f in f.filePath.map { ($0, f) } } }
                else if let f = value as? Frame     { pathsAndFrames = f.filePath.map { [($0, f as Frame?)] } ?? [] }
                else                                { pathsAndFrames = [] }
                for (pos, (path, inputFrame)) in pathsAndFrames.enumerated() {
                    let af = try? await archive.frame(filePath: path)
                    runInputs.append(ProcessingRunInputRef(inputName: name, frameID: af?.id, filePath: path, position: pos))
                    if pos == 0 { refRA = af?.ra; refDec = af?.dec }
                    inputCount += 1
                    if let v = af?.objectName ?? inputFrame?.objectName { objectNamesSet.insert(v) }
                    let fn = af?.filter ?? inputFrame?.filterName; if let fn { filterNamesSet.insert(fn) }
                    let exp = af?.exposureTime ?? inputFrame?.exposureTime; if let exp { totalExposure += exp }
                    if let g = af?.gain ?? inputFrame?.gain { gainsSet.insert(g) }
                    if let o = af?.offset ?? inputFrame?.offset { offsetsSet.insert(o) }
                    if let t = af?.temperature { temperatures.append(t) }
                    if let ts = af?.timestamp ?? inputFrame?.timestamp { timestamps.append(ts) }
                    if let c = af?.camera ?? inputFrame?.camera { camerasSet.insert(c) }
                    if let tl = af?.telescope ?? inputFrame?.telescope { telescopesSet.insert(tl) }
                    if let s = af?.site ?? inputFrame?.site { sitesSet.insert(s) }
                    if let ps = af?.pixelScale { pixelScalesSet.insert(ps) }
                    if let fl = af?.focalLength { focalLengthsSet.insert(fl) }
                }
            }
            let stackObjectName  = objectNamesSet.count  == 1 ? objectNamesSet.first  : nil
            stackFilter          = filterNamesSet.count  == 1 ? filterNamesSet.first  : nil
            let stackCamera      = camerasSet.count      == 1 ? camerasSet.first      : nil
            let stackTelescope   = telescopesSet.count   == 1 ? telescopesSet.first   : nil
            let stackSite        = sitesSet.count        == 1 ? sitesSet.first        : nil
            let stackPixelScale  = pixelScalesSet.count  == 1 ? pixelScalesSet.first  : nil
            let stackFocalLength = focalLengthsSet.count == 1 ? focalLengthsSet.first : nil
            let stackExposure    = inputCount > 0 && totalExposure > 0 ? totalExposure : nil as Double?
            let stackGain        = gainsSet.count   == 1 ? gainsSet.first   : nil
            let stackOffset      = offsetsSet.count == 1 ? offsetsSet.first : nil
            let stackTempMean    = temperatures.isEmpty ? nil : temperatures.reduce(0, +) / Double(temperatures.count) as Double?
            let stackTempMin     = temperatures.isEmpty ? nil : temperatures.min()
            let stackTempMax     = temperatures.isEmpty ? nil : temperatures.max()

            let iso8601 = ISO8601DateFormatter(); iso8601.formatOptions = [.withInternetDateTime]
            let refDate  = timestamps.max().flatMap { iso8601.string(from: $0) }
            let dateBeg  = timestamps.min().flatMap { iso8601.string(from: $0) }
            let dateEnd  = timestamps.max().flatMap { iso8601.string(from: $0) }
            // Merge explicit parameters with pipeline defaults, keeping only keys
            // declared in the pipeline spec. Unrecognised keys are dropped so that
            // caller-supplied aliases (e.g. combine_method, stacking_method) never
            // pollute the stored run and produce spurious diffs later.
            var fullParameters: [String: Parameter] = [:]
            if let pipeline = PipelineRegistry.shared.get(id: pipelineID) {
                let paramSpecs: [String: ParameterSpec] = pipeline.steps
                    .flatMap { $0.parameters }
                    .filter { $0.from != nil }
                    .reduce(into: [:]) { acc, spec in if acc[spec.from!] == nil { acc[spec.from!] = spec } }
                for key in paramSpecs.keys {
                    if let v = parameters[key] { fullParameters[key] = v }
                    else if let def = paramSpecs[key]?.defaultValue { fullParameters[key] = def }
                }
            }
            let paramMap = fullParameters.reduce(into: [String: String]()) { $0[$1.key] = $1.value.stringValue }
            let run      = try await archive.recordProcessingRun(pipelineID: pipelineID, parameters: paramMap, inputs: runInputs)

            var archivedIDs: [String] = []
            for frame in frames {
                guard let texture = frame.texture else { continue }
                let tempURL: URL?
                let fileToArchive: URL
                if let outPath = existingOutputPath, frames.count == 1 {
                    fileToArchive = URL(fileURLWithPath: outPath); tempURL = nil
                } else {
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("navi_result_\(UUID().uuidString).fits")
                    let w = texture.width, h = texture.height
                    let filterName = stackFilter ?? frame.filterName
                    let stacked    = pipelineID == "frame_stacking"
                    let nframes    = inputCount > 0 ? inputCount : nil as Int?
                    // GPU readback and FITS write are synchronous; hop off the main actor.
                    try await Task.detached(priority: .userInitiated) {
                        var buf = [Float](repeating: 0, count: w * h)
                        texture.getBytes(&buf, bytesPerRow: w * MemoryLayout<Float>.size,
                                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                        try FITSTableWriter.writeResultFrame(
                            pixelData: buf, width: w, height: h, pipelineID: pipelineID,
                            imageType: "Light Frame", filterName: filterName,
                            stacked: stacked, nframes: nframes,
                            totalExposure: stackExposure, gain: stackGain, offset: stackOffset,
                            temperature: stackTempMean, objectName: stackObjectName, camera: stackCamera,
                            telescope: stackTelescope, site: stackSite, ra: refRA, dec: refDec,
                            pixelScale: stackPixelScale, focalLength: stackFocalLength,
                            tempMin: stackTempMin, tempMax: stackTempMax,
                            dateObs: refDate, dateBeg: dateBeg, dateEnd: dateEnd, to: tmp.path)
                    }.value
                    fileToArchive = tmp; tempURL = tmp
                }
                let (archived, _) = try await archive.add(fitsFile: fileToArchive, processingRunID: run.id)
                if let tmp = tempURL { try? FileManager.default.removeItem(at: tmp) }
                archivedIDs.append(archived.id.uuidString)
            }
            importVersion += 1
            if archivedIDs.isEmpty { return "Auto-archive: no frames could be read from GPU texture." }
            return "Archived result frame(s): \(archivedIDs.joined(separator: ", ")) (run: \(run.id))"
        } catch {
            return "Auto-archive failed: \(error.localizedDescription)"
        }
    }

    private func backUpdateQuality(
        tables: [TableData],
        inputFrameID: UUID?,
        inputFilePath: String?,
        archive: Archive
    ) async -> String? {
        let perFrame = PipelineQualityExtractor.extractPerFrameQuality(from: tables)
        if !perFrame.isEmpty {
            var notes: [String] = []
            do {
                for entry in perFrame {
                    let expanded = (entry.filePath as NSString).expandingTildeInPath
                    guard let af = try await archive.frame(filePath: expanded) else { continue }
                    try await archive.updateFrameQuality(id: af.id, starCount: entry.starCount,
                                                         medianFWHM: entry.medianFWHM,
                                                         medianEccentricity: entry.medianEccentricity)
                    var parts: [String] = []
                    if let v = entry.starCount          { parts.append("stars: \(v)") }
                    if let v = entry.medianFWHM         { parts.append(String(format: "FWHM: %.2fpx", v)) }
                    if let v = entry.medianEccentricity { parts.append(String(format: "ecc: %.3f", v)) }
                    if !parts.isEmpty { notes.append("\(af.id): \(parts.joined(separator: ", "))") }
                }
            } catch { return "Quality update failed: \(error.localizedDescription)" }
            return notes.isEmpty ? nil : "Quality metrics stored on \(notes.count) frame(s)."
        }
        let metrics = PipelineQualityExtractor.extractGlobalQuality(from: tables)
        guard metrics.starCount != nil || metrics.medianFWHM != nil || metrics.backgroundNoise != nil
                || metrics.medianEccentricity != nil || metrics.saturatedStarCount != nil
                || metrics.hotPixelCount != nil || metrics.sunAltitude != nil
                || metrics.moonSeparation != nil else { return nil }
        do {
            let targetID: UUID?
            if let id = inputFrameID { targetID = id }
            else if let path = inputFilePath {
                targetID = try await archive.frame(filePath: (path as NSString).expandingTildeInPath)?.id
            } else { targetID = nil }
            guard let id = targetID else { return nil }
            try await archive.updateFrameQuality(id: id, starCount: metrics.starCount,
                                                  medianFWHM: metrics.medianFWHM,
                                                  backgroundNoise: metrics.backgroundNoise,
                                                  medianEccentricity: metrics.medianEccentricity,
                                                  saturatedStarCount: metrics.saturatedStarCount,
                                                  hotPixelCount: metrics.hotPixelCount,
                                                  sunAltitude: metrics.sunAltitude,
                                                  moonSeparation: metrics.moonSeparation,
                                                  moonIllumination: metrics.moonIllumination)
            var parts: [String] = []
            if let v = metrics.starCount          { parts.append("stars: \(v)") }
            if let v = metrics.saturatedStarCount { parts.append("sat: \(v)") }
            if let v = metrics.medianFWHM         { parts.append(String(format: "FWHM: %.2fpx", v)) }
            if let v = metrics.backgroundNoise    { parts.append(String(format: "bg: %.4f", v)) }
            if let v = metrics.medianEccentricity { parts.append(String(format: "ecc: %.3f", v)) }
            if let v = metrics.hotPixelCount      { parts.append("hot_px: \(v)") }
            return "Quality metrics stored on frame \(id): \(parts.joined(separator: ", "))."
        } catch { return "Quality update failed: \(error.localizedDescription)" }
    }

    private func unanimousFrameMetadata(from inputs: [String: Any])
        -> (objectName: String?, camera: String?, telescope: String?, site: String?)
    {
        var objNames = Set<String>(), cams = Set<String>(), scopes = Set<String>(), sites = Set<String>()
        for value in inputs.values {
            let fs: [Frame]
            if let s = value as? FrameSet { fs = s.frames }
            else if let f = value as? Frame { fs = [f] }
            else { continue }
            for f in fs {
                if let v = f.objectName { objNames.insert(v) }
                if let v = f.camera     { cams.insert(v) }
                if let v = f.telescope  { scopes.insert(v) }
                if let v = f.site       { sites.insert(v) }
            }
        }
        return (objNames.count == 1 ? objNames.first : nil, cams.count == 1 ? cams.first : nil,
                scopes.count == 1 ? scopes.first : nil, sites.count == 1 ? sites.first : nil)
    }

    private func stackSummaryLine(pixels: [Float], registrationTable df: DataFrame, inputFrameSet: FrameSet?) -> String? {
        let skyNoises = df.rows.compactMap { $0["sky_noise"] as? Double }.filter { !$0.isNaN && $0 > 0 }
        guard !skyNoises.isEmpty else { return nil }
        let mean = skyNoises.reduce(0, +) / Double(skyNoises.count)
        return "Mean sky noise: \(String(format: "%.2f", mean)) ADU."
    }

    private func resolveInputName(_ name: String?, expectedInputs: [String], pipelineID: String) throws -> String {
        if let n = name { return n }
        if expectedInputs.count == 1 { return expectedInputs[0] }
        throw ArchiveManagerError.missingArgument(
            "Pipeline '\(pipelineID)' has multiple inputs: \(expectedInputs.sorted().joined(separator: ", ")). Specify input_name."
        )
    }
}

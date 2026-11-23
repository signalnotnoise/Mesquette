// DirectorStaging.swift
// Mesquette — Split a scene into objects and place them. Do not rewrite the user's English.

import Foundation

nonisolated enum DirectorStaging {

    private static let poisonPhrases = ["highly detailed"]
    private static let poisonWords: Set<String> = [
        "cad", "8k", "octane", "manifold", "polycount", "photorealistic"
    ]

    /// Trim and drop CAD/8K/photoreal boilerplate. Does not clip length or rewrite the scene.
    static func objectPrompt(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for phrase in poisonPhrases {
            text = text.replacingOccurrences(of: phrase, with: " ", options: .caseInsensitive)
        }
        let kept = text.split(whereSeparator: { $0.isWhitespace }).compactMap { chunk -> String? in
            let word = String(chunk)
            let bare = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            return poisonWords.contains(bare) ? nil : word
        }
        return kept.joined(separator: " ")
            .replacingOccurrences(of: "\\s+,", with: ",", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whole-token match so "road" does not hit "roadster", "ring" does not hit "spring".
    static func containsToken(_ blob: String, _ token: String) -> Bool {
        let hay = blob.lowercased()
        let needle = token.lowercased()
        guard !needle.isEmpty else { return false }
        if needle.contains(where: { $0.isWhitespace }) {
            return hay.contains(needle)
        }
        var start = hay.startIndex
        while let range = hay.range(of: needle, range: start..<hay.endIndex) {
            let beforeOK = range.lowerBound == hay.startIndex
                || !hay[hay.index(before: range.lowerBound)].isLetter
            let afterOK = range.upperBound == hay.endIndex
                || !hay[range.upperBound].isLetter
            if beforeOK && afterOK { return true }
            start = range.upperBound
        }
        return false
    }

    static func inferredScale(title: String, prompt: String, current: DirectorScale) -> DirectorScale {
        let blob = title + " " + prompt
        if ["mug", "cup", "bowl", "teapot"].contains(where: { containsToken(blob, $0) }) {
            return .mug
        }
        if [
            "church", "cathedral", "castle", "lighthouse", "cabin", "longhouse",
            "temple", "tower", "keep", "mountain", "peak", "volcano"
        ].contains(where: { containsToken(blob, $0) }) {
            return .building
        }
        if [
            "car", "vehicle", "truck", "racer", "automobile", "roadster",
            "coupe", "porsche", "ferrari", "jaguar", "sedan", "supercar",
            "plane", "airplane", "jet", "motorcycle", "helicopter", "boat"
        ].contains(where: { containsToken(blob, $0) }) {
            return .tabletop
        }
        if ["knight", "armor", "statue"].contains(where: { containsToken(blob, $0) }) {
            return .tabletop
        }
        if [
            "backpack", "lamp", "helmet", "guitar", "basket", "carriage",
            "cart", "fountain", "satchel", "winch"
        ].contains(where: { containsToken(blob, $0) }) {
            return .figurine
        }
        if current == .tabletop {
            return .figurine
        }
        return current
    }

    static func isGroundLike(_ part: CompiledPart) -> Bool {
        let blob = (part.title + " " + part.shapEPrompt).lowercased()
        let keys = [
            "cobble", "cobblestone", "cobblestones", "pavement", "gravel", "ground", "floor",
            "grass", "mist", "fog", "puddle", "wet cobble", "sky", "atmosphere",
            "racetrack", "race track", "circular track", "asphalt", "tarmac",
            "circuit", "roadway", "oval track"
        ]
        if keys.contains(where: { containsToken(blob, $0) }) { return true }
        let bareGround = ["track", "tracks", "ring", "rings", "hoop", "hoops", "road", "roads"]
        guard bareGround.contains(where: { containsToken(blob, $0) }) else { return false }
        let vehicle = [
            "car", "truck", "bike", "engine", "roadster", "coupe", "vehicle",
            "motorcycle", "racer", "automobile"
        ]
        return !vehicle.contains(where: { containsToken(blob, $0) })
    }

    static func inferredMaterial(title: String, prompt: String, current: DirectorMaterial) -> DirectorMaterial {
        if current != .vertexColor { return current }
        let blob = title + " " + prompt
        if ["ceramic", "mug", "cup", "vase", "bowl"].contains(where: { containsToken(blob, $0) }) {
            return .ceramic
        }
        if ["wood", "book", "sketch"].contains(where: { containsToken(blob, $0) }) {
            return .wood
        }
        if [
            "metal", "lamp", "tin", "iron", "knight", "silver", "anvil", "winch",
            "car", "truck", "racer", "vehicle", "coupe", "roadster",
            "porsche", "ferrari", "jaguar", "airplane", "plane", "jet", "motorcycle"
        ].contains(where: { containsToken(blob, $0) }) {
            return .metal
        }
        if ["oak", "hemp", "leather"].contains(where: { containsToken(blob, $0) }) {
            return .wood
        }
        if ["glass", "bottle", "jar"].contains(where: { containsToken(blob, $0) }) {
            return .glass
        }
        return current
    }

    /// Explicit tagging height, or unspecified so code may use looksAirborne.
    enum TaggedHeight: Equatable, Sendable {
        case floor
        case airborne
        case unspecified
    }

    /// Why a mesh prompt must not be sent to Shap-E.
    enum ObjectPromptIssue: Equatable, Sendable {
        case empty
        case fieldLabels
        case wholeScene
        case genericOnly
    }

    /// One named object from a scene brief.
    struct SceneObject: Equatable, Sendable, Identifiable {
        var id: UUID
        var title: String
        var shapEPrompt: String
        var sourcePhrase: String
        var isHero: Bool
        var prefersAirborne: Bool
    }

    /// Named objects + setting, from content tagging or the code fallback.
    struct TaggedSceneCast: Equatable, Sendable {
        var setting: String
        var objects: [SceneObject]
    }

    /// Pull "X as the hero, Y, Z" out of a scene brief. Lighting/palette clauses are dropped.
    /// Does not regex-split "under" / "over" — one clause stays one object so the director can assign pins.
    static func sceneCast(from scene: String) -> (setting: String, objects: [SceneObject]) {
        let brief = scene.trimmingCharacters(in: .whitespacesAndNewlines)
        let halves = brief.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        let setting: String
        let inventory: String
        if halves.count == 2 {
            setting = halves[0].trimmingCharacters(in: .whitespacesAndNewlines)
            inventory = String(halves[1])
        } else {
            setting = brief
            inventory = brief
        }
        var objects: [SceneObject] = []
        for raw in inventory.split(separator: ",") {
            var phrase = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if phrase.lowercased().hasPrefix("and ") {
                phrase = String(phrase.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !phrase.isEmpty, !isAtmosphereClause(phrase) else { continue }
            let hero = phrase.localizedCaseInsensitiveContains("as the hero")
                || phrase.range(of: #"\bas hero\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            phrase = phrase.replacingOccurrences(of: " as the hero", with: "", options: .caseInsensitive)
            phrase = phrase.replacingOccurrences(of: " as hero", with: "", options: .caseInsensitive)
            phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else { continue }
            objects.append(makeObject(phrase, hero: hero, prefersAirborne: looksAirborne(phrase)))
        }
        if !objects.isEmpty, !objects.contains(where: \.isHero) {
            objects[0].isHero = true
        }
        return (setting, objects)
    }

    /// Moon, lantern, bird — things that belong on a lifted pin.
    static func looksAirborne(_ phrase: String) -> Bool {
        let keys = [
            "moon", "sun", "star", "stars", "cloud", "clouds",
            "bird", "birds", "kite", "balloon", "lantern", "lanterns"
        ]
        return keys.contains { containsToken(phrase, $0) }
    }

    /// Timeout backup when the director cannot split a spatial sentence.
    /// "a darkened knight under a pale moon" → knight on the floor, moon in the air.
    static func spatialPair(from scene: String) -> (floor: SceneObject, airborne: SceneObject)? {
        var text = scene.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains(",") { return nil }
        let halves = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        if halves.count == 2 {
            text = String(halves[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.contains(",") { return nil }
        }
        let under = #"^(.+?)\s+(?:under|beneath|below|underneath)\s+((?:a|an|the)\s+.+)$"#
        if let floor = firstCapture(text, under, group: 1),
           let air = firstCapture(text, under, group: 2) {
            return (
                makeObject(floor, hero: true, prefersAirborne: false),
                makeObject(air, hero: false, prefersAirborne: true)
            )
        }
        let over = #"^(.+?)\s+(?:over|above)\s+((?:a|an|the)\s+.+)$"#
        if let air = firstCapture(text, over, group: 1),
           let floor = firstCapture(text, over, group: 2) {
            return (
                makeObject(floor, hero: true, prefersAirborne: false),
                makeObject(air, hero: false, prefersAirborne: true)
            )
        }
        return nil
    }

    static func makeObject(
        _ phrase: String,
        hero: Bool,
        prefersAirborne: Bool,
        id: UUID = UUID()
    ) -> SceneObject {
        var cleaned = phrase.replacingOccurrences(of: " as the hero", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: " as hero", with: "", options: .caseInsensitive)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        var prompt = cleaned
        let lower = prompt.lowercased()
        if !lower.hasPrefix("a ") && !lower.hasPrefix("an ") && !lower.hasPrefix("the ") {
            prompt = "a " + prompt
        }
        return SceneObject(
            id: id,
            title: shortObjectTitle(cleaned),
            shapEPrompt: objectPrompt(prompt),
            sourcePhrase: cleaned,
            isHero: hero,
            prefersAirborne: prefersAirborne
        )
    }

    /// Lowercased, articles stripped, whitespace collapsed. Conservative duplicate key.
    static func normalizedIdentityKey(_ phrase: String) -> String {
        let stop: Set<String> = ["a", "an", "the"]
        return phrase
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { !stop.contains($0) && !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Accept a tagged name once. Trust structured height; heuristic only if unspecified.
    static func ingestTaggedObject(
        name: String,
        height: TaggedHeight,
        isHero: Bool,
        seenKeys: inout Set<String>
    ) -> SceneObject? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAtmosphereClause(trimmed) else { return nil }
        let key = normalizedIdentityKey(trimmed)
        guard !key.isEmpty, seenKeys.insert(key).inserted else { return nil }
        let airborne: Bool
        switch height {
        case .floor: airborne = false
        case .airborne: airborne = true
        case .unspecified: airborne = looksAirborne(trimmed)
        }
        return makeObject(trimmed, hero: isHero, prefersAirborne: airborne)
    }

    /// Structural failures only. Paraphrase ("rusty steel" vs "rusted iron") is allowed.
    static func objectPromptIssue(_ prompt: String, scene: String? = nil) -> ObjectPromptIssue? {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .empty }
        let lower = text.lowercased()
        let labels = ["shapeprompt:", "scale:", "material:", "pinindex:", "title:", "fillstoneighbors:"]
        if labels.contains(where: { lower.contains($0) }) {
            return .fieldLabels
        }
        if let scene {
            let sceneKey = normalizedIdentityKey(scene)
            let promptKey = normalizedIdentityKey(text)
            if !sceneKey.isEmpty, promptKey == sceneKey {
                return .wholeScene
            }
            if sceneKey.count > 48, promptKey.contains(sceneKey) {
                return .wholeScene
            }
        }
        if isGenericOnlyPrompt(text) { return .genericOnly }
        return nil
    }

    static func isGenericOnlyPrompt(_ prompt: String) -> Bool {
        if containsToken(prompt, "complementary"),
           containsToken(prompt, "prop") || containsToken(prompt, "volume") {
            return true
        }
        let generic: Set<String> = [
            "a", "an", "the", "one", "small", "closed", "volume", "volumes",
            "object", "objects", "prop", "props", "complementary", "chunky",
            "silhouette", "mass", "dressing", "extra", "leftover", "for",
            "scene", "setting", "place", "same", "this", "that", "not",
            "tree", "trees", "and", "or", "with", "of", "to", "in"
        ]
        let leftover = prompt
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { !generic.contains($0) && !$0.isEmpty }
        return leftover.isEmpty
    }

    private static func firstCapture(_ text: String, _ pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > group,
              let swiftRange = Range(match.range(at: group), in: text)
        else { return nil }
        let value = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func isAtmosphereClause(_ phrase: String) -> Bool {
        let keepers = ["bottle", "vial", "flask", "jar", "glass"]
        if keepers.contains(where: { containsToken(phrase, $0) }) {
            return false
        }
        if ["glow", "palette", "lighting", "overcast"].contains(where: { containsToken(phrase, $0) }) {
            return true
        }
        if containsToken(phrase, "light") || containsToken(phrase, "sun") {
            return true
        }
        if containsToken(phrase, "amber") || phrase.lowercased().contains("soot-stained") {
            return true
        }
        return false
    }

    static func shortObjectTitle(_ phrase: String) -> String {
        let stop: Set<String> = ["a", "an", "the", "as", "hero"]
        let words = phrase
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
            .filter { !stop.contains($0.lowercased()) }
        guard let last = words.last else { return "Object" }
        if words.count >= 2 {
            let prev = words[words.count - 2]
            if prev.lowercased().hasSuffix("'s") {
                return (prev + " " + last).capitalized
            }
        }
        return last.capitalized
    }

    static func centerPin(among empty: [PlacementPin], all: [PlacementPin]) -> PlacementPin {
        let pts = all.isEmpty ? empty : all
        let cx = pts.map(\.x).reduce(0, +) / Float(max(pts.count, 1))
        let cz = pts.map(\.z).reduce(0, +) / Float(max(pts.count, 1))
        return empty.min {
            hypot($0.x - cx, $0.z - cz) < hypot($1.x - cx, $1.z - cz)
        } ?? empty[0]
    }

    /// Prefer content-tagging output. If the tagger returns fewer than two objects
    /// and the sentence is "X under/over Y", use the spatial pair so moon still lifts.
    static func resolvedCast(scene: String, tagged: TaggedSceneCast?) -> TaggedSceneCast {
        let code = sceneCast(from: scene)
        let spatialObjects: [SceneObject]? = spatialPair(from: scene).map { [$0.floor, $0.airborne] }

        if let tagged {
            let objects = tagged.objects.filter {
                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !isAtmosphereClause($0.title)
                    && !isAtmosphereClause($0.shapEPrompt)
            }
            var setting = tagged.setting.trimmingCharacters(in: .whitespacesAndNewlines)
            if setting.isEmpty { setting = code.setting }
            if objects.count >= 2 {
                return TaggedSceneCast(setting: setting, objects: ensureHero(objects))
            }
            if let spatialObjects, objects.count < 2 {
                return TaggedSceneCast(setting: setting, objects: spatialObjects)
            }
            if !objects.isEmpty {
                return TaggedSceneCast(setting: setting, objects: ensureHero(objects))
            }
        }
        if let spatialObjects, code.objects.count < 2 {
            return TaggedSceneCast(setting: code.setting, objects: spatialObjects)
        }
        return TaggedSceneCast(setting: code.setting, objects: code.objects)
    }

    private static func ensureHero(_ objects: [SceneObject]) -> [SceneObject] {
        var objects = objects
        guard !objects.isEmpty, !objects.contains(where: \.isHero) else { return objects }
        if let i = objects.firstIndex(where: { !$0.prefersAirborne }) {
            objects[i].isHero = true
        } else {
            objects[0].isHero = true
        }
        return objects
    }

    /// Named objects from the brief onto empty pins. Hero sits on the pin closest to the cluster center
    /// among pins of the right height. Sky objects (moon, lantern) take lifted pins.
    /// Leftover pins are returned so extras can be invented as complementary dressing.
    static func namedPinJobs(
        empty: [PlacementPin],
        allPins: [PlacementPin],
        scene: String,
        already: [String],
        seed: Int,
        alreadyIDs: Set<UUID> = []
    ) -> (jobs: [PinAssignment], extraPins: [PlacementPin], setting: String) {
        let (setting, objects) = sceneCast(from: scene)
        return namedPinJobs(
            empty: empty,
            allPins: allPins,
            cast: TaggedSceneCast(setting: setting, objects: objects),
            already: already,
            seed: seed,
            alreadyIDs: alreadyIDs
        )
    }

    static func namedPinJobs(
        empty: [PlacementPin],
        allPins: [PlacementPin],
        cast: TaggedSceneCast,
        already: [String],
        seed: Int,
        alreadyIDs: Set<UUID> = []
    ) -> (jobs: [PinAssignment], extraPins: [PlacementPin], setting: String) {
        let setting = cast.setting
        let usedKeys = Set(already.map { normalizedIdentityKey($0) }.filter { !$0.isEmpty })
        var needed = cast.objects.filter { obj in
            if alreadyIDs.contains(obj.id) { return false }
            let phraseKey = normalizedIdentityKey(obj.sourcePhrase)
            let titleKey = normalizedIdentityKey(obj.title)
            if usedKeys.contains(phraseKey) { return false }
            if usedKeys.contains(titleKey) { return false }
            return true
        }
        guard !empty.isEmpty, !needed.isEmpty else {
            return ([], empty, setting)
        }
        var remaining = empty
        var jobs: [PinAssignment] = []
        var nextSeed = seed

        if let hero = needed.first(where: \.isHero),
           let pin = takePin(
            prefersAirborne: hero.prefersAirborne,
            remaining: &remaining,
            all: allPins,
            preferCenter: true
           ) {
            needed.removeAll { $0.id == hero.id }
            jobs.append(pinJob(hero, pin: pin, seed: nextSeed, hero: true, route: .named))
            nextSeed &+= 1
        }
        for obj in needed {
            guard let pin = takePin(
                prefersAirborne: obj.prefersAirborne,
                remaining: &remaining,
                all: allPins,
                preferCenter: false
            ) else { break }
            jobs.append(pinJob(obj, pin: pin, seed: nextSeed, hero: false, route: .named))
            nextSeed &+= 1
        }
        return (jobs, remaining, setting)
    }

    /// Director timeout / failure: comma lists stay in code; "under a moon" still splits by pin height.
    static func fallbackPinJobs(
        pins: [PlacementPin],
        scene: String,
        seed: Int,
        already: [String],
        allPins: [PlacementPin]
    ) -> [PinAssignment] {
        let (_, objects) = sceneCast(from: scene)
        if objects.count < 2, pins.count >= 2,
           let spatial = spatialPinJobs(
            empty: pins,
            allPins: allPins,
            scene: scene,
            already: already,
            seed: seed
           ) {
            return spatial
        }
        let split = namedPinJobs(
            empty: pins,
            allPins: allPins,
            scene: scene,
            already: already,
            seed: seed
        )
        if split.jobs.isEmpty {
            return []
        }
        return split.jobs.map { job in
            var copy = job
            copy.route = .fallback
            return copy
        }
    }

    static func spatialPinJobs(
        empty: [PlacementPin],
        allPins: [PlacementPin],
        scene: String,
        already: [String],
        seed: Int
    ) -> [PinAssignment]? {
        guard let pair = spatialPair(from: scene) else { return nil }
        let used = Set(already.map { $0.lowercased() })
        var remaining = empty
        var jobs: [PinAssignment] = []
        var nextSeed = seed
        if !used.contains(pair.floor.title.lowercased()),
           let pin = takePin(
            prefersAirborne: false,
            remaining: &remaining,
            all: allPins,
            preferCenter: true
           ) {
            jobs.append(pinJob(pair.floor, pin: pin, seed: nextSeed, hero: true, route: .fallback))
            nextSeed &+= 1
        }
        if !used.contains(pair.airborne.title.lowercased()),
           let pin = takePin(
            prefersAirborne: true,
            remaining: &remaining,
            all: allPins,
            preferCenter: false
           ) {
            jobs.append(pinJob(pair.airborne, pin: pin, seed: nextSeed, hero: false, route: .fallback))
            nextSeed &+= 1
        }
        guard !jobs.isEmpty else { return nil }
        return jobs
    }

    private static func takePin(
        prefersAirborne: Bool,
        remaining: inout [PlacementPin],
        all: [PlacementPin],
        preferCenter: Bool
    ) -> PlacementPin? {
        let isAir: (PlacementPin) -> Bool = { $0.y >= PlacementPin.airborneThreshold }
        let match = remaining.filter { prefersAirborne ? isAir($0) : !isAir($0) }
        let pool = match.isEmpty ? remaining : match
        guard !pool.isEmpty else { return nil }
        let pin = preferCenter ? centerPin(among: pool, all: all) : pool[0]
        remaining.removeAll { $0.id == pin.id }
        return pin
    }

    /// Leftover pins stay empty. Do not invent a generic closed-prop sentence.
    static func complementaryPinJobs(
        pins _: [PlacementPin],
        setting _: String,
        seed _: Int
    ) -> [PinAssignment] {
        []
    }

    private static func pinJob(
        _ obj: SceneObject,
        pin: PlacementPin,
        seed: Int,
        hero: Bool,
        route: PinPlanRoute
    ) -> PinAssignment {
        let scale = hero
            ? .tabletop
            : inferredScale(title: obj.title, prompt: obj.shapEPrompt, current: .figurine)
        return PinAssignment(
            pinID: pin.id,
            title: obj.title,
            shapEPrompt: obj.shapEPrompt,
            scale: scale,
            material: inferredMaterial(title: obj.title, prompt: obj.shapEPrompt, current: .vertexColor),
            fillsToNeighbors: false,
            seed: seed,
            inventoryID: obj.id,
            route: route
        )
    }

    /// Keep the cluster around the origin so the default camera actually sees it.
    static func recenter(_ parts: [CompiledPart]) -> [CompiledPart] {
        guard parts.count >= 2 else { return parts }
        let cx = parts.map(\.offsetX).reduce(0, +) / Float(parts.count)
        let cz = parts.map(\.offsetZ).reduce(0, +) / Float(parts.count)
        return parts.map { part in
            var p = part
            p.offsetX -= cx
            p.offsetZ -= cz
            p.offsetX = min(0.9, max(-0.9, p.offsetX))
            p.offsetZ = min(0.9, max(-0.9, p.offsetZ))
            return p
        }
    }

    static func summarizePinPlan(
        named: Int,
        extras: Int,
        leftoverPins: Int,
        extrasBudget: Int,
        extrasFailed: Bool
    ) -> String {
        let generated = named + extras
        var head = "\(generated) object\(generated == 1 ? "" : "s") generated"
        if extras > 0 {
            head = "\(named) object\(named == 1 ? "" : "s") generated; \(extras) extra\(extras == 1 ? "" : "s")"
        }
        guard leftoverPins > 0 else { return head }
        let pinWord = leftoverPins == 1 ? "pin" : "pins"
        if extrasBudget <= 0 {
            return "\(head); \(leftoverPins) \(pinWord) left empty (extra props off)"
        }
        if extrasFailed {
            return "\(head); \(leftoverPins) \(pinWord) left empty because extra planning failed"
        }
        return "\(head); \(leftoverPins) \(pinWord) left empty"
    }

    /// Shap-E meshes are ~1 unit wide; LLM offsets of 0.1 m stack them. Push apart.
    static func separate(_ parts: [CompiledPart]) -> [CompiledPart] {
        var result = parts.filter { !isGroundLike($0) }
        guard result.count >= 2 else { return result }

        func radius(_ part: CompiledPart) -> Float {
            max(0.28, part.placementScale * 1.15)
        }

        for _ in 0..<10 {
            for i in 0..<result.count {
                for j in (i + 1)..<result.count {
                    let dx = result[j].offsetX - result[i].offsetX
                    let dz = result[j].offsetZ - result[i].offsetZ
                    let dist = hypot(dx, dz)
                    let need = radius(result[i]) + radius(result[j]) + 0.12
                    if dist < 0.02 {
                        let angle = Float(j) * (2 * .pi / Float(result.count))
                        result[j].offsetX += cos(angle) * need
                        result[j].offsetZ += sin(angle) * need
                        continue
                    }
                    if dist < need {
                        let push = (need - dist) * 0.5
                        let nx = dx / dist
                        let nz = dz / dist
                        result[i].offsetX -= nx * push
                        result[i].offsetZ -= nz * push
                        result[j].offsetX += nx * push
                        result[j].offsetZ += nz * push
                    }
                }
            }
        }
        return recenter(result)
    }
}

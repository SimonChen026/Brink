import Foundation

/// Mechanical properties of an injury / illness kind.
public struct InjuryKind: Sendable {
    public let name: String
    /// Severity healed per day when the person is stable (fed, warm, hydrated).
    public let heal: Double
    /// Severity gained per day if untreated (infection-like conditions).
    public let worsens: Double
    /// Daily infection chance when severity > openAbove and untreated.
    public let infect: Double
    public let openAbove: Double
    /// Health damage per day per severity point.
    public let dmg: Double
    /// Extra fluid loss in liters/day at severity 50.
    public let fluid: Double
    /// Morale loss per day per severity point.
    public let pain: Double
    /// Severity above which heavy tasks are impossible.
    public let noHeavyAbove: Double
    /// Severity above which the person can't do outdoor / mobility tasks.
    public let immobileAbove: Double
    /// Cause label when it kills someone.
    public let deathCause: String

    // Healing is per day while stable. Bone, burnt and frozen tissue mend over weeks: a splinted fracture ≈0.5/day
    // (0.2 unsplinted), a dressed burn ≈1/day, dressed frostbite ≈0.7/day (treated ×1.6 for everything but fractures).
    public static let table: [String: InjuryKind] = [
        "laceration": InjuryKind(name: "割伤", heal: 4, worsens: 0, infect: 0.07, openAbove: 15, dmg: 0.04, fluid: 0, pain: 0.03, noHeavyAbove: 60, immobileAbove: 101, deathCause: "失血"),
        "fracture": InjuryKind(name: "骨折", heal: 0.5, worsens: 0, infect: 0.03, openAbove: 60, dmg: 0.02, fluid: 0, pain: 0.06, noHeavyAbove: 25, immobileAbove: 50, deathCause: "骨折并发症"),
        "sprain": InjuryKind(name: "扭伤", heal: 7, worsens: 0, infect: 0, openAbove: 101, dmg: 0, fluid: 0, pain: 0.03, noHeavyAbove: 40, immobileAbove: 75, deathCause: "外伤"),
        "burn": InjuryKind(name: "烧伤", heal: 0.65, worsens: 0, infect: 0.09, openAbove: 20, dmg: 0.05, fluid: 0.6, pain: 0.08, noHeavyAbove: 50, immobileAbove: 85, deathCause: "烧伤"),
        "frostbite": InjuryKind(name: "冻伤", heal: 0.45, worsens: 0, infect: 0.05, openAbove: 40, dmg: 0.02, fluid: 0, pain: 0.05, noHeavyAbove: 50, immobileAbove: 70, deathCause: "冻伤坏疽"),
        "crush": InjuryKind(name: "挤压伤", heal: 1, worsens: 0, infect: 0.04, openAbove: 40, dmg: 0.07, fluid: 0.3, pain: 0.08, noHeavyAbove: 20, immobileAbove: 35, deathCause: "挤压综合征"),
        "concussion": InjuryKind(name: "脑震荡", heal: 5, worsens: 0, infect: 0, openAbove: 101, dmg: 0.02, fluid: 0, pain: 0.04, noHeavyAbove: 60, immobileAbove: 90, deathCause: "颅脑损伤"),
        "trauma": InjuryKind(name: "内伤", heal: 1.5, worsens: 0, infect: 0, openAbove: 101, dmg: 0.06, fluid: 0, pain: 0.06, noHeavyAbove: 30, immobileAbove: 60, deathCause: "内脏损伤"),
        // untreated +5/day; dressed and fed −3/day; antibiotics −25/day. Sepsis (×3 damage) see progressInjuries.
        "infection": InjuryKind(name: "伤口感染", heal: 0, worsens: 5, infect: 0, openAbove: 101, dmg: 0.08, fluid: 0.4, pain: 0.05, noHeavyAbove: 40, immobileAbove: 70, deathCause: "感染（败血症）"),
        "illness": InjuryKind(name: "疾病", heal: 3, worsens: 2, infect: 0, openAbove: 101, dmg: 0.06, fluid: 0.3, pain: 0.04, noHeavyAbove: 40, immobileAbove: 75, deathCause: "疾病"),
        "dysentery": InjuryKind(name: "腹泻", heal: 6, worsens: 0, infect: 0, openAbove: 101, dmg: 0.03, fluid: 2.0, pain: 0.03, noHeavyAbove: 50, immobileAbove: 80, deathCause: "腹泻脱水"),
        "altitude": InjuryKind(name: "高原反应", heal: 6, worsens: 6, infect: 0, openAbove: 101, dmg: 0.03, fluid: 0.2, pain: 0.04, noHeavyAbove: 40, immobileAbove: 70, deathCause: "高原脑水肿"),
        "poisoning": InjuryKind(name: "中毒", heal: 10, worsens: 0, infect: 0, openAbove: 101, dmg: 0.12, fluid: 0.5, pain: 0.05, noHeavyAbove: 40, immobileAbove: 70, deathCause: "中毒")
    ]

    public static let enNames: [String: String] = [
        "laceration": "cut", "fracture": "fracture", "sprain": "sprain", "burn": "burn", "frostbite": "frostbite",
        "crush": "crush injury", "concussion": "concussion", "trauma": "internal injury", "infection": "wound infection",
        "illness": "illness", "dysentery": "diarrhea", "altitude": "altitude sickness", "poisoning": "poisoning"
    ]

    /// Display name of an injury kind.
    public static func name(_ kind: String, _ lang: Lang = Loc.ui) -> String {
        lang == .en ? (enNames[kind] ?? kind) : (table[kind]?.name ?? kind)
    }

    public static func severityLabel(_ s: Double, _ lang: Lang = Loc.ui) -> String {
        switch s {
        case ..<20: return Loc.pick("轻微", "minor", lang)
        case ..<45: return Loc.pick("中度", "moderate", lang)
        case ..<70: return Loc.pick("严重", "serious", lang)
        default: return Loc.pick("危重", "critical", lang)
        }
    }

    /// Kinds that first aid can set right only once (splint, dress, rewarm): after that, only time heals them.
    public static let firstAidOnce: Set<String> = ["fracture", "crush", "burn", "frostbite", "trauma"]

    /// Body parts you stand and walk on (the scenario's original wording, Chinese or English).
    static let weightBearing = ["腿", "脚", "足", "踝", "胯", "髋", "骨盆", "膝", "胫", "腓", "股骨", "跟骨",
                                "leg", "foot", "feet", "ankle", "hip", "pelvi", "knee", "shin", "thigh", "femur", "tibia", "fibula", "heel"]

    /// A broken leg, foot, ankle, hip or pelvis: nobody walks on it until the bone has knit.
    /// Looks at the language-independent keys, so a game plays the same in every language.
    public static func bearsWeight(_ inj: Injury) -> Bool {
        let text = [inj.partKey ?? inj.part, inj.labelKey ?? inj.label].compactMap { $0?.lowercased() }.joined(separator: " ")
        return weightBearing.contains { text.contains($0) }
    }
}

/// Physiological constants. Units: °C, liters, kcal, kg, hours.
public enum Physio {
    public static let kcalPerKgFat = 7700.0
    /// Neutral ambient temperature for a resting naked person.
    public static let comfortBase = 28.0
    /// Each clo of clothing lowers the comfortable ambient temperature by this much.
    public static let comfortPerClo = 8.0
    /// °C/hour of core cooling per °C of uncompensated cold stress.
    public static let coolingRate = 0.010
    /// Max °C of cold stress the body can offset by shivering/vasoconstriction.
    public static let compensationBase = 18.0
    /// kcal/hour burned per °C of compensated cold stress.
    public static let shiverKcal = 6.0

    public static func essentialFatFraction(female: Bool) -> Double {
        female ? 0.11 : 0.035
    }

    public static func activityShift(_ ex: Exertion) -> Double {
        switch ex {
        case .rest: return 0
        case .light: return 5
        case .heavy: return 10
        }
    }

    public static func metabolicMultiplier(_ ex: Exertion, working: Bool) -> Double {
        guard working else { return 1.1 }
        switch ex {
        case .rest: return 1.15
        case .light: return 2.0
        case .heavy: return 3.4
        }
    }

    public static func waterFactor(_ ex: Exertion, working: Bool) -> Double {
        guard working else { return 1.0 }
        switch ex {
        case .rest: return 1.0
        case .light: return 1.4
        case .heavy: return 2.0
        }
    }

    /// Liters of sweat per hour per °C of felt temperature above 26 °C, at rest (resting in shade at a 43 °C
    /// maximum comes to about 4.5 L a day with the base loss). Work multiplies it (`sweatFactor`), up to 1.8 L/h.
    public static let sweatSlope = 0.02
    public static let maxSweat = 1.8

    public static func sweatFactor(_ ex: Exertion, working: Bool) -> Double {
        guard working else { return 1.0 }
        switch ex {
        case .rest: return 1.0
        case .light: return 2.0
        case .heavy: return 4.0     // noon labour in desert sun still reaches the 1.8 L/h ceiling
        }
    }

    /// °C/hour of core warming per °C of heat stress: muscles at work add heat the body can't shed.
    public static func heatGain(working: Bool) -> Double { working ? 0.01 : 0.004 }

    /// Wind chill index (Environment Canada / US NWS, 2001): the temperature exposed skin feels in the wind.
    /// Defined for air at or below 10 °C and wind above 4.8 km/h; otherwise the air temperature itself.
    public static func windChillIndex(_ t: Double, wind v: Double) -> Double {
        guard t <= 10, v > 4.8 else { return t }
        let p = pow(v, 0.16)
        return min(t, 13.12 + 0.6215 * t - 11.37 * p + 0.3965 * t * p)
    }

    /// Chance per hour that exposed skin freezes, by the wind chill it is exposed to (Environment Canada's bands:
    /// −28 to −39 frostbite within ~30 min of bare skin, −40 to −47 within 10, below −48 within minutes).
    public static func frostbiteRisk(windChill wc: Double) -> Double {
        switch wc {
        case ...(-48): return 0.30
        case ...(-40): return 0.10
        case ...(-28): return 0.02
        default: return 0
        }
    }

    /// How much of that risk gets through the clothes: mitts and a face cover come with proper cold-weather kit
    /// (no separate items in the scenarios, so clothing insulation stands in): clo ≤ 1.5 → all, clo ≥ 2.5 → 30%.
    public static func frostbiteCover(clo: Double) -> Double {
        min(1, max(0.3, 1 - 0.7 * (clo - 1.5)))
    }

    /// `labelKey` of an infection that has gone into the blood.
    public static let sepsisKey = "败血症"

    /// Fraction of the solar bonus at a given clock hour (bell curve 7–18h, peak 13h).
    public static func sunCurve(_ hour: Int) -> Double {
        guard hour >= 7 && hour < 18 else { return 0 }
        let x = (Double(hour) - 13.0) / 4.0
        return max(0, exp(-x * x))
    }

    public static func coreLabel(_ c: Double, _ lang: Lang = Loc.ui) -> String {
        switch c {
        // clinical stages: mild 35–32 °C (shivering), moderate 32–28 °C, severe below 28 °C
        case ..<28: return Loc.pick("重度失温", "severe hypothermia", lang)
        case ..<32: return Loc.pick("中度失温", "moderate hypothermia", lang)
        case ..<35: return Loc.pick("轻度失温", "mild hypothermia", lang)
        case ..<36: return Loc.pick("发冷", "chilled", lang)
        case ..<37.6: return Loc.pick("正常", "normal", lang)
        case ..<39: return Loc.pick("发热", "feverish", lang)
        case ..<40.5: return Loc.pick("中暑/高热", "heat exhaustion / high fever", lang)
        default: return Loc.pick("热射病", "heatstroke", lang)
        }
    }

    public static func dehydrationLabel(_ pct: Double, _ lang: Lang = Loc.ui) -> String {
        switch pct {
        case ..<1.5: return Loc.pick("不渴", "not thirsty", lang)
        case ..<3: return Loc.pick("口渴", "thirsty", lang)
        case ..<6: return Loc.pick("脱水", "dehydrated", lang)
        case ..<10: return Loc.pick("严重脱水", "severely dehydrated", lang)
        default: return Loc.pick("濒临衰竭", "on the verge of collapse", lang)
        }
    }

    public static func hungerLabel(_ ema: Double, _ lang: Lang = Loc.ui) -> String {
        switch ema {
        case 0.85...: return Loc.pick("吃得饱", "well fed", lang)
        case 0.55..<0.85: return Loc.pick("有点饿", "a bit hungry", lang)
        case 0.3..<0.55: return Loc.pick("饥饿", "hungry", lang)
        case 0.1..<0.3: return Loc.pick("严重饥饿", "starving", lang)
        default: return Loc.pick("饥荒", "famished", lang)
        }
    }

    public static func fatigueLabel(_ f: Double, _ lang: Lang = Loc.ui) -> String {
        switch f {
        case ..<25: return Loc.pick("精力充沛", "rested", lang)
        case ..<50: return Loc.pick("有些累", "a little tired", lang)
        case ..<75: return Loc.pick("疲惫", "tired", lang)
        default: return Loc.pick("精疲力竭", "exhausted", lang)
        }
    }

    public static func moraleLabel(_ m: Double, _ lang: Lang = Loc.ui) -> String {
        switch m {
        case ..<15: return Loc.pick("崩溃边缘", "close to breaking", lang)
        case ..<35: return Loc.pick("低落", "low", lang)
        case ..<60: return Loc.pick("还撑得住", "holding on", lang)
        case ..<80: return Loc.pick("稳定", "steady", lang)
        default: return Loc.pick("乐观", "hopeful", lang)
        }
    }

    public static func healthLabel(_ h: Double, _ lang: Lang = Loc.ui) -> String {
        switch h {
        case ..<15: return Loc.pick("垂危", "dying", lang)
        case ..<35: return Loc.pick("很差", "very poor", lang)
        case ..<60: return Loc.pick("虚弱", "weak", lang)
        case ..<85: return Loc.pick("还行", "fair", lang)
        default: return Loc.pick("良好", "good", lang)
        }
    }

    /// English for the causes of death the engine itself writes (in Chinese).
    public static let causeEN: [String: String] = [
        "体力耗尽": "exhaustion", "失温": "hypothermia", "中暑": "heat exhaustion", "热射病": "heatstroke", "脱水": "dehydration", "饥饿": "starvation",
        "伤重": "severe injuries", "意外": "an accident", "失血": "blood loss", "骨折并发症": "complications of a fracture",
        "外伤": "injuries", "烧伤": "burns", "冻伤坏疽": "gangrene from frostbite", "挤压综合征": "crush syndrome",
        "颅脑损伤": "head injury", "内脏损伤": "internal injuries", "感染（败血症）": "infection (sepsis)", "疾病": "illness",
        "腹泻脱水": "diarrhea and dehydration", "高原脑水肿": "high-altitude cerebral edema", "中毒": "poisoning"
    ]
}

// MARK: - Hourly simulation

struct HourContext {
    var exertion: Exertion
    var working: Bool
    var outdoor: Bool
    var away: Bool
}

extension GameEngine {

    var altitude: Double {
        scenario.physiology?.altitude ?? scenario.setting.altitude ?? 0
    }

    /// Hours in a round (at least 1, so a broken scenario can't divide by zero or loop backwards).
    var hoursPerRound: Int { max(1, scenario.clock.roundHours) }

    /// Hour index (0-based, absolute from game start) at which the current round starts.
    public var roundStartHour: Int { (state.round - 1) * hoursPerRound }

    /// Hour within the current round at which the day's work begins: the first `clock.workStart` hour that falls
    /// inside this round, else one hour after the round starts.
    func workStartOffset() -> Int {
        let start = currentClockHour
        for hour in scenario.clock.workStart?.hours ?? [] {
            let off = ((hour - start) % 24 + 24) % 24
            if off < hoursPerRound { return off }
        }
        return min(1, hoursPerRound - 1)
    }

    /// Clock hour at which people on an expedition set off each day: the scenario's work start for this round,
    /// else 08:00.
    func awayStartClock() -> Int {
        guard scenario.clock.workStart != nil else { return 8 }
        return clockHour(absHour: roundStartHour + workStartOffset())
    }

    /// Marker stored with an expedition's return effects: what the trip asks of the body (see the `away` effect).
    static let awayPlanTag = "_awayplan"

    /// Exertion and hours on the move per day for someone away (default: light work, 6 hours).
    func awayPlan(_ c: CharacterState) -> (exertion: Exertion, hours: Int) {
        guard let plan = c.awayReturn?.first(where: { $0.e == GameEngine.awayPlanTag }) else { return (.light, 6) }
        let ex = plan.exertion.flatMap { Exertion(rawValue: $0) } ?? .light
        var hours = 6.0
        if case .const(let v)? = plan.hours { hours = v }
        return (ex, min(24, max(0, Int(hours.rounded()))))
    }

    public func clockHour(absHour: Int) -> Int { (scenario.clock.startHour + absHour) % 24 }
    func dayIndex(absHour: Int) -> Int { (scenario.clock.startHour + absHour) / 24 + 1 }

    public var currentDay: Int { dayIndex(absHour: roundStartHour) }
    public var currentClockHour: Int { clockHour(absHour: roundStartHour) }

    public var weatherDef: WeatherDef {
        scenario.climate.weather[state.weather] ?? WeatherDef(name: state.weather, next: [:])
    }

    /// Recompute today's high/low (called when a new calendar day starts).
    func rollDayTemperatures(day: Int) {
        let c = scenario.climate
        let w = weatherDef
        let drift = (c.drift ?? 0) * Double(day - 1)
        let noise = (c.noise ?? 1.5) * state.rng.gaussian()
        let off = w.temp ?? 0
        // harder settings bring a harsher spell: colder where it's cold, hotter where it's hot (D-053)
        let shift = state.setup.level.weatherShift
        // (heat bites harder per degree — sweat losses climb steeply — so a hot spell gets half the shift)
        let harsh = shift == 0 ? 0 : (c.tempLow < 12 ? -shift : (c.tempHigh >= 30 ? shift / 2 : 0))
        let mid = (c.tempHigh + c.tempLow) / 2 + drift + noise + off + harsh
        let amp = (c.tempHigh - c.tempLow) / 2 * (w.ampScale ?? 1)
        state.dayHigh = mid + amp
        state.dayLow = mid - amp
        state.tempDay = day
    }

    /// Air temperature at an absolute hour (diurnal cosine curve, peak at 15h).
    public func airTemp(absHour: Int) -> Double {
        let h = Double(clockHour(absHour: absHour))
        let mid = (state.dayHigh + state.dayLow) / 2
        let amp = (state.dayHigh - state.dayLow) / 2
        return mid + amp * cos(2 * .pi * (h - 15) / 24)
    }

    public var currentTemp: Double { airTemp(absHour: roundStartHour + 1) }

    /// How many °C colder exposed skin feels in the wind (air temperature minus the wind chill index).
    func windChill(_ tAir: Double, wind: Double) -> Double {
        return max(0, tAir - Physio.windChillIndex(tAir, wind: wind))
    }

    /// Is this person wet this hour (rain outdoors, a wet shelter, clothes not yet dry)?
    func isWet(_ c: CharacterState, _ ctx: HourContext) -> Bool {
        c.wetHours > 0 || (ctx.outdoor && (weatherDef.wet ?? false)) || (!ctx.outdoor && !ctx.away && (scenario.shelter.wet ?? false))
    }

    /// Effective temperature felt by a person this hour.
    func effectiveTemp(_ c: CharacterState, _ ctx: HourContext, tAir: Double, clockHour: Int, presentCount: Int) -> Double {
        let w = weatherDef
        let wind = w.wind ?? 0
        let solar = (scenario.climate.solar ?? 0) * (w.sun ?? 1) * Physio.sunCurve(clockHour)
        var t: Double
        if ctx.away {
            // bivouac in the open: improvised cover blocks some wind and, in the cold, keeps a little warmth in
            // (+ camp bonus at rest: hut, wreck, tent)
            t = tAir - windChill(tAir, wind: wind * 0.6) + (tAir < 15 ? 2 : 0) + solar * 0.5
            if !ctx.working { t = min(t + c.awayCamp, max(tAir, 24)) }
        } else if ctx.outdoor {
            t = tAir - windChill(tAir, wind: wind) + solar
        } else {
            let sh = scenario.shelter
            let integ = max(0, min(100, state.shelterIntegrity)) / 100
            var boost = sh.insulation * integ
            if state.fireLit, let fire = sh.fire { boost += fire.heat }
            boost += min(5, 0.8 * Double(max(0, presentCount - 1)))
            let cap = max(tAir, 24)
            t = min(tAir + boost, cap)
            // only the draught that gets through the walls chills, at the temperature inside
            t -= windChill(t, wind: wind * (1 - sh.windProof * integ))
            if sh.shade == false { t += solar * 0.6 }
        }
        // sea-survival know-how (HELP position, keeping still, wringing out layers) halves the wet-cold penalty
        if isWet(c, ctx) && t < 26 { t -= hasPerk(c.id, "wet") ? 3 : 6 }
        return t
    }

    /// Runs the physiological simulation for every hour of the current round.
    /// `water`: each person's water ration for the round (liters, by index in `state.characters`). It is drunk a
    /// little at a time as thirst comes; whatever is left at the end is the caller's to put back in the stock.
    func simulateRoundHours(damage: inout [String: [String: Double]], coldHours: inout [String: Double], mods: [String: BuffMods] = [:],
                            water ration: inout [Double]) {
        let hours = hoursPerRound
        let start = roundStartHour
        let w = weatherDef
        let alt = altitude
        let workOff = workStartOffset()
        let awayStart = awayStartClock()
        if ration.count < state.characters.count { ration += Array(repeating: 0, count: state.characters.count - ration.count) }

        for h in 0..<hours {
            let abs = start + h
            let day = dayIndex(absHour: abs)
            if day != state.tempDay { rollDayTemperatures(day: day) }
            let ch = clockHour(absHour: abs)
            let tAir = airTemp(absHour: abs)
            let presentCount = state.characters.filter { $0.present }.count

            for i in state.characters.indices {
                guard state.characters[i].alive else { continue }
                let c = state.characters[i]
                let def = scenario.character(c.id)
                let weight = def?.weight ?? 65
                let female = def?.isFemale ?? false

                // Where is this person and what are they doing this hour?
                var ctx = HourContext(exertion: .rest, working: false, outdoor: false, away: c.status == .away)
                if c.status == .away {
                    // on the move for the trip's hours each day (from the scenario's work start), camped the rest
                    let plan = awayPlan(c)
                    if (ch - awayStart + 24) % 24 < plan.hours {
                        ctx.exertion = plan.exertion
                        ctx.working = true
                    }
                    ctx.outdoor = true
                } else if let a = state.assignments[c.id] {
                    let (ex, outdoor, workH) = taskShape(a.task)
                    if h >= workOff && h < workOff + workH {
                        ctx.exertion = ex
                        ctx.working = true
                        ctx.outdoor = outdoor
                    }
                    if state.guards.contains(c.id) && (ch >= 22 || ch < 5) {
                        ctx.exertion = .light
                        ctx.working = true
                    }
                }

                let m = mods[c.id] ?? BuffMods()
                var tEff = effectiveTemp(c, ctx, tAir: tAir, clockHour: ch, presentCount: presentCount) + m.warm + (ctx.outdoor || ctx.away ? m.warmOut : 0)
                // sleeping next to someone: their body heat (D-053)
                if !ctx.working && !ctx.outdoor && !ctx.away { tEff += huddleWarmthNow(c.id, clockHour: ch) }
                var p = state.characters[i]

                // --- Thermal balance ---
                var clo = p.clo
                if !ctx.outdoor && !ctx.away && !ctx.working { clo += scenario.shelter.bedding ?? 0 }
                if ctx.away && !ctx.working { clo += 0.5 }
                let comfort = Physio.comfortBase - Physio.comfortPerClo * clo - Physio.activityShift(ctx.exertion)
                let stress = comfort - tEff
                let spareFat = p.fatKg - weight * Physio.essentialFatFraction(female: female)
                let fatFactor = min(1, max(0, spareFat / 4))
                let energyStatus = min(1, max(0, 0.5 * min(1, p.energyEMA) + 0.5 * fatFactor))
                var capacity = Physio.compensationBase * (0.35 + 0.65 * energyStatus) * (1 - p.fatigue / 250)
                if p.health < 30 { capacity *= 0.6 }
                if stress > capacity {
                    p.core -= (stress - capacity) * Physio.coolingRate
                    coldHours[p.id, default: 0] += 1
                } else if p.core < 37 {
                    let rewarm = 0.35 * (1 - max(0, stress) / max(capacity, 1))
                    p.core = min(37, p.core + max(0.05, rewarm))
                }
                let dehydPct = max(0, p.thirst) / weight * 100
                let heat = tEff - (comfort + 10)
                if heat > 0 {
                    // sweat stops keeping up once dehydration passes ~2% of body weight
                    p.core += heat * Physio.heatGain(working: ctx.working && ctx.exertion != .rest) * (1 + 3 * max(0, dehydPct - 2) / 8)
                } else if p.core > 37 {
                    p.core = max(37, p.core - 0.4)
                }

                // --- Energy (Kleiber scaling: BMR ≈ 70·W^0.75 kcal/day; children run hotter) ---
                let isChild = (def?.age ?? 30) < 14
                let bmrDay = 70 * pow(weight, 0.75) * (isChild ? 1.3 : 1)
                let massScale = pow(weight / 70, 0.75)
                var kcal = bmrDay / 24 * Physio.metabolicMultiplier(ctx.exertion, working: ctx.working)
                if stress > 0 { kcal += min(stress, capacity) * Physio.shiverKcal }
                if alt > 3000 { kcal *= 1.1 }
                if p.injuries.contains(where: { $0.kind == "infection" && $0.severity > 30 }) { kcal *= 1.1 }
                kcal *= m.kcal
                p.lastNeed += kcal
                p.fatKg -= 0 // energy balance settled at end of round (see settleEnergy)

                // --- Water (scaled by body mass) ---
                var water = 0.075 * Physio.waterFactor(ctx.exertion, working: ctx.working)
                if tEff > 26 {
                    water += min(Physio.maxSweat, Physio.sweatSlope * (tEff - 26) * Physio.sweatFactor(ctx.exertion, working: ctx.working))
                }
                if alt > 2500 { water += 0.015 + (alt - 2500) / 1000 * 0.008 }
                if tEff < -5 { water += 0.008 }
                // desert know-how: shade by day, slow movement, mouth closed — "ration sweat, not water"
                if hasPerk(c.id, "water") { water *= 0.88 }
                water *= m.water
                for inj in p.injuries {
                    if let k = InjuryKind.table[inj.kind], k.fluid > 0 {
                        water += k.fluid * inj.severity / 50 / 24
                    }
                }
                let loss = water * massScale + m.fluid / 24
                p.thirst += loss
                p.roundWaterLoss += loss
                // Drink from the round's ration as thirst comes: up to half a liter ahead, at most a liter an hour.
                if ration[i] > 0 {
                    let drink = min(ration[i], max(0, p.thirst + 0.5), 1.0)
                    p.thirst -= drink
                    ration[i] -= drink
                }

                // --- Wetness ---
                if (ctx.outdoor && (w.wet ?? false)) || (!ctx.outdoor && !ctx.away && (scenario.shelter.wet ?? false)) {
                    p.wetHours = max(p.wetHours, 3)
                } else if p.wetHours > 0 {
                    p.wetHours = max(0, p.wetHours - (state.fireLit && !ctx.outdoor ? 2 : 1))
                }

                // --- Fatigue ---
                if ctx.working {
                    switch ctx.exertion {
                    case .heavy: p.fatigue += 5 * m.fatigue
                    case .light: p.fatigue += 2.5 * m.fatigue
                    case .rest: p.fatigue -= 1
                    }
                } else {
                    p.fatigue -= stress > capacity ? 1.5 : 4
                }
                p.fatigue = min(100, max(0, p.fatigue))
                if ctx.outdoor { p.stats.outdoorHours += 1 }

                // --- Health damage from vitals ---
                var dmg: [String: Double] = [:]
                if p.core < 35 { dmg["失温"] = p.core < 30 ? 3 : (p.core < 33 ? 1.5 : 0.6) }
                if p.core > 40.5 {
                    // heatstroke: the brain and organs start to cook, and it gets worse by the hour
                    dmg["热射病"] = p.core > 41.5 ? 12 : 6
                } else if p.core > 39 {
                    dmg["中暑"] = p.core > 40 ? 2 : 0.5
                }
                let pct = max(0, p.thirst) / weight * 100
                if pct > 6 { dmg["脱水"] = pct > 12 ? 3 : (pct > 9 ? 1 : 0.3) }
                if spareFat < 0.5 { dmg["饥饿"] = 0.5 }
                let vitals = state.setup.level.vitalsScale
                for (cause, d0) in dmg.sorted(by: { $0.key < $1.key }) {
                    let d = d0 * vitals
                    p.health -= d
                    damage[p.id, default: [:]][cause, default: 0] += d
                }
                // natural recovery
                let maxSev = p.injuries.map(\.severity).max() ?? 0
                if dmg.isEmpty && p.core >= 36 && pct < 4 && maxSev < 40 && p.energyEMA > 0.4 {
                    p.health = min(maxHealth(p.id), p.health + (ctx.working ? 0.06 : 0.14) / vitals)
                }

                // --- Frostbite: exposed skin outdoors, by wind chill and wetness (not by core temperature) ---
                if ctx.outdoor || ctx.away {
                    var exposure = Physio.windChillIndex(tAir, wind: (w.wind ?? 0) * (ctx.away ? 0.6 : 1))
                    if ctx.away && !ctx.working { exposure += c.awayCamp }      // asleep in a hut, a wreck, a tent
                    if isWet(c, ctx) { exposure -= 6 }                           // wet gloves and skin freeze faster
                    let pFrost = Physio.frostbiteRisk(windChill: exposure) * Physio.frostbiteCover(clo: p.clo)
                    if pFrost > 0 && !p.injuries.contains(where: { $0.kind == "frostbite" && $0.severity > 30 }) && state.rng.chance(pFrost) {
                        let parts = isAnimal(p.id) ? [("爪子", "paws"), ("耳朵", "ears")]
                            : [("手指", "fingers"), ("脚趾", "toes"), ("耳朵", "ears"), ("鼻尖", "nose")]
                        let picked = state.rng.pick(parts) ?? parts[0]
                        let part = L(picked.0, picked.1)
                        state.characters[i] = p
                        addInjury(p.id, kind: "frostbite", severity: state.rng.range(15, 35), part: part, label: nil, partKey: picked.0, labelKey: nil)
                        log(.result, L("\(name(p.id)) 的\(part)冻伤了。", "\(name(p.id)) has frostbite on the \(part)."), actor: p.id)
                        p = state.characters[i]
                    }
                }

                state.characters[i] = p

                // --- Immediate death thresholds ---
                if p.core < 26 { killCharacter(p.id, cause: "失温") }
                else if p.core > 43 { killCharacter(p.id, cause: "热射病") }
                else if pct > 15 { killCharacter(p.id, cause: "脱水") }
            }
        }
    }

    /// (exertion, outdoor, work hours) for a task id, including built-in tasks.
    func taskShape(_ taskId: String) -> (Exertion, Bool, Int) {
        let defaultHours = scenario.clock.workHours ?? max(2, scenario.clock.roundHours / 3)
        switch taskId {
        case "rest": return (.rest, false, defaultHours)
        case "care": return (.light, false, max(2, defaultHours / 2))
        case "guard": return (.light, false, max(2, defaultHours / 2))
        case "comfort": return (.light, false, defaultHours)
        default:
            guard let t = scenario.task(taskId) else { return (.rest, false, defaultHours) }
            return (Exertion(rawValue: t.exertion) ?? .light, t.outdoor, t.hours ?? defaultHours)
        }
    }

    /// Settle food intake vs. expenditure into body fat and the intake EMA.
    func settleEnergy() {
        for i in state.characters.indices where state.characters[i].alive {
            var p = state.characters[i]
            let need = max(1, p.lastNeed)
            let hoursScale = 24 / Double(hoursPerRound)
            p.reportKcal = need * hoursScale
            p.reportWater = p.roundWaterLoss * hoursScale
            p.roundWaterLoss = 0
            let balance = p.lastIntake - need
            if balance < 0 {
                p.fatKg += balance / Physio.kcalPerKgFat
            } else {
                p.fatKg += balance * 0.8 / Physio.kcalPerKgFat
            }
            let ratio = min(1.3, p.lastIntake / need)
            let hoursFactor = Double(hoursPerRound) / 24
            let alpha = min(0.6, 0.4 * hoursFactor + 0.05)
            p.energyEMA = (1 - alpha) * p.energyEMA + alpha * ratio
            p.fatKg = max(0, p.fatKg)
            // Reset here (not at the very end of the round) so that energy added later by
            // scenario rules carries into the next round instead of being lost.
            p.lastIntake = 0
            p.lastNeed = 0
            state.characters[i] = p
        }
    }

    /// Round in which an injury was inflicted (0: one of the scenario's starting injuries, there from the outset).
    /// Injury ids and log ids are drawn from the same counter (`state.nextId`) and every round opens with its
    /// morning report, so an injury belongs to the round of the last log entry written before it.
    func roundInflicted(_ inj: Injury) -> Int {
        if inj.id >= GameEngine.startingInjuryIds { return 0 }
        var lo = 0, hi = state.log.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if state.log[mid].id < inj.id { lo = mid + 1 } else { hi = mid }
        }
        return lo > 0 ? state.log[lo - 1].round : 0
    }

    /// Hours since the injury, counted in whole rounds (at the end of the current round).
    func woundAge(_ inj: Injury) -> Double {
        Double(max(0, state.round - roundInflicted(inj)) * hoursPerRound)
    }

    /// An infection that has got into the blood (its label key carries the mark).
    public static func isSeptic(_ inj: Injury) -> Bool {
        inj.kind == "infection" && (inj.labelKey?.hasSuffix(Physio.sepsisKey) ?? false)
    }

    /// Marks an infection as sepsis, or clears the mark once it is pulled back (keeps any label it had).
    func setSepsis(_ inj: inout Injury, _ on: Bool) {
        let suffix = L("，并发败血症", ", now septic")
        if on {
            if let key = inj.labelKey ?? inj.label {
                inj.labelKey = key + "·" + Physio.sepsisKey
                inj.label = (inj.label ?? key) + suffix
            } else {
                inj.labelKey = Physio.sepsisKey
                inj.label = L("败血症", "sepsis")
            }
        } else if let key = inj.labelKey, key.hasSuffix(Physio.sepsisKey) {
            if key == Physio.sepsisKey {
                inj.labelKey = nil
                inj.label = nil
            } else {
                inj.labelKey = String(key.dropLast(Physio.sepsisKey.count + 1))
                if let l = inj.label, l.hasSuffix(suffix) { inj.label = String(l.dropLast(suffix.count)) }
            }
        }
    }

    /// Daily progression of injuries and illnesses (scaled by round length).
    func progressInjuries(damage: inout [String: [String: Double]], mods: [String: BuffMods] = [:]) {
        let f = Double(hoursPerRound) / 24
        let envRisk = scenario.physiology?.infectionRisk ?? 1
        for i in state.characters.indices where state.characters[i].alive {
            var p = state.characters[i]
            let m = mods[p.id] ?? BuffMods()
            let def = scenario.character(p.id)
            let weight = def?.weight ?? 65
            let pct = max(0, p.thirst) / weight * 100
            let stable = p.core >= 35.5 && pct < 5 && p.energyEMA > 0.35
            let resting = p.status == .active && (state.assignments[p.id]?.task ?? "rest") == "rest"
            var newInjuries: [Injury] = []
            var healedNames: [String] = []
            var septic: [String] = []
            for j in p.injuries.indices {
                var inj = p.injuries[j]
                guard let k = InjuryKind.table[inj.kind] else { continue }
                if inj.kind == "infection" {
                    if state.antibioticsGiven.contains(p.id) {
                        inj.severity -= 25 * f
                    } else if inj.treated {
                        // a cleaned, dressed wound: a fed, warm, watered body fights it off; a failing one can't
                        inj.severity += (stable ? -3 : 2) * f
                    } else {
                        inj.severity += k.worsens * f
                    }
                    // Sepsis: once the infection is severe, each day carries a chance that it gets into the blood.
                    if GameEngine.isSeptic(inj) {
                        if inj.severity < 40 { setSepsis(&inj, false) }
                    } else if inj.severity > 60 && state.rng.chance(0.15 * f) {
                        setSepsis(&inj, true)
                        septic.append(inj.displayName(lang))
                    }
                } else if inj.kind == "illness" || inj.kind == "altitude" {
                    let heavy = taskShape(state.assignments[p.id]?.task ?? "rest").0 == .heavy || p.status == .away
                    if heavy && inj.kind == "altitude" {
                        inj.severity += k.worsens * f
                    } else if resting || stable {
                        inj.severity -= k.heal * (inj.treated ? 1.5 : 1) * f
                    } else {
                        inj.severity += k.worsens * f
                    }
                } else {
                    var heal = k.heal * (stable ? 1 : 0.3) * m.heal
                    if inj.kind == "fracture" {
                        if !inj.treated { heal *= 0.4 }         // splinted ≈0.5/day, left as it is ≈0.2/day
                    } else if inj.treated {
                        heal *= 1.6
                    }
                    inj.severity -= heal * f
                    // an open wound starts to fester only after a day or so
                    if inj.severity > k.openAbove && k.infect > 0 && woundAge(inj) >= 24 {
                        let pInf = k.infect * envRisk * (inj.treated ? 0.3 : 1) * f * m.infection
                        if state.rng.chance(pInf) && !p.injuries.contains(where: { $0.kind == "infection" }) && !newInjuries.contains(where: { $0.kind == "infection" }) {
                            newInjuries.append(Injury(id: state.nextId, kind: "infection", severity: 20, part: inj.part, label: nil, treated: false,
                                                      partKey: inj.partKey ?? inj.part, labelKey: nil))
                            state.nextId += 1
                        }
                    }
                }
                // damage
                var d = max(0, inj.severity) * k.dmg * f
                if GameEngine.isSeptic(inj) { d *= 3 }
                if inj.kind == "altitude" && inj.severity > 70 { d *= 4 }
                if inj.kind == "laceration" && inj.severity > 50 && !inj.treated { d += inj.severity * 0.15 * f }
                if d > 0 {
                    p.health -= d
                    damage[p.id, default: [:]][k.deathCause, default: 0] += d
                }
                p.morale -= max(0, inj.severity) * k.pain * f
                inj.severity = min(100, inj.severity)
                if inj.severity <= 0 { healedNames.append(inj.displayName(lang)) }
                p.injuries[j] = inj
            }
            p.injuries.removeAll { $0.severity <= 0 }
            for n in newInjuries {
                p.injuries.append(n)
            }
            state.characters[i] = p
            if !newInjuries.isEmpty {
                log(.result, L("\(name(p.id)) 的伤口发炎了，开始发烧。", "\(name(p.id))'s wound is infected. A fever sets in."), actor: p.id)
            }
            if !septic.isEmpty {
                log(.result, L("\(name(p.id)) 的感染进了血里：败血症。高烧、寒战，人开始迷糊。", "\(name(p.id))'s infection has got into the blood: sepsis. A raging fever, the shakes, confusion."), actor: p.id)
            }
            for n in healedNames {
                log(.result, L("\(name(p.id)) 的\(n)好了。", "\(name(p.id))'s \(n) has healed."), actor: p.id)
            }
        }
        state.antibioticsGiven.removeAll()
    }

    /// Morale drift for the round.
    func updateMorale(coldHours: [String: Double], mods: [String: BuffMods] = [:]) {
        let f = Double(hoursPerRound) / 24
        let leaderTrust: Double? = state.leader.map { lid in
            let others = state.characters.filter { $0.present && $0.id != lid && !$0.isNPC }
            guard !others.isEmpty else { return 0 }
            return others.map { $0.trust[lid] ?? 0 }.reduce(0, +) / Double(others.count)
        }
        for i in state.characters.indices where state.characters[i].alive {
            var p = state.characters[i]
            let before = p.morale
            let weight = scenario.character(p.id)?.weight ?? 65
            p.morale += (50 - p.morale) * 0.04 * f
            if p.energyEMA < 0.6 { p.morale -= (0.6 - p.energyEMA) * 8 * f }
            let pct = max(0, p.thirst) / weight * 100
            if pct > 3 { p.morale -= (pct - 3) * 1.0 * f }
            p.morale -= (coldHours[p.id] ?? 0) * 0.15
            if state.fireLit && state.dayLow < 5 { p.morale += 2 * f }
            if let lt = leaderTrust, p.id != state.leader {
                if lt > 30 { p.morale += 1.5 * f } else if lt < -30 { p.morale -= 1.5 * f }
            }
            let m = mods[p.id] ?? BuffMods()
            p.morale += m.morale * f
            if p.morale < before { p.morale = before - (before - p.morale) * m.moraleLoss }
            // psychological-first-aid know-how: losses hit a quarter less hard
            if p.morale < before && hasPerk(p.id, "calm") { p.morale = before - (before - p.morale) * 0.75 }
            p.morale = min(100, max(0, p.morale))
            p.health = min(maxHealth(p.id), p.health)
            state.characters[i] = p
        }
    }

    /// Efficiency multiplier (0.2–1.2) for task output.
    /// Water deficit as a percentage of body weight.
    func dehydration(_ c: CharacterState) -> Double {
        max(0, c.thirst) / (scenario.character(c.id)?.weight ?? 65) * 100
    }

    public func efficiency(_ id: String) -> Double {
        guard let c = state.character(id) else { return 0 }
        var e = 1.0
        e -= c.fatigue / 200
        if c.energyEMA < 0.7 { e -= (0.7 - c.energyEMA) * 0.5 }
        let maxSev = c.injuries.map(\.severity).max() ?? 0
        e -= maxSev / 250
        if c.core < 35 { e -= 0.3 }
        if c.morale < 20 { e -= 0.2 }
        if c.health < 40 { e -= 0.2 }
        if c.injuries.contains(where: { $0.kind == "concussion" }) { e -= 0.15 }
        // past ~2% of body weight, every percent of water lost takes a bite out of strength and judgement
        let dehyd = dehydration(c)
        if dehyd > 2 { e -= 0.04 * (dehyd - 2) }
        e += buffMods(id).eff
        return min(1.2, max(0.2, e))
    }

    /// Whether someone can do heavy / mobile work given injuries, thirst and their state.
    public func mobility(_ id: String) -> (canHeavy: Bool, canMove: Bool) {
        guard let c = state.character(id) else { return (false, false) }
        var heavy = c.health >= 25 && c.core >= 34
        var move = c.health >= 15 && c.core >= 32
        for inj in c.injuries {
            guard let k = InjuryKind.table[inj.kind] else { continue }
            if inj.severity > k.noHeavyAbove { heavy = false }
            if inj.severity > k.immobileAbove { move = false }
            // a broken leg, ankle, foot, hip or pelvis can't take weight until the bone has knit
            if inj.kind == "fracture" && inj.severity >= 10 && InjuryKind.bearsWeight(inj) { move = false }
        }
        // badly dehydrated: no strength for heavy work past 8%, can barely stand past 12%
        let dehyd = dehydration(c)
        if dehyd > 8 { heavy = false }
        if dehyd > 12 { move = false }
        let m = buffMods(id)
        if m.noHeavy { heavy = false }
        if m.incapacitated { move = false }
        return (heavy && move, move)
    }
}

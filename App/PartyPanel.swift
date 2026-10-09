import SwiftUI
import BrinkCore

struct PartyPanel: View {
    let session: GameSession
    @Binding var inspect: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: L("幸存者", "Survivors"))
                ForEach(session.state.characters.filter { $0.status != .notJoined }) { c in
                    CharacterCard(session: session, c: c)
                        .onTapGesture { inspect = c.id }
                }
            }
        }
    }
}

struct CharacterCard: View {
    let session: GameSession
    let c: CharacterState

    var body: some View {
        let def = session.scenario.character(c.id)
        let isMe = c.id == session.humanId
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Avatar(id: c.id, name: def?.name ?? c.id, size: 28, dead: !c.alive)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(def?.name ?? c.id).font(.system(size: 13, weight: .semibold))
                        if isMe { Text(L("你", "you")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.flare) }
                        if session.state.leader == c.id { Text(L("领头", "lead")).font(.system(size: 11)).foregroundStyle(Theme.warn) }
                    }
                    Text(c.isNPC ? (def?.role ?? "") : seatLabel)
                        .font(.system(size: 11)).foregroundStyle(Theme.faint).lineLimit(1).truncationMode(.middle)
                        .help(c.isNPC ? (def?.role ?? "") : seatLabel)
                }
                Spacer()
                if session.thinking.contains(c.id) {
                    ProgressView().controlSize(.mini)
                } else if c.status != .active {
                    Chip(text: c.status.label, color: c.status == .away ? Theme.warn : (c.status == .rescued ? Theme.good : Theme.danger))
                }
            }
            if c.alive {
                vitals(def)
                let inj = c.injuries.filter { $0.severity > 4 }
                if !inj.isEmpty {
                    FlowChips(items: inj.map { ("\($0.displayName)·\(InjuryKind.severityLabel($0.severity))", $0.severity > 45 ? Theme.danger : Theme.warn) })
                }
                let statuses = session.engine.visibleBuffs(c.id, viewer: session.godView ? c.id : session.humanId)
                if !statuses.isEmpty { BuffStrip(buffs: statuses) }
            } else if c.status == .dead {
                Text(L("第 \(c.deathRound ?? 0) 回合 · \(c.deathCause ?? "")", "Round \(c.deathRound ?? 0) · \(c.deathCause ?? "")")).font(.system(size: 11)).foregroundStyle(Theme.danger.opacity(0.8))
            } else if c.status == .rescued {
                Text(L("第 \(c.rescuedRound ?? 0) 回合被救走", "Rescued in round \(c.rescuedRound ?? 0)")).font(.system(size: 11)).foregroundStyle(Theme.good.opacity(0.9))
            }
        }
        .padding(10)
        .padding(.leading, isMe ? 2 : 0)
        .background(Theme.panel)
        // you: a bone rule down the left edge
        .overlay(alignment: .leading) { if isMe { Rectangle().fill(Theme.flare).frame(width: 2) } }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .opacity(c.alive ? 1 : (c.status == .rescued ? 0.8 : 0.55))
        .contentShape(Rectangle())
    }

    /// Who plays this character (in an endless run: the player's name and level).
    var seatLabel: String {
        guard let seat = session.state.setup.chapter?.seats[c.id] else { return session.engine.controller(c.id).label }
        return session.engine.playedBy(c.id) + " · Lv\(seat.level)"
    }

    @ViewBuilder
    func vitals(_ def: CharacterDef?) -> some View {
        let w = def?.weight ?? 65
        let dehyd = max(0, c.thirst) / w * 100
        VStack(spacing: 4) {
            let cap = session.engine.maxHealth(c.id)
            row(L("健康", "HP"), value: c.health / cap, text: cap > 100 ? "\(Int(max(0, c.health)))/\(Int(cap))" : "\(Int(c.health))",
                color: c.health > 60 ? Theme.good : (c.health > 30 ? Theme.warn : Theme.danger))
            HStack(spacing: 10) {
                stat(L("体温", "Core"), String(format: "%.1f°", c.core), color: (c.core < 35.5 || c.core > 38.5) ? Theme.danger : (c.core < 36.3 ? Theme.warn : Theme.dim))
                stat(L("缺水", "Thirst"), String(format: "%.0f%%", dehyd), color: dehyd > 6 ? Theme.danger : (dehyd > 3 ? Theme.warn : Theme.dim))
                stat(L("饱腹", "Fed"), "\(Int(max(0, min(1, c.energyEMA)) * 100))%", color: c.energyEMA < 0.3 ? Theme.danger : (c.energyEMA < 0.6 ? Theme.warn : Theme.dim))
                Spacer(minLength: 0)
            }
            row(L("疲劳", "Tired"), value: c.fatigue / 100, text: "\(Int(c.fatigue))", color: c.fatigue > 70 ? Theme.warn : Theme.dim.opacity(0.7))
            row(L("士气", "Mood"), value: c.morale / 100, text: "\(Int(c.morale))", color: c.morale < 25 ? Theme.danger : Theme.dim.opacity(0.7))
        }
    }

    func row(_ label: String, value: Double, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.faint).lineLimit(1).frame(width: Loc.ui == .en ? 38 : 26, alignment: .leading)
            Meter(value: value, color: color, height: 3)
            Text(text).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.dim).lineLimit(1).fixedSize().frame(minWidth: 24, alignment: .trailing)
        }
    }

    func stat(_ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.faint)
            Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(color)
        }
    }
}

struct FlowChips: View {
    let items: [(String, Color)]
    var body: some View {
        // simple wrapping using ViewThatFits-free approach: two-column fallback
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                Chip(text: it.0, color: it.1)
            }
        }
    }
}

struct CharacterDetail: View {
    @Environment(\.dismiss) private var dismiss
    let session: GameSession
    let id: String

    var body: some View {
        let def = session.scenario.character(id)
        let c = session.state.character(id)
        let canSeeSecrets = session.godView || id == session.humanId
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Avatar(id: id, name: def?.name ?? id, size: 44, dead: !(c?.alive ?? false))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(def?.name ?? id).font(Theme.title(24))
                        Text(L("\(def?.gender ?? "")，\(def?.age ?? 0)岁，\(def?.role ?? "")", "\(def?.gender ?? ""), \(def?.age ?? 0), \(def?.role ?? "")")).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Button(L("关闭", "Close")) { dismiss() }.buttonStyle(GhostButtonStyle()).keyboardShortcut(.cancelAction)
                }
                Text(def?.bio ?? "").font(Theme.prose(14)).lineSpacing(4)
                if let def {
                    detailBlock(L("性格", "Personality"), def.personality)
                    if let v = def.voice { detailBlock(L("说话方式", "Way of talking"), v) }
                    detailBlock(L("技能", "Skills"), Skill.all.map { "\(Skill.names[$0]!) \(def.skill($0))" }.joined(separator: "  "))
                    if let seat = session.state.setup.chapter?.seats[id] {
                        let perks = (def.perks ?? []).map { Perks.name($0, Loc.ui) }
                        detailBlock(L("扮演者", "Played by"), L("\(session.engine.playedBy(id)) · Lv\(seat.level)", "\(session.engine.playedBy(id)) · Lv \(seat.level)")
                                    + (seat.certs.isEmpty ? "" : L("\n资格证：", "\nCertificates: ") + seat.certs.joined(separator: L("、", ", ")))
                                    + (perks.isEmpty ? "" : L("\n本事：", "\nKnow-how: ") + perks.joined(separator: L("、", ", ")))
                                    + L("\n技能里已经算上这位玩家的加点和资格证。", "\nThe skills above include this player's ranks and certificates."), color: Theme.flare)
                    }
                    let clo = String(format: "%.1f", c?.clo ?? def.clo)
                    detailBlock(L("体格", "Build"), L("体重 \(Int(def.weight)) kg · 体脂 \(Int(def.fat * 100))% · 衣物保温 \(clo) clo", "weight \(Int(def.weight)) kg · body fat \(Int(def.fat * 100))% · clothing \(clo) clo")
                                + "\n" + healthCapText(def))
                }
                if let c, c.alive {
                    let statuses = session.engine.visibleBuffs(id, viewer: canSeeSecrets ? id : session.humanId)
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: L("状态", "Status"))
                        if statuses.isEmpty {
                            Text(L("没有特别的增益或减益。", "No buffs or debuffs right now.")).font(.system(size: 12)).foregroundStyle(Theme.faint)
                        }
                        ForEach(statuses) { b in
                            HStack(alignment: .top, spacing: 8) {
                                Rectangle().fill(b.def.good ? Theme.good : Theme.danger).frame(width: 2).padding(.vertical, 2)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Text(b.def.name(Loc.ui)).font(.system(size: 12, weight: .semibold)).foregroundStyle(b.def.good ? Theme.good : Theme.danger)
                                        if let r = b.rounds { Text(L("还剩 \(r) 回合", "\(r) round\(r == 1 ? "" : "s") left")).font(.system(size: 11)).foregroundStyle(Theme.faint) }
                                    }
                                    Text(b.def.desc(Loc.ui)).font(.system(size: 11)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                if canSeeSecrets {
                    Divider()
                    if let s = def?.secret { detailBlock(L("秘密", "Secret") + (c?.secretRevealed == true ? L("（已揭开）", " (revealed)") : ""), s, color: Theme.secret) }
                    if let g = def?.goal { detailBlock(L("个人目标", "Personal goal"), g.text, color: Theme.secret) }
                    if let c {
                        let items = c.items.filter { $0.value > 0 && !session.scenario.itemName($0.key).isEmpty }.map { "\(session.scenario.itemName($0.key))×\(Int($0.value))" }
                        if !items.isEmpty { detailBlock(L("随身物品", "Carrying"), items.joined(separator: Loc.sep(Loc.ui))) }
                        let stash = c.stash.filter { $0.value > 0 && ($0.key == "food" || $0.key == "water") }.map { $0.key == "food" ? L("食物 \(Int($0.value)) 千卡", "\(Int($0.value)) kcal of food") : L("水 \(Fmt.number($0.value, 1)) 升", "\(Fmt.number($0.value, 1)) L of water") }
                        if !stash.isEmpty { detailBlock(L("私藏", "Hidden stash"), stash.joined(separator: Loc.sep(Loc.ui)), color: Theme.secret) }
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: L("对其他人的信任", "Trust in the others"))
                            ForEach(session.state.characters.filter { $0.id != id && $0.status != .notJoined }) { o in
                                let t = c.trust[o.id] ?? 0
                                HStack {
                                    Text(session.engine.name(o.id)).font(.system(size: 12)).lineLimit(1).frame(width: Loc.ui == .en ? 110 : 76, alignment: .leading)
                                    Meter(value: (t + 100) / 200, color: t >= 0 ? Theme.good : Theme.danger, height: 3)
                                    Text("\(Int(t))").font(.system(size: 11)).monospacedDigit().frame(width: 34, alignment: .trailing).foregroundStyle(Theme.dim)
                                }
                            }
                        }
                        if !c.diary.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                SectionLabel(text: L("日记", "Diary"))
                                ForEach(c.diary, id: \.self) { d in Text(d).font(Theme.prose(13)).foregroundStyle(Theme.secret) }
                            }
                        }
                        let st = c.stats
                        detailBlock(L("记录", "Record"), L("偷吃 \(st.thefts) 次（被抓 \(st.caught)）· 吃私藏 \(Int(st.stashEaten)) 千卡 · 私聊 \(st.whispers) 次 · 提出动议 \(st.motions) 次 · 当领头人 \(st.roundsLed) 回合 · 照顾别人 \(st.cared) 次",
                                                           "stole food \(st.thefts)× (caught \(st.caught)) · ate \(Int(st.stashEaten)) kcal from a stash · whispered \(st.whispers)× · proposed \(st.motions) motion(s) · led \(st.roundsLed) round(s) · cared for others \(st.cared)×"))
                    }
                } else {
                    Text(L("打开“上帝视角”可以看到这个人的秘密、目标、日记和对别人的信任。", "Turn on God view to see this person's secret, goal, diary and trust in the others.")).font(.system(size: 12)).foregroundStyle(Theme.faint)
                }
            }
            .padding(24)
        }
        .background(Theme.bg)
    }

    /// "Maximum health 124 (Strength 3: +18, Survival 2: +6, Tough +10)".
    func healthCapText(_ def: CharacterDef) -> String {
        let cap = Int(Buffs.healthCap(def))
        guard !def.isAnimal else { return L("血量上限 100", "Maximum health 100") }
        let str = def.skill("strength"), surv = def.skill("survival")
        var parts: [String] = []
        let ps = Int(Buffs.healthPerStrength), pv = Int(Buffs.healthPerSurvival), pt = Int(Buffs.toughHealth)
        if str > 0 { parts.append(L("体能 \(str)：+\(ps * str)", "Strength \(str): +\(ps * str)")) }
        if surv > 0 { parts.append(L("野外 \(surv)：+\(pv * surv)", "Survival \(surv): +\(pv * surv)")) }
        if str >= Buffs.masteryLevel { parts.append(L("皮实 +\(pt)", "Tough +\(pt)")) }
        return L("血量上限 \(cap)", "Maximum health \(cap)") + (parts.isEmpty ? "" : L("（\(parts.joined(separator: "，"))）", " (\(parts.joined(separator: ", ")))"))
    }

    func detailBlock(_ title: String, _ text: String, color: Color = Theme.text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: title)
            Text(text).font(.system(size: 13)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
}

/// Small outlined tags under a character's vitals: buffs in sage, debuffs in brick. Hover for details.
struct BuffStrip: View {
    let buffs: [BuffInstance]
    var body: some View {
        WrapLayout(spacing: 4, lineSpacing: 3) {
            ForEach(buffs) { b in
                let color = b.def.good ? Theme.good : Theme.danger
                HStack(spacing: 3) {
                    Text(b.def.name(Loc.ui)).font(.system(size: 11))
                    if let r = b.rounds { Text("\(r)").font(.system(size: 10)).monospacedDigit().opacity(0.7) }
                }
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .foregroundStyle(color)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(color.opacity(0.45), lineWidth: 0.75))
                .help(b.def.desc(Loc.ui) + (b.rounds.map { L("（还剩 \($0) 回合）", " (\($0) round\($0 == 1 ? "" : "s") left)") } ?? ""))
            }
        }
    }
}

/// Lays its children out left to right, wrapping onto new lines.
struct WrapLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { y += line + lineSpacing; x = 0; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(width, widest), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { y += line + lineSpacing; x = bounds.minX; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

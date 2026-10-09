import Foundation

/// Renders the game log as readable text / Markdown (in the game's language).
public enum Transcript {

    public static func line(_ e: LogEntry, _ engine: GameEngine) -> String {
        let who = e.actor.map { engine.name($0) } ?? ""
        let en = engine.lang == .en
        func paren(_ s: String?) -> String { s.map { en ? " (\($0))" : "（\($0)）" } ?? "" }
        let colon = Loc.colon(engine.lang)
        switch e.kind {
        case .report: return "【\(e.text)】" + (e.detail.map { "\n    \($0)" } ?? "")
        case .situation: return "▶ \(e.text)"
        case .speech:
            if e.isSilent { return en ? "  \(who) (says nothing\(e.detail.map { ", \($0)" } ?? ""))" : "  \(who)（没说话\(e.detail.map { "，\($0)" } ?? "")）" }
            return "  \(who)\(colon)\(e.text)" + paren(e.detail)
        case .vote: return "  ⚖ \(e.text)" + paren(e.detail)
        case .result: return "  → \(e.text)" + paren(e.detail)
        case .task: return "  · \(e.text)\(colon)\(e.detail ?? "")"
        case .death: return "  ✝ \(e.text)" + paren(e.detail)
        case .whisper: return "  [\(engine.L("私聊", "whisper"))] \(who) → \(engine.name(e.target))\(colon)\(e.text)"
        case .thought: return "  [\(engine.L("内心", "thinks"))] \(who)\(colon)\(e.text)"
        case .diary: return "  [\(engine.L("日记", "diary"))] \(who)\(colon)\(e.text)"
        case .secret: return "  [\(engine.L("暗中", "secretly"))] \(e.text)"
        case .system: return "  ※ \(e.text)" + paren(e.detail)
        case .ending: return "\n■ \(engine.L("结局", "Ending"))\(colon)\(e.text)\n\(e.detail ?? "")"
        case .debug: return "  [debug] \(e.text)"
        }
    }

    public static func text(_ engine: GameEngine, godView: Bool = true) -> String {
        var out: [String] = []
        let L = engine.L
        out.append(L("《绝境 · \(engine.scenario.title)》\(engine.scenario.subtitle)", "Brink · \(engine.scenario.title) — \(engine.scenario.subtitle)"))
        out.append(engine.scenario.briefing.joined(separator: "\n"))
        out.append("")
        var lastRound = 0
        for e in engine.state.log {
            if !godView, case .god = e.visibility { continue }
            if e.round != lastRound {
                lastRound = e.round
                out.append("")
            }
            out.append(line(e, engine))
        }
        if let end = engine.state.ending {
            out.append("")
            out.append(L("—— 结算 ——", "—— Results ——"))
            for r in end.results {
                let goal = r.goal ?? L("无", "none")
                out.append(L("\(r.name)（\(r.controller)）：\(r.fate)；个人目标「\(goal)」\(r.goalAchieved ? "达成" : "未达成")；得分 \(r.score)",
                             "\(r.name) (\(r.controller)): \(r.fate); personal goal “\(goal)” \(r.goalAchieved ? "achieved" : "not achieved"); score \(r.score)"))
            }
            for r in (end.results + (end.others ?? [])) {
                if let e = r.epilogue { out.append("  \(r.name)\(Loc.colon(engine.lang))\(e)") }
            }
        }
        return out.joined(separator: "\n")
    }

    public static func markdown(_ engine: GameEngine, godView: Bool = true) -> String {
        var out: [String] = []
        let s = engine.scenario
        let L = engine.L
        let colon = Loc.colon(engine.lang)
        out.append(L("# 《绝境 · \(s.title)》\(s.subtitle)", "# Brink · \(s.title) — \(s.subtitle)"))
        out.append("")
        out.append("> \(s.tagline)")
        out.append("")
        if let ch = engine.state.setup.chapter {
            let label = ch.finale ? L("终章", "the finale") : L("第 \(ch.number) 关", "chapter \(ch.number)")
            out.append(L("无尽模式 · \(label)", "Endless mode · \(label)") + (ch.mutators.isEmpty ? "" : L("；变数：", "; twists: ") + ch.mutators.joined(separator: Loc.sep(engine.lang))))
            out.append("")
        }
        out.append(L("## 角色", "## Characters"))
        for c in s.characters {
            let secret = c.secret ?? L("无", "none"), goal = c.goal?.text ?? L("无", "none")
            out.append(L("- **\(c.name)**（\(engine.playedBy(c.id))）：\(c.age)岁，\(c.role)。秘密：\(secret)；目标：\(goal)",
                         "- **\(c.name)** (\(engine.playedBy(c.id))): \(c.age), \(c.role). Secret: \(secret); goal: \(goal)"))
        }
        out.append("")
        out.append(L("## 过程", "## What happened"))
        var lastRound = 0
        for e in engine.state.log {
            if !godView, case .god = e.visibility { continue }
            if e.round != lastRound {
                lastRound = e.round
                out.append("")
                out.append(L("### 第 \(e.round) 回合", "### Round \(e.round)"))
            }
            out.append(line(e, engine).replacingOccurrences(of: "\n", with: "  \n"))
        }
        if let end = engine.state.ending {
            out.append("")
            out.append(L("## 结局：\(end.title)", "## Ending: \(end.title)"))
            out.append(end.text)
            out.append("")
            out.append(L("| 角色 | 控制者 | 结果 | 个人目标 | 得分 |", "| Character | Played by | Fate | Personal goal | Score |"))
            out.append("|---|---|---|---|---|")
            for r in end.results {
                out.append("| \(r.name) | \(r.controller) | \(r.fate) | \(r.goal ?? "-")\(r.goalAchieved ? " ✅" : " ❌") | \(r.score) |")
            }
            let epilogues = (end.results + (end.others ?? [])).compactMap { r in r.epilogue.map { (r.name, $0) } }
            if !epilogues.isEmpty {
                out.append("")
                out.append(L("### 后来", "### Afterwards"))
                for (n, e) in epilogues { out.append("- **\(n)**\(colon)\(e)") }
            }
        }
        return out.joined(separator: "\n")
    }
}

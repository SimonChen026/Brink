import SwiftUI
import BrinkCore

struct WorldPanel: View {
    @Bindable var session: GameSession
    @Binding var showCalls: Bool

    var body: some View {
        let s = session.scenario
        let st = session.state
        let w = s.climate.weather[st.weather]
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Panel(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: L("天气", "Weather"))
                        HStack(spacing: 10) {
                            Image(systemName: w?.icon ?? "cloud").font(.system(size: 24)).foregroundStyle(Theme.accent(s))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w?.name ?? st.weather).font(.system(size: 15, weight: .semibold))
                                Text("\(Fmt.temp(st.dayLow)) ~ \(Fmt.temp(st.dayHigh))").font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.dim)
                            }
                        }
                        if let d = w?.desc { Text(d).font(.system(size: 11)).foregroundStyle(Theme.faint).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                Panel(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: s.shelter.name)
                        HStack {
                            Meter(value: st.shelterIntegrity / 100, color: st.shelterIntegrity > 50 ? Theme.good : Theme.warn)
                            Text("\(Int(st.shelterIntegrity))%").font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.dim)
                        }
                        if let f = s.shelter.fire {
                            let fl = Loc.inline(f.label ?? L("火", "fire"), Loc.ui)
                            Label(st.fireLit ? L("昨晚点着\(fl)", "The \(fl) burned last night") : L("昨晚没有\(fl)", "No \(fl) last night"), systemImage: st.fireLit ? "flame.fill" : "flame")
                                .font(.system(size: 11)).foregroundStyle(st.fireLit ? Theme.flare : Theme.faint)
                        }
                    }
                }
                Panel(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: L("物资", "Supplies"))
                        ForEach(s.resources, id: \.id) { r in
                            let v = st.resources[r.id] ?? 0
                            if !((r.hidden ?? false) && v <= 0) {
                                HStack {
                                    Text(r.name).font(.system(size: 12))
                                    Spacer()
                                    Text(Fmt.amount(v, r.id, s)).font(.system(size: 12, weight: .medium)).monospacedDigit()
                                        .foregroundStyle(v <= 0 && (r.id == "food" || r.id == "water") ? Theme.danger : Theme.text)
                                }
                            }
                        }
                        Divider().padding(.vertical, 2)
                        Text(session.engine.policyText(st.policy)).font(.system(size: 11)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    }
                }
                let vars = (s.vars ?? []).filter { ($0.show ?? false) || session.godView }
                if !vars.isEmpty {
                    Panel(padding: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            SectionLabel(text: L("局面", "Situation"))
                            ForEach(vars, id: \.id) { v in
                                let value = st.vars[v.id] ?? 0
                                let lo = v.min ?? 0, hi = v.max ?? 100
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(v.name + ((v.show ?? false) ? "" : L("（隐藏）", " (hidden)"))).font(.system(size: 12))
                                            .foregroundStyle((v.show ?? false) ? Theme.text : Theme.secret)
                                        Spacer()
                                        Text(Fmt.variable(value, v)).font(.system(size: 12, weight: .medium)).monospacedDigit()
                                    }
                                    Meter(value: (value - lo) / max(1e-9, hi - lo), color: (v.show ?? false) ? Theme.accent(s) : Theme.secret, height: 3)
                                }
                                .help(v.desc ?? "")
                            }
                        }
                    }
                }
                let projects = (s.projects ?? []).filter { st.projectsDone.contains($0.id) || (st.projects[$0.id] ?? 0) > 0 }
                if !projects.isEmpty {
                    Panel(padding: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            SectionLabel(text: L("工程", "Projects"))
                            ForEach(projects, id: \.id) { p in
                                let done = st.projectsDone.contains(p.id)
                                let frac = done ? 1 : min(1, (st.projects[p.id] ?? 0) / max(1, p.work))
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(p.name).font(.system(size: 12))
                                        Spacer()
                                        Text(done ? L("完成", "done") : "\(Int(frac * 100))%").font(.system(size: 11)).foregroundStyle(done ? Theme.good : Theme.dim)
                                    }
                                    Meter(value: frac, color: done ? Theme.good : Theme.flare, height: 3)
                                }
                                .help(p.desc)
                            }
                        }
                    }
                }
                if !session.usage.isEmpty {
                    Panel(padding: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            SectionLabel(text: L("模型调用", "Model calls"))
                            ForEach(session.usage.sorted { $0.key < $1.key }, id: \.key) { k, u in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(k).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                    let avg = u.calls > 0 ? String(format: "%.1f", u.seconds / Double(u.calls)) : "0"
                                    Text(L("\(u.calls) 次\(u.failures > 0 ? "，失败 \(u.failures)" : "") · \(u.inputTokens + u.outputTokens) tokens · 平均 \(avg)s", "\(u.calls) calls\(u.failures > 0 ? ", \(u.failures) failed" : "") · \(u.inputTokens + u.outputTokens) tokens · avg \(avg)s"))
                                        .font(.system(size: 10)).foregroundStyle(Theme.dim)
                                }
                            }
                            Button(L("查看调用记录", "Show call log")) { showCalls = true }.buttonStyle(.link).font(.system(size: 11))
                        }
                    }
                }
            }
        }
    }
}

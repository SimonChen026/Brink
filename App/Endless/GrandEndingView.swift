import SwiftUI
import BrinkCore

/// The grand ending of a run: the finale's ending, the road there, everyone's "afterwards".
struct GrandEndingView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClose = false

    var body: some View {
        if let run = model.run, let g = run.grand {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Text(L("大结局", "THE GRAND ENDING")).font(.system(size: 12, weight: .semibold)).tracking(model.uiLang == .en ? 2 : 0).foregroundStyle(Theme.tone(g.tone))
                        Spacer()
                        let found = (model.gallery.unlocked["_grand"] ?? []).count
                        Text(L("大结局 \(found)/\(GrandEndings.all.count)", "Grand endings \(found)/\(GrandEndings.all.count)")).font(.system(size: 11)).foregroundStyle(Theme.faint)
                    }
                    Text(g.title).font(Theme.title(64))
                    Text(g.text).font(Theme.prose(18)).lineSpacing(8).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if let add = g.addendum { Text(add).font(Theme.prose(15)).foregroundStyle(Theme.dim) }
                    if let ft = g.finaleTitle, let fx = g.finaleText {
                        Panel {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(text: L("终章 · \(ft)", "The finale · \(ft)"))
                                Text(fx).font(Theme.prose(14)).lineSpacing(5).foregroundStyle(Theme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: L("后来", "Afterwards"))
                        ForEach(g.legacies) { l in legacyRow(l) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: L("这一路（\(g.chapters) 关，推演通关 \(g.cleared)/8）", "The road (\(g.chapters) chapters, \(g.cleared)/8 drills cleared)"))
                        ForEach(Array(g.recap.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 12)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(spacing: 10) {
                        if run.phase == .finaleDone {
                            if run.canContinue {
                                Button(L("接着无尽下去", "Keep going — endlessly")) { model.continueEndless() }
                                    .buttonStyle(PrimaryButtonStyle())
                            }
                            Button(L("先回主页，以后再说", "Home — decide later")) { model.leaveRun() }.buttonStyle(GhostButtonStyle())
                            Button(L("合上这本书", "Close the book")) { confirmClose = true }.buttonStyle(GhostButtonStyle())
                                .alert(L("合上这本书？", "Close the book?"), isPresented: $confirmClose) {
                                    Button(L("合上", "Close it"), role: .destructive) { model.closeRun() }
                                    Button(L("再想想", "Not yet"), role: .cancel) {}
                                } message: {
                                    Text(L("这段征程就到此为止，以后不能再接着往下打。大结局会留在图鉴里。", "This run ends here for good — you can't carry on with it later. The grand ending stays in your collection."))
                                }
                        } else {
                            Button(L("返回主页", "Home")) { model.leaveRun() }.buttonStyle(PrimaryButtonStyle())
                        }
                        Spacer()
                        Text(run.options.spectator ? L("观战", "Watched") : (run.options.hardcore ? L("铁人模式", "Iron mode") : L("普通模式", "Normal mode")))
                            .font(.system(size: 11)).foregroundStyle(Theme.faint)
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: 860, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.vertical, 36)
                .frame(maxWidth: .infinity)
            }
        } else {
            HomeView()
        }
    }

    func legacyRow(_ l: Legacy) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(id: l.id, name: l.name, size: 34, dead: !l.alive)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(l.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.person(l.id))
                    Chip(text: l.title, color: Theme.flare)
                    Text("Lv \(l.level)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    Text(l.isHuman ? L("你", "you") : l.controller).font(.system(size: 11)).foregroundStyle(Theme.faint).lineLimit(1)
                }
                Text(l.fate + L("。打了 \(l.chapters) 关，活着走出来 \(l.survived) 次。", ". \(l.chapters) chapter\(l.chapters == 1 ? "" : "s"), walked out alive \(l.survived == 1 ? "once" : "\(l.survived) times")."))
                    .font(.system(size: 12)).foregroundStyle(l.alive ? Theme.good : Theme.danger)
                Text(l.epilogue).font(Theme.prose(14)).lineSpacing(4).foregroundStyle(Theme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if !l.certs.isEmpty {
                    Text(L("资格证：", "Certificates: ") + l.certs.joined(separator: L("、", ", "))).font(.system(size: 11)).foregroundStyle(Theme.faint)
                }
            }
        }
    }
}

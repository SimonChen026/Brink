import SwiftUI
import BrinkCore

/// "我": your certificates (earned in certification exams, carried into every run) and your exam record.
struct MeView: View {
    @Environment(AppModel.self) private var model
    @State private var certifying: String?
    @State private var showing: String?
    @State private var nameDraft = ""
    @FocusState private var editingName: Bool

    var body: some View {
        let p = model.profile
        let lib = model.library
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Button { model.screen = .home } label: { Label(L("返回", "Back"), systemImage: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(Theme.dim)
                header(p, lib)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("我的资格证", "My certificates")).font(Theme.title(26))
                    Text(L("资格认证很难：20 道题，大多是考官级的难题，对 19 道才算通过，每题限时 40 秒，没通过要等 12 小时才能再考同一张证。拿到的证会带进每一段新的无尽征程：对应技能 +1，有的还带一项本事。",
                           "Certification is hard: 20 questions, mostly examiner-level, 19 to pass, 40 seconds each, and a 12-hour wait before you can retake the same one. Certificates you earn come with you into every new endless run: +1 to the matching skill, and some bring know-how."))
                        .font(.system(size: 13)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 16)], spacing: 16) {
                    ForEach(lib) { c in
                        if p.has(c.id) {
                            CertificateCard(cert: c, holder: p.name ?? L("你", "You"), held: p.held(c.id), lang: model.uiLang)
                                .onTapGesture { showing = c.id }
                        } else {
                            LockedCertificate(cert: c, reason: p.lockReason(c, lang: model.uiLang)) { certifying = c.id }
                        }
                    }
                }
                if !p.attempts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: L("考试记录", "Exam record"))
                        ForEach(p.attempts.suffix(30).reversed()) { a in
                            HStack(spacing: 10) {
                                Image(systemName: a.passed ? "checkmark.seal.fill" : "xmark.circle").foregroundStyle(a.passed ? Theme.good : Theme.danger)
                                Text(lib.first { $0.id == a.certId }?.name(model.uiLang) ?? a.certId).font(.system(size: 13, weight: .semibold))
                                Text("\(a.score)/\(a.total)").font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(a.passed ? Theme.good : Theme.danger)
                                Text(a.source == "run" ? L("征程里", "in a run") : L("考场", "exam room")).font(.system(size: 11)).foregroundStyle(Theme.faint)
                                Spacer()
                                Text(a.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(Theme.faint)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 32)
        }
        .onAppear { nameDraft = p.name ?? "" }
        .sheet(isPresented: Binding(get: { certifying != nil }, set: { if !$0 { certifying = nil } })) {
            if let id = certifying { ExamView(mode: .certify(certId: id)).environment(model).frame(minWidth: 800, minHeight: 680) }
        }
        .sheet(isPresented: Binding(get: { showing != nil }, set: { if !$0 { showing = nil } })) {
            if let id = showing, let c = lib.first(where: { $0.id == id }) {
                VStack(spacing: 18) {
                    CertificateCard(cert: c, holder: model.profile.name ?? L("你", "You"), held: model.profile.held(id), lang: model.uiLang, large: true)
                    Text(c.text(model.uiLang).desc + "\n" + c.effectText(model.uiLang)).font(.system(size: 12)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    Button(L("关闭", "Close")) { showing = nil }.buttonStyle(GhostButtonStyle())
                }
                .padding(30)
                .frame(minWidth: 680)
                .background(Theme.bg)
            }
        }
    }

    func header(_ p: PlayerProfile, _ lib: [CertificateDef]) -> some View {
        let tried = p.attempts.count, passed = p.attempts.filter(\.passed).count
        let grand = (model.gallery.unlocked["_grand"] ?? []).count
        let endings = model.gallery.unlocked.filter { $0.key != "_grand" }.values.map(\.count).reduce(0, +)
        let total = model.baseScenarios.map(\.endings.count).reduce(0, +)
        return HStack(alignment: .center, spacing: 20) {
            Text(String((p.name ?? L("我", "Me")).prefix(1)))
                .font(Theme.title(34))
                .foregroundStyle(Theme.flare)
                .frame(width: 76, height: 76)
                .overlay(Circle().stroke(Theme.flare.opacity(0.7), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField(L("你的名字", "Your name"), text: $nameDraft)
                        .textFieldStyle(.plain)
                        .font(Theme.title(30))
                        .frame(maxWidth: 360)
                        .focused($editingName)
                        .onSubmit { model.renameProfile(nameDraft) }
                        // also saved when the field loses focus, not only on Return
                        .onChange(of: editingName) { _, on in if !on { model.renameProfile(nameDraft) } }
                        .help(L("点一下就能改名", "Click to change your name"))
                }
                HStack(spacing: 8) {
                    Chip(text: L("资格证 \(p.certs.count)/\(lib.count)", "Certificates \(p.certs.count)/\(lib.count)"), color: Theme.flare)
                    Chip(text: L("认证考试 \(tried) 次，通过 \(passed) 次", "\(tried) certification attempt(s), \(passed) passed"), color: Theme.dim)
                    Chip(text: L("结局 \(endings)/\(total)", "Endings \(endings)/\(total)"), color: Theme.dim)
                    Chip(text: L("大结局 \(grand)/\(GrandEndings.all.count)", "Grand endings \(grand)/\(GrandEndings.all.count)"), color: Theme.dim)
                }
            }
            Spacer()
        }
        .padding(20)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line.opacity(0.5), lineWidth: 1))
    }
}

/// A certificate as it looks on the wall.
struct CertificateCard: View {
    let cert: CertificateDef
    let holder: String
    let held: PlayerProfile.Held?
    let lang: Lang
    var large = false

    var body: some View {
        let color = Color(hex: cert.color) ?? Theme.flare
        let t = cert.text(lang)
        let scale: CGFloat = large ? 1.35 : 1
        ZStack {
            // a printed certificate: flat card, a double rule in the certificate's colour
            RoundedRectangle(cornerRadius: 3).fill(Theme.panelHi)
            RoundedRectangle(cornerRadius: 3).stroke(color.opacity(0.7), lineWidth: 1.5)
            RoundedRectangle(cornerRadius: 2).stroke(color.opacity(0.3), lineWidth: 0.75).padding(5)
            VStack(alignment: .leading, spacing: 8 * scale) {
                HStack {
                    Text(Loc.pick("绝境训练营 · 资格证书", "BRINK TRAINING CAMP · CERTIFICATE", lang)).font(.system(size: 10 * scale, weight: .semibold)).tracking(lang == .en ? 2 : 0.5).foregroundStyle(color.opacity(0.9))
                    Spacer()
                    Image(systemName: cert.icon).font(.system(size: 16 * scale)).foregroundStyle(color)
                }
                Text(t.full).font(lang == .en ? .system(size: 22 * scale, weight: .bold, design: .serif) : .custom(Theme.serif, size: 24 * scale).weight(.bold))
                    .foregroundStyle(Color(red: 0.95, green: 0.92, blue: 0.85))
                    .lineLimit(2).minimumScaleFactor(0.7)
                Text(Loc.pick("持证人：\(holder)", "Holder: \(holder)", lang)).font(.system(size: 12 * scale)).foregroundStyle(Color(red: 0.85, green: 0.82, blue: 0.75))
                Text(cert.effectText(lang)).font(.system(size: 10 * scale)).foregroundStyle(color.opacity(0.85)).lineLimit(2)
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let h = held {
                            Text(Loc.pick("证书编号 \(h.serial)", "No. \(h.serial)", lang)).font(.system(size: 9 * scale, design: .monospaced)).foregroundStyle(Theme.dim)
                            Text(Loc.pick("成绩 \(h.score)/\(h.total) · \(h.date.formatted(date: .long, time: .omitted))", "Score \(h.score)/\(h.total) · \(h.date.formatted(date: .long, time: .omitted))", lang))
                                .font(.system(size: 9 * scale)).foregroundStyle(Theme.dim)
                        }
                    }
                    Spacer()
                    // the seal
                    ZStack {
                        Circle().stroke(Color(red: 0.78, green: 0.20, blue: 0.18), lineWidth: 2)
                        Circle().stroke(Color(red: 0.78, green: 0.20, blue: 0.18).opacity(0.6), lineWidth: 1).padding(4)
                        VStack(spacing: 1) {
                            Text(Loc.pick("绝境", "BRINK", lang)).font(.system(size: 11 * scale, weight: .bold))
                            Text(Loc.pick("合格", "PASSED", lang)).font(.system(size: 8 * scale, weight: .bold))
                        }
                        .foregroundStyle(Color(red: 0.78, green: 0.20, blue: 0.18))
                    }
                    .frame(width: 54 * scale, height: 54 * scale)
                    .rotationEffect(.degrees(-14))
                    .opacity(0.9)
                }
            }
            .padding(16 * scale)
        }
        .frame(height: 190 * scale)
    }
}

/// A certificate not held yet: what it gives and whether you can sit it now.
struct LockedCertificate: View {
    let cert: CertificateDef
    let reason: String?
    let action: () -> Void

    var body: some View {
        let color = Color(hex: cert.color) ?? Theme.flare
        let t = cert.text(Loc.ui)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: cert.icon).font(.system(size: 18)).foregroundStyle(color.opacity(0.6))
                Text(t.full).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text.opacity(0.75))
                Spacer()
                Image(systemName: "lock.fill").foregroundStyle(Theme.faint)
            }
            Text(t.desc).font(.system(size: 12)).foregroundStyle(Theme.faint).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(cert.effectText(Loc.ui)).font(.system(size: 11)).foregroundStyle(color.opacity(0.6)).lineLimit(2)
            Spacer(minLength: 0)
            HStack {
                if let reason { Text(reason).font(.system(size: 11)).foregroundStyle(Theme.faint) }
                Spacer()
                Button { action() } label: { Label(L("参加资格认证", "Take the certification"), systemImage: "pencil.and.list.clipboard") }
                    .buttonStyle(PrimaryButtonStyle(color: color))
                    .disabled(reason != nil)
            }
        }
        .padding(16)
        .frame(height: 190)
        .background(Theme.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(Theme.line))
    }
}

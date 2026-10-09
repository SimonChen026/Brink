import SwiftUI
import BrinkCore

struct FeedView: View {
    @Bindable var session: GameSession

    var entries: [LogEntry] {
        let all = session.state.log
        if session.godView || session.spectator || !session.humanAlive && session.humanId == nil { return all }
        let viewer = session.humanId
        return all.filter { e in
            switch e.visibility {
            case .everyone: return true
            case .only(let ids): return session.godView || (viewer.map { ids.contains($0) } ?? false)
            case .god: return session.godView
            }
        }
    }

    var body: some View {
        let list = entries
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(list) { e in
                        FeedRow(entry: e, session: session)
                            .id(e.id)
                    }
                    if !session.thinking.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(session.thinking.sorted().map { session.engine.name($0) }.joined(separator: Loc.sep(Loc.ui)) + L(" 正在想……", " thinking…"))
                                .font(.system(size: 12)).foregroundStyle(Theme.dim)
                        }
                        .padding(.leading, 6)
                        .id(-1)
                    }
                    Color.clear.frame(height: 4).id(-2)
                }
                .padding(16)
            }
            .onChange(of: list.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(-2, anchor: .bottom) }
            }
            .onChange(of: session.thinking.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(-2, anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo(-2, anchor: .bottom) }
        }
    }
}

struct FeedRow: View {
    let entry: LogEntry
    let session: GameSession

    var name: String { entry.actor.map { session.engine.name($0) } ?? "" }
    var model: String? {
        guard let a = entry.actor, session.state.character(a)?.isNPC == false else { return nil }
        let c = session.engine.controller(a)
        if case .human = c { return L("你", "you") }
        return c.label
    }

    /// Parenthesized aside in the game's language.
    func paren(_ s: String?) -> String { s.map { session.engine.lang == .en ? " (\($0))" : "（\($0)）" } ?? "" }

    var body: some View {
        switch entry.kind {
        case .report:
            // the morning report: a dateline over a hairline, like the head of a dispatch
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.text).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(Theme.line).frame(height: 1)
                if let d = entry.detail {
                    Text(d).font(.system(size: 12)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 12)
        case .situation:
            // a dispatch: a rule on the left, the text in the serif
            Text(entry.text)
                .font(Theme.prose(17))
                .lineSpacing(5)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 14)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.flare.opacity(0.75)).frame(width: 2) }
                .padding(.vertical, 4)
        case .speech:
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.person(entry.actor ?? ""))
                    if let m = model { Text(m).font(.system(size: 11)).foregroundStyle(Theme.faint) }
                    if let d = entry.detail { Text(d).font(.system(size: 11)).foregroundStyle(Theme.faint) }
                }
                Text(entry.text)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .foregroundStyle(entry.isSilent ? Theme.faint : Theme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 2)
        case .vote:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text).font(.system(size: 13, weight: .semibold))
                if let d = entry.detail { Text(d).font(.system(size: 12)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true) }
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.warn.opacity(0.7)).frame(width: 2) }
        case .result where entry.visibility != .everyone:
            privateRow(title: L("只有部分人知道", "Only some know"), text: entry.text + paren(entry.detail))
        case .result:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text).font(Theme.prose(14)).foregroundStyle(Theme.text.opacity(0.92)).italic()
                    .fixedSize(horizontal: false, vertical: true)
                if let d = entry.detail { Text(d).font(.system(size: 12)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true) }
            }
            .padding(.leading, 2)
        case .task:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.text).font(.system(size: 12, weight: .medium))
                Text(entry.detail ?? "").font(.system(size: 12)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 2)
        case .death:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Rectangle().fill(Theme.danger).frame(width: 16, height: 1).alignmentGuide(.firstTextBaseline) { _ in 4 }
                Text(entry.text).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.danger)
                if let d = entry.detail { Text(d).font(.system(size: 12)).foregroundStyle(Theme.danger.opacity(0.8)) }
            }
            .padding(.vertical, 4)
        case .whisper:
            privateRow(title: L("\(name) → \(session.engine.name(entry.target)) 私聊", "\(name) → \(session.engine.name(entry.target)), whispered"), text: entry.text)
        case .thought:
            privateRow(title: L("\(name) 心里想", "\(name) thinks"), text: entry.text)
        case .diary:
            privateRow(title: L("\(name) 的日记", "\(name)'s diary"), text: entry.text)
        case .secret:
            privateRow(title: L("暗中", "In secret"), text: entry.text)
        case .system:
            Text(entry.text + paren(entry.detail)).font(.system(size: 12)).foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 2)
        case .ending:
            VStack(alignment: .leading, spacing: 6) {
                Text(L("结局：\(entry.text)", "Ending: \(entry.text)")).font(Theme.title(20))
                if let d = entry.detail { Text(d).font(Theme.prose(15)).lineSpacing(4) }
            }
            .padding(.top, 10)
        case .debug:
            EmptyView()
        }
    }

    /// Things only some people know: indented, a thin rule, cool grey italics.
    func privateRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secret.opacity(0.75))
            Text(text).font(.system(size: 13)).italic().foregroundStyle(Theme.secret)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.secret.opacity(0.4)).frame(width: 1) }
        .padding(.leading, 20)
    }
}

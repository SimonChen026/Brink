import SwiftUI
import BrinkCore

/// The three settings and what each one means.
struct DifficultyPicker: View {
    @Binding var level: Difficulty

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $level) {
                ForEach(Difficulty.allCases, id: \.self) { d in Text(d.label(Loc.ui)).tag(d) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Text(level.blurb(Loc.ui)).font(.system(size: 12)).foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// How hard the world is. On the cover it sets the difficulty new games start on; in the top bar it changes the
/// game being played, from now on (D-057).
struct DifficultyButton: View {
    enum Place { case cover, bar }
    @Environment(AppModel.self) private var model
    let place: Place
    var session: GameSession? = nil
    @State private var open = false

    private var level: Difficulty { session?.state.setup.level ?? model.config.newGameDifficulty }

    /// Picking one changes the running game (if any) and is remembered for the next one.
    private var choice: Binding<Difficulty> {
        Binding(
            get: { level },
            set: { new in
                session?.setDifficulty(new)
                model.config.difficulty = new
                model.saveConfig()
            })
    }

    private var button: some View {
        Button { open = true } label: {
            HStack(spacing: 5) {
                // the top bar is crowded: a dial and the short name there, the full words on the cover
                if place == .bar { Image(systemName: "dial.medium").font(.system(size: 11)) }
                Text(place == .bar ? L("难度 · \(level.label(Loc.ui))", level.label(Loc.ui))
                                   : L("难度 · \(level.label(Loc.ui))", "Difficulty · \(level.label(Loc.ui))"))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .fixedSize()
        }
        .help(session == nil ? L("新开的对局从哪一档难度开始", "The difficulty new games start on")
                             : L("调整这一局的难度，从现在起生效", "Change this game's difficulty, starting now"))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: L("难度", "Difficulty"))
                DifficultyPicker(level: choice)
                Text(session == nil
                     ? L("新开的对局会从这一档开始。", "New games start on this setting.")
                     : L("从现在起生效：开局时的物资和士气不会追加，天气从明天起变。", "Takes effect from now: the starting supplies and spirits stay as they were, and the weather changes from tomorrow."))
                    .font(.system(size: 11)).foregroundStyle(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 380)
        }
    }

    @ViewBuilder var body: some View {
        switch place {
        case .cover: button.buttonStyle(CoverToolStyle())
        case .bar: button.buttonStyle(BarButtonStyle())
        }
    }
}

import SwiftUI
import BrinkCore

/// Starting an endless run: who sits in the five seats, and how hard it is.
struct RunSetupView: View {
    @Environment(AppModel.self) private var model

    @State private var spectator = false
    @State private var myName = ""
    @State private var myFemale = false
    @State private var seats: [String] = ["rule", "rule", "rule", "rule", "rule"]
    @State private var hardcore = false
    @State private var debate = true
    @State private var autoAdvance = true
    @State private var seedText = ""

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button { model.screen = .home } label: { Label(L("返回", "Back"), systemImage: "chevron.left") }
                        .buttonStyle(.plain).foregroundStyle(Theme.dim)
                    Text(L("无尽模式", "Endless")).font(Theme.title(46))
                    Text(L("八场推演，一场真的。", "Eight drills. One that's real.")).font(Theme.prose(20)).foregroundStyle(Theme.flare)
                    VStack(alignment: .leading, spacing: 10) {
                        para(L("你和四个 AI 玩家进了一个灾害应对训练营。训练是八场“推演”——照着真实灾难做的全真模拟：雪山空难、救生筏、矿井透水、地震废墟、沙漠、荒岛、极夜、洪水。每一关你们各自扮演那场灾难里的一个人。",
                               "You and four AI players join a disaster-response training camp. The training is eight drills — full simulations of real disasters: a plane crash in the snow, a life raft, a flooded mine, an earthquake, the desert, a coral island, the polar night, a flood. In each one, every player takes on the role of one of the people who were there."))
                        para(L("每一关下来都有经验：活下来、完成个人目标、照顾伤员、带好队伍都算。升级给技能点；关与关之间还能考资格证——急救员、海上求生、寒区求生、地震搜救、无线电……真题真知识，考过了技能就涨。技能和资格证会跟着你进下一个角色。",
                               "Every chapter earns experience: surviving, reaching your personal goal, caring for the injured, leading well. Levels bring skill points, and between chapters you can sit certificate exams — first aid, sea survival, cold-weather survival, earthquake rescue, radio… real questions, real knowledge, and a pass raises your skills. Skills and certificates come with you into every new role."))
                        para(L("八场推演之后是终章：这一次不是推演，你们第一次以自己的身份出场。终章打完，就是大结局。之后还想接着打，就一直打下去——变数会越来越多。",
                               "After the eight drills comes the finale: this time it isn't a drill, and for the first time you play yourselves. When it's over, you get the grand ending. If you want more after that, keep going — endlessly, with more and more twists."))
                    }
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: L("规则速览", "The rules in brief"))
                            bullet(L("心力：每人 3 点。推演里死了扣 1，活着走出来回 1。心力低，下一关开局士气就低。", "Resolve: 3 points each. Dying in a drill costs 1, walking out alive gives 1 back. Low resolve means low morale at the start of the next chapter."))
                            bullet(L("经验：升到下一级要 100 × 当前等级。每级 1 个技能点（逢 5 级 2 个），考证通过再给 2 个。", "Experience: the next level takes 100 × your level. 1 skill point per level (2 every fifth level), and 2 more for every certificate."))
                            bullet(L("技能：医疗、野外、技术、方向、威望可以加点，每项最多 +3；体能属于身体，不能加。用得多的技能会自己长（熟能生巧）。", "Skills: Medical, Survival, Technical, Navigation and Standing can be trained, up to +3 each. Strength belongs to the body and can't. Skills you use a lot grow by themselves."))
                            bullet(L("资格证：每关之间每人可以考一张资格认证，20 题、大多是考官级难题，对 19 题才通过。对应技能 +1，有的还带一项本事（比如寒区求生：衣服保暖 +0.3）。你在“我”里已经拿到的证，开局就带着。", "Certificates: one certification per player between chapters — 20 questions, mostly examiner-level, 19 to pass. +1 to the matching skill, and some bring know-how (e.g. Cold & Mountain: +0.3 clo of warmth). Certificates already on your “Me” page come with you from the start."))
                            bullet(L("终章里死了就是真的死了。", "In the finale, death is real."))
                        }
                    }
                    Panel {
                        let found = model.gallery.unlocked["_grand"] ?? []
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: L("大结局 \(found.count)/\(GrandEndings.all.count)", "Grand endings \(found.count)/\(GrandEndings.all.count)"))
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 6) {
                                ForEach(GrandEndings.all, id: \.0) { e in
                                    let has = found.contains(e.0)
                                    HStack(spacing: 6) {
                                        Image(systemName: has ? (e.1 == "good" ? "sun.max.fill" : (e.1 == "bad" ? "moon.fill" : "cloud.sun.fill")) : "lock.fill")
                                            .font(.system(size: 11)).foregroundStyle(has ? Theme.tone(e.1) : Theme.faint)
                                        Text(has ? GrandEndings.title(e.0, Loc.ui) : L("尚未解锁", "Not found yet")).font(.system(size: 12, weight: has ? .semibold : .regular))
                                            .foregroundStyle(has ? Theme.text : Theme.faint)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(36)
            }
            .frame(maxWidth: .infinity)

            Divider().background(Theme.line)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(text: L("怎么玩", "How to play"))
                    Picker("", selection: $spectator) {
                        Text(L("亲自下场", "Play")).tag(false)
                        Text(L("观战：五个 AI 玩家", "Watch: five AI players")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if !spectator {
                        SectionLabel(text: L("你", "You"))
                        HStack(spacing: 8) {
                            TextField(L("你的名字（终章里用）", "Your name (used in the finale)"), text: $myName)
                                .textFieldStyle(.roundedBorder)
                            Picker("", selection: $myFemale) {
                                Text(L("男", "Male")).tag(false)
                                Text(L("女", "Female")).tag(true)
                            }
                            .labelsHidden()
                            .frame(width: 90)
                        }
                    }

                    SectionLabel(text: spectator ? L("五个 AI 玩家", "Five AI players") : L("另外四个玩家", "The other four players"))
                    ForEach(seatIndices, id: \.self) { i in
                        HStack(spacing: 8) {
                            Avatar(id: "p\(i + 1)", name: "\(i + 1)", size: 24)
                            Picker("", selection: Binding(get: { seats[i] }, set: { seats[i] = $0 })) {
                                ForEach(model.seatOptions, id: \.id) { o in Text(o.label).tag(o.id) }
                            }
                            .labelsHidden()
                        }
                    }
                    HStack(spacing: 8) {
                        Menu(L("全部用同一个", "Same for everyone")) {
                            ForEach(model.seatOptions, id: \.id) { o in
                                Button(o.label) { for i in seatIndices { seats[i] = o.id } }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        Button(L("随机混搭", "Shuffle")) { shuffle() }
                            .buttonStyle(GhostButtonStyle())
                            .disabled(model.config.availableModels.isEmpty)
                    }
                    Text(L("AI 玩家的名字和性格开局时随机生成。大模型玩家会记得前面每一关发生的事（谁救过它、谁把它赶出过队伍），也会真的去答资格考试。",
                           "AI players get a random name and temperament. AI-model players remember every earlier chapter (who saved them, who threw them out) and really do sit the exams."))
                        .font(.system(size: 11)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)

                    SectionLabel(text: L("选项", "Options"))
                    Toggle(L("铁人模式：心力耗尽就出局（你出局，征程就结束）", "Iron mode: out of resolve means out (if it's you, the run ends)"), isOn: $hardcore)
                        .font(.system(size: 13))
                    Toggle(L("大事先表态、辩论一轮再表决", "Debate once before big votes"), isOn: $debate)
                        .font(.system(size: 13))
                    if spectator {
                        Toggle(L("自动连播：一关打完自动考证、进下一关", "Autoplay: after each chapter, sit exams and move on automatically"), isOn: $autoAdvance)
                            .font(.system(size: 13))
                    }
                    HStack {
                        Text(L("随机种子", "Random seed")).font(.system(size: 13))
                        TextField(L("留空 = 随机", "empty = random"), text: $seedText).textFieldStyle(.roundedBorder).frame(width: 140)
                    }
                    let llm = seatIndices.filter { seats[$0] != "rule" }.count
                    if llm > 0 {
                        Text(L("预计：一段征程（8 场推演 + 终章）大约 \(llm * 9 * 60 / 10 * 10) 到 \(llm * 9 * 120 / 10 * 10) 次模型调用；考试和加点每关每个大模型玩家再多 2 次。",
                               "Estimate: one run (8 drills + the finale) takes roughly \(llm * 9 * 60 / 10 * 10)–\(llm * 9 * 120 / 10 * 10) model calls; exams and skill points add 2 per AI-model player per chapter."))
                            .font(.system(size: 11)).foregroundStyle(Theme.faint).fixedSize(horizontal: false, vertical: true)
                    }
                    Button { start() } label: {
                        Label(spectator ? L("开始观战", "Start watching") : L("进训练营", "Enter the camp"), systemImage: "flag.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 6)
                }
                .padding(28)
            }
            .frame(width: 430)
            .background(Theme.panel.opacity(0.5))
        }
        .onAppear(perform: setup)
    }

    var seatIndices: [Int] { spectator ? Array(0..<5) : Array(1..<5) }

    func para(_ t: String) -> some View {
        Text(t).font(Theme.prose(15)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
    }

    func bullet(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.flare).frame(width: 5, height: 5).padding(.top, 6)
            Text(t).font(.system(size: 13)).foregroundStyle(Theme.dim).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
    }

    func setup() {
        debate = model.config.debate
        if myName.isEmpty, let n = model.profile.name { myName = n }
        var perProvider: [String] = []
        for p in model.config.providers where p.isUsable {
            if let m = p.models.first { perProvider.append(ModelRef(providerId: p.id, model: m).id) }
        }
        for i in 0..<5 { seats[i] = perProvider.isEmpty ? "rule" : perProvider[i % perProvider.count] }
    }

    func shuffle() {
        let models = model.config.availableModels.map(\.id)
        guard !models.isEmpty else { return }
        var pool = models.shuffled()
        for i in seatIndices {
            if pool.isEmpty { pool = models.shuffled() }
            seats[i] = pool.removeFirst()
        }
    }

    func start() {
        var specs: [SeatSpec] = []
        let labels = Dictionary(model.seatOptions.map { ($0.id, $0.label) }, uniquingKeysWith: { a, _ in a })
        for i in 0..<5 {
            if !spectator && i == 0 {
                specs.append(SeatSpec(seat: "human", label: L("玩家", "Player"), name: myName, female: myFemale))
            } else {
                let seat = seats[i]
                let label = seat == "rule" ? L("基础人机", "Basic bot") : (ModelRef(seatId: seat).map { model.config.label(for: $0) } ?? labels[seat] ?? seat)
                specs.append(SeatSpec(seat: seat, label: label))
            }
        }
        model.config.debate = debate
        model.saveConfig()
        let seed = UInt64(seedText.trimmingCharacters(in: .whitespaces))
        model.newRun(seats: specs, options: RunOptions(spectator: spectator, hardcore: hardcore, debate: debate, autoAdvance: autoAdvance), seed: seed)
    }
}

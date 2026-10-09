import SwiftUI
import BrinkCore

struct DecisionPanel: View {
    @Bindable var session: GameSession

    var body: some View {
        Group {
            if let p = session.pendingHuman {
                switch p {
                case .situation(let final):
                    SituationInput(session: session, final: final)
                case .tasks:
                    TaskInput(session: session)
                case .night:
                    NightInput(session: session)
                }
            } else if session.spectator || !session.humanAlive {
                SpectatorControls(session: session)
            } else {
                Waiting(session: session)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.panel)
        // your turn: a bone rule along the top instead of a glowing frame
        .overlay(alignment: .top) { Rectangle().fill(session.pendingHuman == nil ? Theme.line : Theme.flare).frame(height: session.pendingHuman == nil ? 1 : 2) }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .animation(.easeOut(duration: 0.2), value: session.pendingHuman)
    }
}

// MARK: - Waiting / spectator

struct Waiting: View {
    let session: GameSession
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                if session.thinking.isEmpty {
                    Text(L("结算中……", "Working it out…")).foregroundStyle(Theme.dim)
                } else {
                    Text(L("等其他人", "Waiting for")).foregroundStyle(Theme.faint)
                    let ids = session.thinking.sorted()
                    ForEach(ids, id: \.self) { id in
                        let secs = session.thinkingSince[id].map { Int(ctx.date.timeIntervalSince($0)) } ?? 0
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(session.engine.name(id)).foregroundStyle(Theme.text)
                            Text("\(secs)s").monospacedDigit().foregroundStyle(secs >= 30 ? Theme.warn : Theme.faint)
                        }
                        .help(session.engine.controller(id).label)
                    }
                }
                Spacer(minLength: 8)
                let longest = session.thinkingSince.values.map { ctx.date.timeIntervalSince($0) }.max() ?? 0
                if longest >= 8 {
                    Button(L("不等了，交给基础人机", "Don't wait — let a basic bot decide")) { session.skipThinking() }
                        .buttonStyle(GhostButtonStyle())
                        .help(L("还没回答的模型这一步由基础人机代做，下一步照常问它们", "A basic bot takes this step for the models still thinking; they're asked again next step"))
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
    }
}

struct SpectatorControls: View {
    @Bindable var session: GameSession
    var body: some View {
        HStack(spacing: 14) {
            if !session.spectator && !session.humanAlive {
                Text(L("你的角色已经离开了这个故事。剩下的人还在继续。", "Your character has left the story. The others carry on."))
                    .font(.system(size: 13)).foregroundStyle(Theme.dim)
            }
            Button(session.paused ? L("继续", "Resume") : L("暂停", "Pause")) { session.paused.toggle() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut("p", modifiers: .command)
                .help("⌘P")
            Button(L("下一步", "Step")) { session.step() }
                .buttonStyle(GhostButtonStyle())
                .disabled(!session.paused)
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .help("⌘→")
            HStack(spacing: 6) {
                Text(L("快", "fast")).font(.system(size: 11)).foregroundStyle(Theme.faint)
                Slider(value: $session.delay, in: 0...5, step: 0.5).frame(width: 110)
                Text(L("慢", "slow")).font(.system(size: 11)).foregroundStyle(Theme.faint)
                Text("\(String(format: "%.1f", session.delay))s").font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.dim)
            }
            .help(L("每一步之间停多久", "Pause between steps"))
            Menu {
                ForEach(session.directorEvents, id: \.id) { ev in
                    Button(ev.label) { session.injectEvent(ev.id) }
                }
            } label: {
                Text(L("导演：安排下回合的事", "Director: stage next round's event"))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L("强制在下一回合触发一个事件（条件不满足时会顺延）", "Force an event next round (it waits if its conditions aren't met yet)"))
            if let inj = session.injected, let label = session.directorEvents.first(where: { $0.id == inj })?.label,
               session.state.scheduled.contains(where: { $0.eventId == inj }) {
                Chip(text: L("已安排：", "Staged: ") + "\(label.prefix(14))…", color: Theme.secret)
            }
            Spacer()
            if !session.thinking.isEmpty {
                Text(session.thinking.sorted().map { session.engine.name($0) }.joined(separator: Loc.sep(Loc.ui)) + L(" 正在想", " thinking"))
                    .font(.system(size: 12)).foregroundStyle(Theme.dim).lineLimit(1)
            }
        }
        .padding(14)
    }
}

// MARK: - Situation

struct SituationInput: View {
    let session: GameSession
    let final: Bool
    @State private var choice: String?
    @State private var speech = ""

    var body: some View {
        let ev = session.state.currentEvent
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: final ? L("最终表决", "Final vote") : (ev?.kindLabel ?? ""))
                if ev?.isMajor == true && !final { Text(L("先表态，大家听完彼此的意见后再最终表决", "State your position first; the final vote comes after everyone has heard each other")).font(.system(size: 11)).foregroundStyle(Theme.faint) }
                Spacer()
            }
            if let ev {
                Text(ev.text).font(Theme.prose(16)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                if final && !session.stances.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(ev.deciders.filter { $0 != session.humanId }, id: \.self) { id in
                            if let s = session.stances[id] {
                                let label = session.engine.optionLabel(ev, session.engine.normalizeChoice(ev, s.choice, decider: id))
                                let said = (s.speech ?? "").isEmpty ? "" : "\(Loc.colon(Loc.ui))\(s.speech!)"
                                Text(L("\(session.engine.name(id)) 倾向「\(label)」\(said)", "\(session.engine.name(id)) leans “\(label)”\(said)"))
                                    .font(.system(size: 12)).foregroundStyle(Theme.dim).lineLimit(2)
                            }
                        }
                    }
                }
                if ev.def.kind == "nominate" {
                    HStack(spacing: 8) {
                        ForEach(Array(ev.nominees.enumerated()), id: \.element) { i, id in
                            optionButton(id: id, letter: "\(i + 1)", title: session.engine.name(id) + (id == session.humanId ? L("（我）", " (me)") : ""), hint: nil, index: i)
                        }
                    }
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(ev.options.enumerated()), id: \.element.id) { i, o in
                            if o.available {
                                optionButton(id: o.id, letter: String(Array("ABCDEFGH")[min(i, 7)]), title: o.label, hint: o.hint, index: i)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField(L("想对大家说点什么？（可选）", "Anything to say to the others? (optional)"), text: $speech)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submit)
                    Button(final ? L("最终决定", "Decide") : L("表态", "State position"), action: submit)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(choice == nil)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(14)
        .onAppear {
            if final, let ev, let me = session.humanId, let s = session.stances[me] { choice = session.engine.normalizeChoice(ev, s.choice, decider: me) }
        }
    }

    func optionButton(id: String, letter: String, title: String, hint: String?, index: Int) -> some View {
        let selected = choice == id
        let key = KeyEquivalent(Character(String(min(index + 1, 9))))
        return Button {
            choice = id
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(letter).font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(selected ? Theme.flare : Theme.faint)
                    .frame(width: 12, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(selected ? Theme.text : Theme.text.opacity(0.9))
                    if let hint { Text(hint).font(.system(size: 12)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(selected ? Theme.panelHi : Color.clear)
            .overlay(alignment: .leading) { Rectangle().fill(selected ? Theme.flare : Color.clear).frame(width: 2) }
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(selected ? Theme.flare.opacity(0.5) : Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .help("⌘\(index + 1)")
    }

    func submit() {
        guard let c = choice else { return }
        session.submit(SituationDecision(choice: c, speech: speech.isEmpty ? nil : speech))
        speech = ""
        choice = nil
    }
}

// MARK: - Tasks

struct TaskInput: View {
    let session: GameSession
    @State private var task: String?
    @State private var target: String?
    @State private var speech = ""
    @State private var food: Double = 0
    @State private var water: Double = 0
    @State private var fire = false
    @State private var priority = "equal"

    var body: some View {
        let me = session.humanId ?? ""
        let opts = session.engine.taskOptions(for: me)
        let isLeader = session.state.leader == me
        let rd = session.scenario.rationDef
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("分工：今天你做什么？", "Work: what do you do today?")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                if !session.plannedTasks.isEmpty {
                    Text(L("已定：", "Decided: ") + session.plannedTasks.sorted { $0.key < $1.key }.map { "\(session.engine.name($0.key))→\(Prompting.taskName(session.engine, $0.value.task))" }.joined(separator: "  "))
                        .font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 196), spacing: 6)], spacing: 6) {
                ForEach(Array(opts.enumerated()), id: \.element.id) { i, o in
                    let on = task == o.id
                    Button {
                        task = o.id
                        target = o.needsTarget ? o.targets.first : nil
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(o.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                                Spacer(minLength: 4)
                                Text((o.outdoor ? L("户外", "outdoors") : L("室内", "indoors")) + " · " + o.exertion.label)
                                    .font(.system(size: 11)).foregroundStyle(o.exertion == .heavy ? Theme.warn : Theme.faint)
                            }
                            Text(o.available ? o.desc : (o.reason ?? L("做不了", "not possible"))).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(2)
                                .help(o.desc)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                        .background(on ? Theme.panelHi : Color.clear)
                        .overlay(alignment: .leading) { Rectangle().fill(on ? Theme.flare : Color.clear).frame(width: 2) }
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(on ? Theme.flare.opacity(0.5) : Theme.line, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .opacity(o.available ? 1 : 0.4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!o.available)
                    .modifier(NumberKey(index: i))
                }
            }
            if let t = task, let o = opts.first(where: { $0.id == t }) {
                // the whole description of the chosen job, not just the two lines on the card
                Text(o.desc).font(.system(size: 12)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                if o.outdoor {
                    let mates = session.plannedTasks.filter { $0.value.task == t && $0.key != me }.map { session.engine.name($0.key) }
                    Text(mates.isEmpty ? L("户外的活最好结伴：有人一起，出意外的机会小得多，出了事也有人马上帮忙。", "Better not to go out alone: with someone on the same job, accidents are much rarer and help is at hand.")
                                       : L("和 \(mates.joined(separator: "、")) 一起去，更安全。", "Going with \(mates.joined(separator: ", ")) — safer."))
                        .font(.system(size: 11)).foregroundStyle(mates.isEmpty ? Theme.warn : Theme.good)
                }
            }
            if let t = task, let o = opts.first(where: { $0.id == t }), o.needsTarget {
                Picker(L("对象", "Who"), selection: Binding(get: { target ?? "" }, set: { target = $0 })) {
                    ForEach(o.targets, id: \.self) { Text(session.engine.name($0)).tag($0) }
                }
                .frame(maxWidth: 260)
            }
            if isLeader {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("你是领头人：定今天的配给", "You lead: set today's rations")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.warn)
                    HStack(spacing: 14) {
                        Picker(L("食物", "Food"), selection: $food) {
                            ForEach(rd.food, id: \.self) { Text(L("\(Int($0)) 千卡", "\(Int($0)) kcal")).tag($0) }
                        }.frame(width: 170)
                        Picker(L("水", "Water"), selection: $water) {
                            ForEach(rd.water, id: \.self) { Text(L("\(Fmt.number($0, 1)) 升", "\(Fmt.number($0, 1)) L")).tag($0) }
                        }.frame(width: 130)
                        if let f = session.scenario.shelter.fire {
                            let fl = Loc.inline(f.label ?? L("火", "fire"), Loc.ui)
                            Toggle(L("晚上点\(fl)", "Light the \(fl) tonight"), isOn: $fire)
                        }
                        Picker(L("顺序", "Order"), selection: $priority) {
                            ForEach(Policy.priorities, id: \.0) { Text(Policy.priorityLabel($0.0)).tag($0.0) }
                        }.frame(width: 190)
                    }
                    .font(.system(size: 12))
                    let alive = session.state.characters.filter { $0.alive }
                    let k = alive.isEmpty ? 0 : alive.map(\.reportKcal).reduce(0, +) / Double(alive.count)
                    let w = alive.isEmpty ? 0 : alive.map(\.reportWater).reduce(0, +) / Double(alive.count)
                    if k > 0 {
                        Text(L("参考：上一回合平均每人消耗约 \(Int(k)) 千卡、\(Fmt.number(w, 1)) 升水（按一天算）。", "For reference: last round each person used about \(Int(k)) kcal and \(Fmt.number(w, 1)) L of water (per day)."))
                            .font(.system(size: 11)).foregroundStyle(Theme.dim)
                    }
                }
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.line, lineWidth: 1))
            }
            HStack(spacing: 8) {
                TextField(L("想对大家说点什么？（可选）", "Anything to say to the others? (optional)"), text: $speech).textFieldStyle(.roundedBorder)
                Button(L("就这么干", "Do it")) {
                    guard let t = task else { return }
                    let policy = isLeader ? Policy(food: food, water: water, fire: fire, priority: priority) : nil
                    session.submit(TaskDecision(task: t, target: target, speech: speech.isEmpty ? nil : speech, policy: policy))
                    task = nil
                    speech = ""
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(task == nil)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(14)
        .onAppear {
            let p = session.state.policy
            food = p.food
            water = p.water
            fire = p.fire
            priority = p.priority
        }
    }
}

// MARK: - Night

struct NightInput: View {
    let session: GameSession
    @State private var to1 = ""
    @State private var text1 = ""
    @State private var to2 = ""
    @State private var text2 = ""
    @State private var secret = "none"
    @State private var motion = "none"
    @State private var motionTarget = ""
    @State private var diary = ""
    @State private var huddle = ""
    @State private var giftTo = ""
    @State private var giftKind = "half"

    var body: some View {
        let me = session.humanId ?? ""
        let others = session.state.characters.filter { $0.alive && $0.id != me && !$0.isNPC }.map(\.id)
        let c = session.state.character(me)
        let hasStash = ((c?.stash["food"] ?? 0) + (c?.stash["water"] ?? 0)) > 0
        let canReveal = session.scenario.character(me)?.secret != nil && !(c?.secretRevealed ?? true)
        let guards = session.state.guards.filter { $0 != me }.map { session.engine.name($0) }
        // anyone still here can be slept next to or given something — children and animals too
        let around = session.state.characters.filter { $0.alive && $0.present && $0.id != me }.map(\.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("入夜：私下里的事", "Night: what you do in private")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secret)
                Text(L("别人看不到你在这里做的选择，除非被抓到", "Nobody sees these choices — unless you get caught")).font(.system(size: 11)).foregroundStyle(Theme.faint)
                Spacer()
            }
            whisperRow(to: $to1, text: $text1, others: others)
            whisperRow(to: $to2, text: $text2, others: others)
            HStack(spacing: 14) {
                let guardList = guards.isEmpty ? L("无人", "nobody") : guards.joined(separator: Loc.sep(Loc.ui))
                Picker(L("暗中", "Secretly"), selection: $secret) {
                    Text(L("什么也不做", "Do nothing")).tag("none")
                    Text(L("偷吃公共食物（守夜：\(guardList)）", "Steal from the common food (on watch: \(guardList))")).tag("steal")
                    if hasStash { Text(L("吃自己的私藏", "Eat from your own stash")).tag("stash") }
                    if canReveal { Text(L("向大家坦白秘密", "Confess your secret")).tag("reveal") }
                }
                .frame(maxWidth: 360)
                Picker(L("动议", "Motion"), selection: $motion) {
                    Text(L("不提", "None")).tag("none")
                    Text(L("重新推选领头人", "Choose a new leader")).tag("elect")
                    Text(L("惩罚某人", "Punish someone")).tag("punish")
                    Text(L("驱逐某人", "Exile someone")).tag("exile")
                    Text(L("搜身（查所有人的私藏）", "Search everyone for hidden food")).tag("search")
                }
                .frame(maxWidth: 240)
                if motion == "punish" || motion == "exile" {
                    Picker(L("对象", "Who"), selection: $motionTarget) {
                        ForEach(others, id: \.self) { Text(session.engine.name($0)).tag($0) }
                    }
                    .frame(maxWidth: 160)
                }
            }
            .font(.system(size: 12))
            HStack(spacing: 14) {
                Picker(L("挨着谁睡", "Sleep next to"), selection: $huddle) {
                    Text(L("自己睡", "Nobody")).tag("")
                    ForEach(around, id: \.self) { Text(session.engine.name($0)).tag($0) }
                }
                .frame(maxWidth: 220)
                .help(L("冷的夜里挤在一起能少丢不少体温；对方生病的话可能传给你。热的时候只会更热。", "On a cold night, sleeping side by side saves a lot of body heat; if they're ill you may catch it. In the heat it only makes things worse."))
                Picker(L("分给", "Give to"), selection: $giftTo) {
                    Text(L("不分", "No one")).tag("")
                    ForEach(around, id: \.self) { Text(session.engine.name($0)).tag($0) }
                }
                .frame(maxWidth: 200)
                if !giftTo.isEmpty {
                    Picker("", selection: $giftKind) {
                        Text(L("今天口粮的一半", "Half my share today")).tag("half")
                        Text(L("今天口粮的全部", "All my share today")).tag("all")
                        if hasStash { Text(L("私藏（悄悄给）", "From my stash (quietly)")).tag("stash") }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 190)
                }
            }
            .font(.system(size: 12))
            HStack(spacing: 8) {
                TextField(L("日记：记下你想记住的事（只有你自己看得到）", "Diary: what you want to remember (only you can see it)"), text: $diary).textFieldStyle(.roundedBorder)
                Button(L("入夜", "Go to sleep")) {
                    var ws: [Whisper] = []
                    if !to1.isEmpty && !text1.isEmpty { ws.append(Whisper(to: to1, text: text1)) }
                    if !to2.isEmpty && !text2.isEmpty { ws.append(Whisper(to: to2, text: text2)) }
                    var m: Motion?
                    if let t = MotionType(rawValue: motion) {
                        m = Motion(type: t, target: (motion == "punish" || motion == "exile") ? motionTarget : nil)
                    }
                    let gift: Gift? = giftTo.isEmpty ? nil : (giftKind == "stash" ? Gift(to: giftTo, from: "stash") : Gift(to: giftTo, from: "ration", portion: giftKind == "all" ? 1 : 0.5))
                    session.submit(NightDecision(whispers: ws, secret: secret, motion: m, diary: diary.isEmpty ? nil : diary,
                                                 huddle: huddle.isEmpty ? nil : huddle, gift: gift))
                    text1 = ""; text2 = ""; diary = ""; secret = "none"; motion = "none"; giftTo = ""; giftKind = "half"
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.secret))
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(14)
        .onAppear {
            if motionTarget.isEmpty { motionTarget = others.first ?? "" }
        }
    }

    func whisperRow(to: Binding<String>, text: Binding<String>, others: [String]) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: to) {
                Text(L("私聊给…", "Whisper to…")).tag("")
                ForEach(others, id: \.self) { Text(session.engine.name($0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 130)
            TextField(L("悄悄说一句（拉拢、警告、交易都行）", "Say something quietly (win them over, warn, make a deal…)"), text: text).textFieldStyle(.roundedBorder)
                .disabled(to.wrappedValue.isEmpty)
        }
    }
}

/// ⌘1…⌘9 for the first nine cards of a grid.
struct NumberKey: ViewModifier {
    let index: Int
    func body(content: Content) -> some View {
        if index < 9 {
            content.keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command).help("⌘\(index + 1)")
        } else {
            content
        }
    }
}

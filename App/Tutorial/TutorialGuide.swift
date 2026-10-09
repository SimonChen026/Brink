import SwiftUI
import BrinkCore

/// The panel a tutorial tip is about: it gets a pulsing outline while the tip is up.
enum GuideSpot: Equatable {
    case none, party, scene, feed, decision, world, topBar

    /// A small pointer shown on the card ("← on the left").
    var pointer: String? {
        switch self {
        case .party: return L("← 看左边", "← on the left")
        case .world: return L("看右边 →", "on the right →")
        case .decision: return L("↓ 看下面", "↓ below")
        case .feed: return L("↓ 看日志", "↓ the log")
        case .topBar: return L("↑ 看顶栏", "↑ the top bar")
        case .scene: return L("↑ 3D 现场", "↑ the 3D scene")
        case .none: return nil
        }
    }
}

struct GuideTip: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    var spot: GuideSpot = .none
}

/// The beginner tutorial: tips that follow the game, one at a time, each shown until dismissed.
/// The tutorial itself is an ordinary (hidden) scenario, `tutorial.json`; this only explains it.
@MainActor
enum TutorialGuide {
    /// The character the player plays.
    static let playerId = "xiaoman"

    /// The tip for this moment: the first one that fits and hasn't been dismissed yet.
    static func current(_ s: GameSession, seen: Set<String>) -> GuideTip? {
        candidates(s).first { !seen.contains($0.id) }
    }

    /// Tips that fit the current moment, in the order they should be read.
    static func candidates(_ s: GameSession) -> [GuideTip] {
        let st = s.state
        if s.finished || st.phase == .ended { return [] }
        let me = s.humanId ?? playerId
        let ev = st.currentEvent
        var out = [welcome, you]
        // a new day: read the morning report first, then the statuses that showed up overnight
        if st.round >= 2 && st.phase == .situation {
            out.append(morning)
            if !s.engine.visibleBuffs(me, viewer: me).isEmpty { out.append(statuses) }
        }
        switch s.pendingHuman {
        case .situation(let final)?:
            if ev?.def.id == "_elect" {
                out.append(elect)
            } else if let m = ev?.motion, m.type != .elect {
                out.append(motion)
            } else if ev?.def.id == "r4_rescue" {
                out.append(last)
            } else if final {
                out.append(finalVote)
            } else if ev?.isMajor == true {
                out.append(event)
            } else {
                out.append(smallVote)
            }
        case .tasks?:
            out.append(tasks)
            if s.engine.taskOptions(for: me).contains(where: { $0.id == "care" && $0.available }) { out.append(care) }
            if st.leader == me {
                out.append(rations)
            } else if let l = st.leader {
                out.append(leaderOther(s.engine.name(l)))
            }
            if st.round >= 2 { out.append(godView) }
        case .night?:
            out.append(night)
        case nil:
            break
        }
        return out
    }

    // MARK: Tips

    static var welcome: GuideTip {
        GuideTip(id: "welcome", title: L("欢迎来到《绝境》", "Welcome to Brink"),
                 body: L("你是林小满，一个实习护士。大巴被塌方堵在了山上，你和另外五个人要在这间道班房里熬到天亮。\n\n另外四个大人由「基础人机」扮演：它是游戏自带的离线小程序，按每个角色的性格做决定，不用联网，也不用配 key。正式开局时，可以换成 Kimi、DeepSeek 这些大模型来演。\n\n这一局大约 10 分钟，提示会一步一步带你玩。",
                         "You're Mandy Lin, a trainee nurse. A landslide has trapped your bus on the mountain, and you and five others have to sit it out in this roadside hut until morning.\n\nThe other four adults are played by basic bots, run by a small offline program built into the game that decides according to each character's personality. No internet, no API key. In a real game you can have AI models like Kimi or DeepSeek play them instead.\n\nThis game takes about 10 minutes. These tips will walk you through it."))
    }

    static var you: GuideTip {
        GuideTip(id: "you", title: L("左边：这里的每一个人", "On the left: everyone here"),
                 body: L("标着「你」的是你。每个人下面是健康、体温、缺水、饱腹、疲劳和士气，谁快撑不住了，一眼就能看出来。\n\n点一个人的名字，能看这个人的技能、伤病和性格。点你自己，能看到你的秘密和个人目标：你包里有一盒没跟别人说的月饼；你的目标是照顾好受伤的小宇。",
                         "The one marked “you” is you. Under each name are health, core temperature, thirst, how well fed, tiredness and mood — you can see at a glance who is struggling.\n\nClick a name to see that person's skills, injuries and personality. Click yourself to see your secret and personal goal: there's a box of mooncakes in your bag you haven't mentioned, and your goal is to look after Danny, the injured boy."),
                 spot: .party)
    }

    static var event: GuideTip {
        GuideTip(id: "event", title: L("大家一起拿主意", "Deciding together"),
                 body: L("每一回合开始，都会弹出一件要大家决定的事。这是件大事，所以分两步：先表态，听完别人怎么说，再最终表决，按多数票算。\n\n在下面选一个选项（选项下的小字是代价和好处），想说服别人就写一句话，然后点「表态」。快捷键：⌘1、⌘2、⌘3 选选项，⌘↩ 提交。",
                         "Each round starts with something the group has to decide. This one is a big decision, so it takes two steps: everyone states a position, hears the others out, then votes for real — the majority wins.\n\nPick an option below (the small print under each is its cost and benefit), add a line to win the others over if you like, then click “State position”. Shortcuts: ⌘1/⌘2/⌘3 pick an option, ⌘↩ submits."),
                 spot: .decision)
    }

    static var finalVote: GuideTip {
        GuideTip(id: "final", title: L("最终表决", "The final vote"),
                 body: L("上面列出了每个人刚才的倾向和说的话。你可以坚持，也可以改主意。这一次投完，按多数票定下来。",
                         "Above are everyone's leanings and what they said. Stick to your choice or change your mind — this time the votes count, and the majority decides."),
                 spot: .decision)
    }

    static var elect: GuideTip {
        GuideTip(id: "elect", title: L("推选领头人", "Choosing a leader"),
                 body: L("第一件事之后，大家要推选一个领头人。领头人每天定配给：每人吃多少、喝多少，晚上点不点炉子，先照顾谁。\n\n可以选自己，也可以选你信得过的人。以后觉得不合适，夜里可以提议重新推选。",
                         "After the first decision, the group chooses a leader. The leader sets the rations every day: how much everyone eats and drinks, whether the stove is lit at night, and who gets looked after first.\n\nYou can vote for yourself or for someone you trust. If it isn't working out, you can propose a new election at night."),
                 spot: .decision)
    }

    static var tasks: GuideTip {
        GuideTip(id: "tasks", title: L("分工：这一回合你做什么", "Work: what do you do this round?"),
                 body: L("每个人每回合选一件事。卡片右上角标着在屋里还是户外、轻活还是重活。下雨天在户外干活会淋湿，湿衣服让人冷得快；重活更累，也更容易出意外。\n\n柴火烧炉子，炉子让屋里暖和；吃的喝的按领头人定的配给分；求救信号让外面的人知道这里有人。",
                         "Everyone picks one job per round. The top right of each card says indoors or outdoors, light or heavy work. Outdoor work in the rain gets you wet, and wet clothes make you cold fast; heavy work is more tiring and more likely to end in an accident.\n\nFirewood feeds the stove, and the stove keeps the hut warm. Food and water are shared out by the leader's rations. A distress signal lets the outside world know someone is here."),
                 spot: .decision)
    }

    static var care: GuideTip {
        GuideTip(id: "care", title: L("有人受伤了", "Someone is hurt"),
                 body: L("小宇的左小臂被车窗玻璃划开了一道口子。开放的伤口不处理会感染。\n\n选「照顾伤员」，对象选小宇。这会用掉 1 份急救用品；你的医疗技能是 2，比别人处理得好。",
                         "Danny's left forearm was cut by a broken bus window. An open wound that isn't treated gets infected.\n\nPick “Care for the injured” and choose Danny. It uses 1 unit of first-aid supplies; your medical skill is 2, so you'll do a better job than the others."),
                 spot: .decision)
    }

    static var rations: GuideTip {
        GuideTip(id: "rations", title: L("你是领头人：定配给", "You lead: set the rations"),
                 body: L("分工下面多了一块「配给」：每人每天吃多少千卡、喝多少升水，晚上点不点炉子（要烧 1 份柴），按什么顺序分。\n\n给得太少，大家没力气、士气低；给得太多，物资撑不到明天。下面有上一回合的消耗可以参考。",
                         "Below the jobs there's now a rations panel: how many kcal of food and litres of water each person gets per day, whether to light the stove tonight (it burns 1 unit of wood), and in what order things are shared.\n\nToo little and everyone weakens and loses heart; too much and the supplies won't last till tomorrow. Last round's consumption is shown underneath for reference."),
                 spot: .decision)
    }

    static func leaderOther(_ name: String) -> GuideTip {
        GuideTip(id: "leader", title: L("配给由领头人定", "The leader sets the rations"),
                 body: L("现在的领头人是\(name)。每人吃多少、喝多少、晚上点不点炉子，都由领头人来定。\n\n觉得分得不公平？夜里可以提「重新推选领头人」的动议，第二天早上大家表决。",
                         "\(name) leads now, and decides how much everyone eats and drinks and whether the stove is lit tonight.\n\nThink it's unfair? At night you can propose a new leader, and everyone votes on it the next morning."),
                 spot: .topBar)
    }

    static var night: GuideTip {
        GuideTip(id: "night", title: L("入夜：私下里的事", "Night: what you do in private"),
                 body: L("白天做的事大家都看得见，夜里做的事只有你自己知道，除非被抓到：\n• 私聊：悄悄拉拢谁、提醒谁，或者做个交易。\n• 暗中：偷吃公共的食物（守夜的人可能抓到你），或者吃自己的私藏。你的月饼就是私藏。\n• 坦白秘密：说出来可能丢面子，也可能换来信任。\n• 动议：提议重新推选领头人、惩罚、赶走或搜查，第二天早上大家表决。\n• 挨着谁睡：雨夜里两个人挤在一起，能少丢不少体温。\n• 分给谁：把自己的一份口粮分给别人，比如那个孩子；私藏也可以悄悄给人。\n• 日记：只有你自己看得到。\n什么都不想做，就直接点「入夜」。",
                         "Everyone sees what you do by day. What you do at night only you know — unless you get caught:\n• Whisper: quietly win someone over, warn them, or strike a deal.\n• Secretly: steal from the common food (whoever keeps watch may catch you), or eat from your own stash — your mooncakes are a stash.\n• Confess your secret: you may lose face, or gain trust.\n• Motion: propose a new leader, a punishment, throwing someone out or a search; everyone votes the next morning.\n• Sleep next to someone: on a wet night, two people side by side lose much less body heat.\n• Give to someone: hand part of your share to another person — the child, say; a stash can be given quietly too.\n• Diary: only you can read it.\nIf you don't want to do anything, just click “Go to sleep”."),
                 spot: .decision)
    }

    static var morning: GuideTip {
        GuideTip(id: "morning", title: L("新的一天：看看夜里发生了什么", "A new day: what happened overnight"),
                 body: L("引擎把这一夜一小时一小时地算完了：吃了多少、喝了多少、谁冷、谁的伤怎么样了，都写在中间的日志里。\n\n右边是物资、天气和求救信号，左边是每个人的身体状况。物资少了、有人体温往下掉了，就该想想下一步怎么办。",
                         "The game has worked through the night hour by hour: what was eaten and drunk, who got cold, how the injuries are doing — it's all in the log in the middle.\n\nSupplies, weather and the distress signal are on the right; everyone's condition is on the left. If supplies are dropping or someone's temperature is falling, it's time to think about your next move."),
                 spot: .feed)
    }

    static var statuses: GuideTip {
        GuideTip(id: "buffs", title: L("名字下面的小标签：状态", "The tags under each name: statuses"),
                 body: L("绿色的是增益，红色的是减益。比如昨晚守着炉子过夜，会有「烤了一夜火」；好好休息过，第二天「养足精神」，干活更有劲；守了一夜的人会「熬了一夜」。带数字的过几回合就消失。\n\n血条也不是人人一样：体能和野外技能越高，血量上限越高。点一个人能看到每个状态的具体效果。",
                         "Green ones are buffs, red ones debuffs. A night by the stove gives “Warm night”; a proper rest leaves someone “Well rested” and working harder the next day; whoever kept watch is “Up all night”. The ones with a number wear off after that many rounds.\n\nNot everyone's health bar is the same either: the higher someone's Strength and Survival, the higher their maximum health. Click a person to see exactly what each status does."),
                 spot: .party)
    }

    static var godView: GuideTip {
        GuideTip(id: "god", title: L("上帝视角和 3D 现场", "God view and the 3D scene"),
                 body: L("顶栏的「上帝视角」能看到所有人的内心独白、私聊和日记。会剧透，第一次玩可以先不开。\n\n上面的 3D 现场跟着天气、钟点和你们做的事变化：拖动转视角，滚轮缩放，右上角的按钮可以放大或隐藏。",
                         "God view in the top bar shows everyone's inner thoughts, whispers and diaries. It's a spoiler — you may want to leave it off the first time.\n\nThe 3D scene above changes with the weather, the time of day and what you all do: drag to turn the view, scroll to zoom, and use the buttons in its corner to enlarge or hide it."),
                 spot: .topBar)
    }

    static var smallVote: GuideTip {
        GuideTip(id: "small", title: L("小事直接投票", "Small matters: one vote"),
                 body: L("不是每件事都要先表态：小事大家直接投一次票。\n\n这件事说的是偷吃。分工时选「守夜看物资」的人，夜里有机会抓到偷吃的人；被抓到的人，第二天早上由大家处置。",
                         "Not everything needs positions first — for smaller matters everyone just votes once.\n\nThis one is about stolen food. Whoever picks “Guard the supplies” as their job has a chance to catch a thief in the night, and the group deals with whoever is caught the next morning."),
                 spot: .decision)
    }

    static var motion: GuideTip {
        GuideTip(id: "motion", title: L("有人提了动议", "A motion"),
                 body: L("昨天夜里有人提了一个动议，现在大家表决。动议能惩罚、赶走或者搜查别人。被赶出去的人，很难一个人活下来，投票前想清楚。",
                         "Someone made a motion last night, and now everyone votes on it. Motions can punish, throw out or search people — and whoever is thrown out rarely survives alone, so think before you vote."),
                 spot: .decision)
    }

    static var last: GuideTip {
        GuideTip(id: "last", title: L("最后一件事", "One last thing"),
                 body: L("抢修队来了。选完这一项，这一局就结束：你会看到结局、每个人后来的故事，以及完整的对局记录。",
                         "The road crew is here. Once you choose, the game ends: you'll see the ending, what became of everyone, and the full game log."),
                 spot: .decision)
    }
}

// MARK: - App model

extension AppModel {
    /// Start (or restart) the tutorial: the player is Lin Xiaoman (Mandy Lin in English), the others are the offline rule AI.
    func startTutorial() {
        guard let sc = scenario(Scenario.tutorialId) else {
            showToast(L("找不到教程场景", "The tutorial scenario is missing"))
            return
        }
        stopTournament()
        if run != nil { leaveRun() }
        session?.stop()
        tutorialSeen = []
        tutorialMuted = false
        saveTutorialState()
        var controllers: [String: ControllerKind] = [:]
        for c in sc.characters { controllers[c.id] = c.id == TutorialGuide.playerId ? .human : .rule }
        let setup = GameSetup(scenarioId: sc.id, seed: UInt64.random(in: 1...900_000), controllers: controllers, debate: true, language: uiLang)
        let s = GameSession(scenario: sc, setup: setup, config: config)
        // the tutorial isn't autosaved, so it never replaces the game behind "Continue"
        s.autosaveOverride = { _ in }
        session = s
        screen = .game
        s.start()
    }

    /// The tip to show in this game, if it's the tutorial.
    func tutorialTip(_ s: GameSession) -> GuideTip? {
        guard s.scenario.isTutorial, !s.spectator, !tutorialMuted else { return nil }
        return TutorialGuide.current(s, seen: tutorialSeen)
    }

    func dismissTip(_ id: String) {
        tutorialSeen.insert(id)
        saveTutorialState()
    }

    func muteTips() {
        tutorialMuted = true
        saveTutorialState()
    }

    func finishTutorial() {
        guard !tutorialDone else { return }
        tutorialDone = true
        saveTutorialState()
    }

    func saveTutorialState() {
        let d = UserDefaults.standard
        d.set(tutorialSeen.sorted().joined(separator: ","), forKey: "tutorial.seen")
        d.set(tutorialMuted, forKey: "tutorial.muted")
        d.set(tutorialDone, forKey: "tutorialDone")
    }

    static func loadTutorialSeen() -> Set<String> {
        Set((UserDefaults.standard.string(forKey: "tutorial.seen") ?? "").split(separator: ",").map(String.init))
    }
}

// MARK: - Views

/// The floating tip card.
struct TutorialCard: View {
    let tip: GuideTip
    var onNext: () -> Void
    var onMute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionLabel(text: L("新手教程", "Tutorial"))
                if let p = tip.spot.pointer {
                    Text(p).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.warn)
                }
                Spacer()
                Button(L("不再提示", "Hide tips"), action: onMute)
                    .buttonStyle(.link).font(.system(size: 11))
                    .help(L("这一局不再显示教程提示", "No more tutorial tips this game"))
            }
            Text(tip.title).font(Theme.title(20))
            Text(tip.body)
                .font(.system(size: 13)).lineSpacing(3)
                .foregroundStyle(Theme.text.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("知道了", "Got it"), action: onNext)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(16)
        .frame(width: 470)
        .background(Theme.panelHi, in: RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .top) { Rectangle().fill(Theme.flare).frame(height: 2) }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// A steady outline around the panel a tip is about.
struct GuideGlow: ViewModifier {
    let on: Bool
    var radius: CGFloat = 4

    func body(content: Content) -> some View {
        content.overlay {
            if on {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Theme.flare.opacity(0.85), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func guideGlow(_ on: Bool, radius: CGFloat = 4) -> some View { modifier(GuideGlow(on: on, radius: radius)) }
}

/// At the end of the tutorial: where to go next.
struct TutorialNextSteps: View {
    @Environment(AppModel.self) private var model
    let session: GameSession
    @Binding var lookBack: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("教程完成", "Tutorial complete")).font(Theme.title(24))
            Text(L("你已经会玩了。真正的绝境比这一夜难得多，接下来可以：", "You know how to play now. The real disasters are much harder than this night. Where next:"))
                .font(.system(size: 13)).foregroundStyle(Theme.dim)
            step("flame", L("\(HomeView.spelled(model.scenarios.filter { !$0.isTutorial && !($0.hidden ?? false) }.count))场灾难", "\(HomeView.spelled(model.scenarios.filter { !$0.isTutorial && !($0.hidden ?? false) }.count)) disasters"),
                 L("每一场都根据真实发生过的灾难改编：雪山空难、海上漂流、矿井透水、地震废墟……", "Each one is based on a disaster that really happened: a plane crash in the snow, a life raft, a flooded mine, an earthquake…"),
                 L("选一个场景", "Pick one")) {
                model.homeScrollTarget = "scenarios"
                model.leaveGame()
            }
            step("infinity", L("无尽模式", "Endless mode"),
                 L("5 个玩家一关接一关地闯：攒经验、加技能点、考资格证，最后迎来大结局。", "Five players take on one disaster after another: earn experience, raise skills, pass certificates, and reach a grand ending."),
                 L("开始无尽模式", "Start endless mode")) {
                model.leaveGame()
                model.screen = .runSetup
            }
            step("pencil.and.list.clipboard", L("考场和「我」", "Exams and “Me”"),
                 L("资格认证很难：20 道题对 19 道才算过。考到的证挂在「我」的证书墙上，也会带进无尽模式。", "Certification is hard: 19 out of 20 to pass. Certificates you earn hang on your wall in “Me” and come with you into endless mode."),
                 L("去考场", "Go to the exams")) {
                model.leaveGame()
                model.screen = .examHall
            }
            step("cpu", L("让大模型来演", "Let AI models play"),
                 L("在设置里填入 Kimi、GLM、DeepSeek 等的 API key，其他人就由大模型扮演：它们会说服、结盟、撒谎，比基础人机精彩得多。", "Add API keys for Kimi, GLM, DeepSeek and others in Settings, and AI models will play the others: they persuade, form alliances and lie — far more lively than the basic bots."),
                 L("打开设置", "Open Settings")) {
                model.leaveGame()
                model.showSettings = true
            }
            HStack(spacing: 10) {
                Button(L("再玩一次教程", "Play the tutorial again")) { model.startTutorial() }
                    .buttonStyle(GhostButtonStyle())
                Button(L("回看过程", "Look back")) { lookBack = true }.buttonStyle(GhostButtonStyle())
                if let url = session.savedTranscript {
                    Button(L("打开完整记录", "Open full log")) { NSWorkspace.shared.open(url) }.buttonStyle(GhostButtonStyle())
                }
                Spacer()
                Button(L("返回主页", "Home")) { model.leaveGame() }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(Theme.panelHi, in: RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .top) { Rectangle().fill(Theme.flare).frame(height: 2) }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onAppear { model.finishTutorial() }
    }

    func step(_ icon: String, _ title: String, _ text: String, _ button: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(button, action: action).buttonStyle(GhostButtonStyle())
        }
    }
}

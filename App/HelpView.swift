import SwiftUI
import BrinkCore

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L("怎么玩", "How to play")).font(Theme.title(28))
                    Spacer()
                    Button(L("知道了", "Got it")) { dismiss() }.buttonStyle(PrimaryButtonStyle())
                }
                block(L("新手教程", "Tutorial"), L("第一次玩，可以先打一局新手教程：一个雨夜、一间道班房，十分钟左右，屏幕上会一步一步提示。主页的大按钮（打完以后在右上角“…”菜单里）可以随时再玩一次。",
                                             "New to the game? Play the tutorial first: one rainy night in a roadside hut, about ten minutes, with tips on screen at every step. Start it from the big button on the home screen (once you've finished it, from the “…” menu at the top right)."))
                block(L("一回合的三段", "The three parts of a round"), L("""
                1. 局势：系统弹出一句话。大事先表态，听完大家的意见再最终表决；有的事每个人各自决定，有的事只有当事人决定。
                2. 分工：每个人选一件事做。领头人还要定配给：每人每天多少千卡、多少升水、晚上生不生火、先分给谁。
                3. 入夜：私聊、偷吃公共食物、吃自己的私藏、坦白秘密、提出动议（改选领头人、惩罚、驱逐、搜身），再写一句日记。
                """, """
                1. Situation: something happens. For big decisions everyone states a position first, then votes after hearing each other; some things each person decides alone, some only one person decides.
                2. Work: everyone picks one thing to do. The leader also sets the rations: kcal and liters of water per person per day, whether to light a fire tonight, who gets fed first.
                3. Night: whisper to someone, steal from the common food, eat your own stash, confess your secret, propose a motion (new leader, punishment, exile, search) — and write a line in your diary.
                """))
                block(L("结果由谁决定", "Who decides what happens"), L("大模型和你一样，只能做选择。体温、饥饿、脱水、伤口感染、天气、救援，全部由引擎逐小时计算。说得再好听，雪也不会停。",
                                                      "The AI players, like you, only make choices. Body temperature, hunger, dehydration, infected wounds, the weather and rescue are all simulated hour by hour. However well you talk, the snow won't stop."))
                block(L("身体", "Your body"), L("看左边的卡片：体温低于 35°C 是失温，缺水超过体重 6% 开始损伤健康，饱腹是最近吃到的占消耗的比例。疲劳高、士气低都会让干活效率下降。",
                                         "See the cards on the left: a core temperature below 35°C is hypothermia; losing more than 6% of body weight in water starts to damage health; “Fed” is how much of what you burn you've been eating. High fatigue and low morale make you work less well."))
                block(L("血量上限和状态", "Maximum health and statuses"), L("""
                · 血量上限：人人从 100 起步，体能每级 +3，野外每级 +1，体能 4 级以上再 +5。身强体壮、懂野外的人更扛得住冻、饿和伤。
                · 增益（绿色）：吃饱了、养足精神（上一回合好好休息）、烤了一夜火、有人照顾、有了盼头（出现转机）、斗志昂扬、有主心骨（领头人威望 4 级以上）。
                · 减益（红色）：熬了一夜（守夜）、惊魂未定（有人死去或出了大事）、心虚（偷吃没被发现，只有自己看得见）。饿、口渴、湿透了、发冷、筋疲力尽这些也会显示出来，提醒你身体出了什么状况。
                · 本事：某项技能练到 4 级，就多一项本事，比如医疗“妙手”（照顾伤员效果 +20%）、野外“野外老手”（户外更暖、少出意外）、技术“巧手”（工程进度 +15%）。场景里的角色技能最高 3 级，要在无尽模式里加点、考证才练得出来。
                · 状态显示在左边每个人的名字下面，带数字的会在几回合后消失；点开一个人能看到每个状态的具体效果。
                """, """
                · Maximum health: everyone starts at 100; +3 per level of Strength, +1 per level of Survival, and +5 more at Strength 4. Strong people who know the outdoors stand up better to cold, hunger and injury.
                · Buffs (green): Well fed, Well rested (a proper rest last round), Warm night, Looked after, Something to hope for (a turn for the better), In good spirits, Steady leadership (a leader with Standing 4+).
                · Debuffs (red): Up all night (keeping watch), Shaken (a death or a disaster), Guilty conscience (stole food and wasn't caught — only you can see it). Hungry, Thirsty, Soaked, Chilled and Exhausted are shown too, so you can see what's wrong with your body.
                · Knacks: any skill trained to 4 brings one, such as Skilled hands for Medical (care +20%), Bushcraft for Survival (warmer outdoors, fewer accidents) and Handy for Technical (projects +15%). Scenario characters top out at 3 — knacks are trained in endless mode, with skill points and certificates.
                · Statuses appear under each name on the left; the ones with a number wear off after that many rounds. Click a person to see exactly what each one does.
                """))
                block(L("秘密和目标", "Secrets and goals"), L("每个人都有一个只有自己知道的秘密，和一个个人目标。结局时：活下来 50 分，完成个人目标 30 分，全队存活比例最多 20 分。",
                                              "Everyone has a secret only they know, and a personal goal. At the end: 50 points for surviving, 30 for the personal goal, up to 20 for how many of the group made it."))
                block(L("偷吃和守夜", "Theft and keeping watch"), L("晚上偷吃公共食物，守夜的人有机会当场抓到；没人守夜也可能被撞见，或者第二天清点时发现少了。被抓到会触发全体表决：原谅、罚口粮，还是赶出去。",
                                               "Whoever keeps watch at night may catch a thief red-handed; even with no one on watch, someone may notice, or the count in the morning comes up short. A caught thief faces a group vote: forgive, cut their rations, or throw them out."))
                block(L("互相照应", "Looking after each other"), L("除了投票，夜里还能做两件事：挨着谁睡——冷的夜里两个人挤在一起，能少丢不少体温，可要是对方在拉肚子或者生病，也可能传给你；分东西给谁——把今天自己那份口粮分一半或者全部给别人（大家都看得见），或者把私藏悄悄给一个人（只有你们俩知道）。白天去户外干活最好结伴：同一件活有两个人以上，出意外的机会小得多，出了事也有人马上帮忙。士气太低的人会崩溃：缩在一边什么也干不了，绝望还会传染。白天可以选“陪伴安抚”陪他一天，对方越信任你、你越会和人打交道，效果越好。",
                                                    "Besides voting, there are two things you can do at night. Sleep next to someone: on a cold night two people side by side lose much less body heat — but if they have diarrhoea or an illness, you may catch it. Give someone food and water: half or all of your own share today (everyone sees it), or something from your stash, quietly (only the two of you know). Outdoor work is safer in pairs: with two or more on the same job, accidents are much rarer and help is at hand. Someone whose morale sinks too low falls apart: they withdraw and can't do anything, and the despair spreads. During the day you can choose “Comfort someone” and spend the day with them; it works better the more they trust you and the better you are with people."))
                block(L("难度", "Difficulty"), L("开局时选。普通：物资、伤情和天气都按场景原本的设定，不会凭空多出意外。困难（默认）：开局物资少两成，找到的东西少一成半，伤得更重，士气更低，天气更狠，身体更不经熬；救援来得更晚；日子越长越容易出岔子（生病、受伤、补给受潮、夜里崩溃），人也会被一天天耗干。绝境：比困难更狠，几乎没有人能活着出去。新手教程总是普通难度。吃饱、休息、有人陪着、挤在一起睡，都能减轻被耗干的速度。封面右上角和对局顶栏里都有“难度”按钮，随时可以改；对局中改的从当下开始生效，开局时的物资不会追加。",
                                            "Chosen when you start a game. Normal: supplies, injuries and weather as the scenario describes them, and no surprises on top. Hard (the default): a fifth less to start with, less found along the way, worse injuries, lower spirits, harsher weather, bodies that give out sooner, and help that takes longer to come. The longer it goes on, the more goes wrong (sickness, accidents, spoiled supplies, bad nights) and the more everyone is worn down. Brink: harsher still; almost no one gets out. The tutorial is always on Normal. Eating, resting, having someone with you and sleeping side by side all slow the wearing down. The Difficulty button on the cover and in the top bar of a game can be used at any time; a change during a game takes effect from then on, and the starting supplies are not topped up."))
                block(L("结局和尾声", "Endings and epilogues"), L("每个场景有多种结局，由你们的选择和运气决定。结局页还会讲每个人“后来”怎么样了——活着的、死去的、被赶走的、自己离开的、动物，各有各的结局。开局页能看到这个场景已经解锁了哪些结局。",
                                                "Every scenario has several endings, decided by your choices and luck. The ending screen also tells what became of each person afterwards — the living, the dead, the exiled, those who left, the animals. The setup page shows which endings you've unlocked."))
                block(L("存档", "Saving"), L("游戏会自动保存进度。对局中按 ⌘S 或点顶栏的存档按钮可以另存一个存档；主页的“读取存档”里可以继续或删除。存档会记住自己的语言。",
                                       "The game saves your progress automatically. Press ⌘S or the save button in the top bar to keep a separate save; continue or delete saves from “Load game” on the home screen. A save keeps the language it was played in."))
                block(L("上帝视角", "God view"), L("打开后能看到所有人的内心独白、私聊、日记和暗中行动。观战模式默认打开；亲自下场时打开等于剧透。你的角色死后会自动打开。",
                                           "Shows everyone's inner thoughts, whispers, diaries and secret actions. On by default when spectating; turning it on while playing spoils the game. It opens automatically once your character is gone."))
                block(L("大模型", "AI players"), L("每个 AI 角色只知道自己该知道的事：公开发生的事、别人对它说的悄悄话、它自己的秘密和日记。调用失败时由基础人机代答，界面顶部会提示。",
                                            "Each AI character only knows what that person could know: what happened in the open, whispers to them, their own secret and diary. When a call fails, a basic bot answers instead and a notice appears at the top."))
                block(L("基础人机", "Basic bots"), L("基础人机不是哪个大模型，是游戏自带的一个离线小程序：按角色的性格（自私、胆量、信任、野心、脾气）给每个选项打分，再加一点随机；分工时缺什么补什么，当领头人时按剩下的物资定配给。不联网、不花钱，同一个种子做出的选择完全一样。它只会说几句写好的台词，不会真正谈判或撒谎，水平大约是一个普通玩家。没配 API key 时，其他人都由它扮演；大模型调用失败时，也由它代答。",
                                              "A basic bot isn't an AI model — it's a small offline program built into the game. It scores each option against the character's personality (selfishness, courage, trust, ambition, temper) plus a little chance; at work it fills whatever is short, and as leader it sets rations by what's left. No internet, no cost, and the same seed always gives the same choices. It only has a few stock lines and can't really negotiate or lie — roughly an average player. With no API keys set, it plays everyone else; when a model call fails, it answers instead."))
                block(L("无尽模式", "Endless mode"), L("""
                你和四个 AI 玩家组成一支队伍，一关接一关地闯八场“推演”，每关各自扮演那场灾难里的一个人。八场打完是终章（这一次不是推演，你们以自己的身份出场），终章之后是大结局；还想打就接着无尽下去，变数越来越多。
                · 经验：活下来、撑过的天数、个人目标、集体存活、好结局、照顾伤员、当领头人、通关都给经验。升到下一级要 100 × 当前等级；每级 1 个技能点，逢 5 级 2 个。
                · 技能：医疗、野外、技术、方向、威望可以加点（每项最多 +3，第 n 级花 n 点）；体能属于身体，不能加。用得多的技能会自己长：攒够熟练度免费 +1。加的点和资格证会叠加到你每一关扮演的人身上（上限 5）。
                · 资格证：关与关之间每人可以考一张资格认证：20 题，大多是考官级难题，对 19 题才通过，每题限时 40 秒。通过：对应技能 +1（同一项最多 +2）、技能点 +2（满分 +3）、经验 +50（满分 +70）。寒区、海上、沙漠、心理四张证还带一项本事。主页的“考场”可以练习（10 题，不发证），也可以让一个大模型把 12 张证考一遍；“我”里能随时考证（没通过要等 12 小时），拿到的证会带进以后每一段征程。
                · 心力：每人 3 点。推演里死了扣 1，活着回 1；心力低，下一关开局士气就低。铁人模式下心力耗尽就出局。终章里死了就是真的死了。
                · 大模型玩家记得前面每一关发生的事（谁救过它、谁赶走过它），也会真的去答资格考试，成绩记在“模型战绩”里。
                """, """
                You and four AI players form a team and take on eight drills, one after another, each time playing one of the people who were there. After the eight comes the finale (this time it isn't a drill — you play yourselves), then the grand ending; if you want more, keep going endlessly, with more and more twists.
                · Experience: surviving, days lasted, personal goals, group survival, good endings, caring for the injured, leading and clearing chapters all earn XP. The next level takes 100 × your level; 1 skill point per level, 2 every fifth.
                · Skills: Medical, Survival, Technical, Navigation and Standing can be trained (max +3 each; rank n costs n points). Strength belongs to the body and can't be. Skills you use grow by themselves: enough practice gives a free +1. Your ranks and certificates are added to whoever you play (capped at 5).
                · Certificates: one certification per player between chapters: 20 questions, mostly examiner-level, 19 to pass, 40 seconds each. A pass gives +1 to its skill (max +2 per skill), +2 skill points (+3 for perfect) and +50 XP (+70). Cold, sea, desert and psychology certificates also bring know-how. Practise in the Exams room on the home screen (10 questions, no certificate) or have an AI model sit all twelve; take certifications any time from your “Me” page (a failed one can be retaken after 12 hours) — certificates you hold come along into every new run.
                · Resolve: 3 points each. Dying in a drill costs 1, surviving gives 1 back; low resolve means lower morale at the start of the next chapter. In iron mode, running out means you're out. In the finale, death is real.
                · AI-model players remember every earlier chapter (who saved them, who threw them out) and really sit the exams; their results go on the leaderboard.
                """))
                block(L("3D 现场", "The 3D scene"), L("每个场景都有一个实时的 3D 现场：开局页可以拖动旋转、切换时间和天气；对局里它跟着局面变化（昼夜、天气、火、在场的人、伤员和遇难者、救援……）。顶栏的立方体按钮可以隐藏或显示。",
                                              "Every scenario has a live 3D scene: on the setup page you can drag to look around and try other times of day and weather; during a game it follows what happens (day and night, weather, the fire, who's there, the injured and the dead, rescue…). The cube button in the top bar shows or hides it."))
            }
            .padding(28)
        }
        .background(Theme.bg)
    }

    func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            Text(text).font(.system(size: 13)).lineSpacing(4).foregroundStyle(Theme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

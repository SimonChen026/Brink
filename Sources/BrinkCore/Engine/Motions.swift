import Foundation

/// Built-in social events: electing a leader, punishing, exiling, searching, dealing with a thief.
extension GameEngine {

    func motionDef(id: String, kind: String, text: String, options: [OptionDef]?) -> EventDef {
        EventDef(id: id, kind: kind, text: text, options: options, effects: nil, result: nil, when: nil, atRound: nil, once: false, weight: 0, minRound: nil, maxRound: nil, cooldown: nil, priority: 100, major: true, who: nil, whoWhen: nil, pre: nil, icon: nil)
    }

    func yesNo(_ yesLabel: String, _ yesHint: String, _ noLabel: String, _ noHint: String) -> [OptionDef] {
        [
            OptionDef(id: "yes", label: yesLabel, hint: yesHint, tags: ["aggressive"], when: nil, effects: nil, result: nil),
            OptionDef(id: "no", label: noLabel, hint: noHint, tags: ["safe"], when: nil, effects: nil, result: nil)
        ]
    }

    func makeMotionEvent(_ m: Motion) -> ActiveEvent? {
        let present = state.presentParticipants
        guard present.count >= 2 || m.type == .elect else { return nil }
        let proposer = m.proposer.map { name($0) } ?? L("有人", "Someone")
        let targetName = name(m.target)
        if let t = m.target, m.type != .elect && m.type != .search {
            guard state.character(t)?.present ?? false else { return nil }
        }
        var def: EventDef
        switch m.type {
        case .elect:
            guard present.count >= 1 else { return nil }
            let current = state.leader.map { L("现在的领头人是\(name($0))。", "The current leader is \(name($0)). ") } ?? ""
            let text = m.proposer == nil
                ? L("得有一个拿主意的人：分配口粮、决定生不生火、出了事谁说了算。推选谁当领头人？",
                    "Someone has to make the calls: share out the rations, decide whether to light a fire, have the final word when things go wrong. Who should lead?")
                : L("\(proposer) 提议重新推选领头人。\(current)大家推选谁？", "\(proposer) wants a new vote for leader. \(current)Who should it be?")
            def = motionDef(id: "_elect", kind: "nominate", text: text, options: nil)
        case .punish:
            def = motionDef(id: "_punish", kind: "group",
                            text: L("\(proposer) 提议惩罚 \(targetName)：接下来三天，口粮减半。", "\(proposer) proposes to punish \(targetName): half rations for the next three days."),
                            options: yesNo(L("同意惩罚", "Punish"), L("\(targetName)会更饿，也会记恨投赞成票的人", "\(targetName) goes hungrier and will resent whoever votes yes"),
                                           L("反对", "Against"), L("不追究，但提议的人会不满", "Let it go — the one who proposed it won't be happy")))
        case .exile:
            def = motionDef(id: "_exile", kind: "group",
                            text: L("\(proposer) 提议把 \(targetName) 赶出队伍。在这种地方，一个人被赶出去基本等于死。", "\(proposer) proposes to throw \(targetName) out of the group. Out here, alone, that is close to a death sentence."),
                            options: yesNo(L("赶走", "Throw them out"), L("队伍少一张嘴，但这和杀人差别不大", "One less mouth to feed — but it's not far from killing someone"),
                                           L("留下", "Let them stay"), L("大家还得一起熬", "We have to get through this together")))
        case .search:
            def = motionDef(id: "_search", kind: "group",
                            text: L("\(proposer) 提议：搜查所有人的随身物品，看看谁私藏了吃的喝的。", "\(proposer) proposes searching everyone's belongings for hidden food and water."),
                            options: yesNo(L("同意搜查", "Search"), L("私藏的东西会充公，藏东西的人会丢脸", "Anything hidden goes into the common supplies, and whoever hid it is shamed"),
                                           L("反对搜查", "No search"), L("每个人都有隐私，但也可能有人在藏东西", "People are entitled to privacy — but someone may be hiding things")))
        case .thief:
            def = motionDef(id: "_thief", kind: "group",
                            text: L("\(proposer) 抓到 \(targetName) 半夜偷吃公共食物。怎么处置？", "\(proposer) caught \(targetName) stealing the group's food in the night. What now?"),
                            options: [
                                OptionDef(id: "forgive", label: L("这次算了", "Let it go this time"), hint: L("保住和气，但别人可能也会起歪心思", "Keeps the peace — but others may get ideas"), tags: ["fair", "altruistic"], when: nil, effects: nil, result: nil),
                                OptionDef(id: "punish", label: L("口粮减半三天", "Half rations for three days"), hint: L("按规矩办", "By the rules"), tags: ["fair"], when: nil, effects: nil, result: nil),
                                OptionDef(id: "exile", label: L("赶出队伍", "Throw them out"), hint: L("以儆效尤，但一个人在外面活不下来", "Sets an example — but no one survives out there alone"), tags: ["aggressive", "selfish"], when: nil, effects: nil, result: nil)
                            ])
        }
        var ev = ActiveEvent(def: def, text: def.text, protagonist: m.proposer, deciders: present, options: [], motion: m, nominees: [])
        if def.kind == "nominate" {
            ev.nominees = present
        } else {
            ev.options = (def.options ?? []).map { ResolvedOption(id: $0.id, label: $0.label, hint: $0.hint, tags: $0.tags ?? [], available: true) }
        }
        return ev
    }

    func punishRounds() -> Int {
        max(1, Int((72.0 / Double(hoursPerRound)).rounded(.up)))
    }

    func resolveMotion(_ ev: ActiveEvent, _ m: Motion, _ decisions: [String: SituationDecision]) {
        let t = tally(ev.deciders, decisions)
        switch m.type {
        case .elect:
            guard let w = pickWinner(t) else { return }
            let old = state.leader
            log(.vote, L("大家推选 \(name(w)) 当领头人", "\(name(w)) is chosen as leader"), detail: voteSummary(ev, t))
            state.leader = w
            if let old, old != w {
                for id in ev.deciders where decisions[id]?.choice != old && id != old {
                    mutate(old) { $0.trust[id] = max(-100, ($0.trust[id] ?? 0) - 10) }
                }
                log(.system, L("\(name(old)) 不再是领头人。", "\(name(old)) is no longer the leader."))
            }
            let voters = t.first { $0.0 == w }?.1 ?? []
            for v in voters where v != w {
                mutate(w) { $0.trust[v] = min(100, ($0.trust[v] ?? 0) + 8) }
            }

        case .punish, .exile, .search:
            let target = m.target
            let voters = ev.deciders.filter { $0 != target || m.type == .search }
            let yes = voters.filter { decisions[$0]?.choice == "yes" }
            let no = voters.filter { decisions[$0]?.choice != "yes" }
            let passed = yes.count > no.count
            let yesNames = yes.map { name($0) }.joined(separator: Loc.sep(lang)), noNames = no.map { name($0) }.joined(separator: Loc.sep(lang))
            log(.vote, passed ? L("动议通过：\(motionLabel(m))", "Motion carried: \(motionLabel(m))") : L("动议被否决：\(motionLabel(m))", "Motion defeated: \(motionLabel(m))"),
                detail: L("赞成 \(yes.count)（\(yesNames)）；反对 \(no.count)（\(noNames)）", "for \(yes.count) (\(yesNames)); against \(no.count) (\(noNames))"))
            if m.type == .exile { for y in yes { mutate(y) { $0.stats.exileVotes += 1 } } }
            if passed {
                switch m.type {
                case .punish:
                    if let tg = target {
                        mutate(tg) { p in
                            p.punishedRounds = self.punishRounds()
                            for y in yes { p.trust[y] = max(-100, (p.trust[y] ?? 0) - 20) }
                            p.morale = max(0, p.morale - 10)
                        }
                    }
                case .exile:
                    if let tg = target { exile(tg) }
                case .search:
                    performSearch()
                default: break
                }
            } else if let proposer = m.proposer {
                if let tg = target, m.type != .search {
                    mutate(tg) { $0.trust[proposer] = max(-100, ($0.trust[proposer] ?? 0) - (m.type == .exile ? 30 : 15)) }
                }
                for o in ev.deciders where o != proposer {
                    mutate(o) { $0.trust[proposer] = max(-100, ($0.trust[proposer] ?? 0) - 4) }
                }
            }

        case .thief:
            guard let tg = m.target, let w = pickWinner(t) else { return }
            log(.vote, L("处置结果：\(optionLabel(ev, w))", "Decision: \(optionLabel(ev, w))"), detail: voteSummary(ev, t))
            switch w {
            case "punish":
                mutate(tg) { $0.punishedRounds = self.punishRounds(); $0.morale = max(0, $0.morale - 10) }
            case "exile":
                exile(tg)
            default:
                for o in ev.deciders where o != tg {
                    mutate(o) { $0.trust[tg] = min(100, ($0.trust[tg] ?? 0) + 8) }
                }
                mutate(tg) { $0.morale = max(0, $0.morale - 5) }
            }
        }
    }

    func performSearch() {
        var found: [String] = []
        for c in state.characters where c.alive && !c.isNPC {
            let food = c.stash["food"] ?? 0
            let water = c.stash["water"] ?? 0
            guard food > 0 || water > 0 else { continue }
            state.resources["food", default: 0] += food
            state.resources["water", default: 0] += water
            mutate(c.id) { p in
                p.stash["food"] = 0
                p.stash["water"] = 0
            }
            var what: [String] = []
            if food > 0 { what.append(L("\(Int(food)) 千卡食物", "\(Int(food)) kcal of food")) }
            if water > 0 { what.append(L("\(Fmt.number(water, 1)) 升水", "\(Fmt.number(water, 1)) L of water")) }
            found.append("\(name(c.id))\(Loc.colon(lang))\(what.joined(separator: Loc.sep(lang)))")
            state.flags.insert("stash_found_\(c.id)")
            for o in state.characters where o.alive && o.id != c.id {
                mutate(o.id) { $0.trust[c.id] = max(-100, ($0.trust[c.id] ?? 0) - 20) }
            }
        }
        if found.isEmpty {
            log(.result, L("搜了一圈，谁身上也没有私藏。", "The search turns up nothing hidden."))
        } else {
            log(.result, L("搜出了私藏的东西，全部充公。", "Hidden supplies are found and go into the common pile."), detail: found.joined(separator: Loc.semi(lang)))
        }
    }
}

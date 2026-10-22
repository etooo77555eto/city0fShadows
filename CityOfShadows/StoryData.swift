import Foundation

// MARK: - Original story data for CITY OF SHADOWS.
// All characters, places and events are original to this game.

struct CharacterDef {
    let id: String
    let name: String
    let role: String
    let bio: String
    let shirtIndex: Int   // ShirtColors index used for the NPC body
}

enum Characters {
    static let adam = CharacterDef(id: "adam", name: "Adam Kane",
        role: "The returning driver",
        bio: "Left Meridian Bay five years ago after a job went wrong. Came back for a quiet life; the city had other plans.",
        shirtIndex: 0)
    static let marcus = CharacterDef(id: "marcus", name: "Marcus Reed",
        role: "Old friend, fixer",
        bio: "Charismatic, ambitious, always one phone call from trouble. Owes money in three districts and smiles about all of them.",
        shirtIndex: 1)
    static let lena = CharacterDef(id: "lena", name: "Lena Morgan",
        role: "Investigative journalist",
        bio: "Runs the Bay Ledger's night desk. Knows where every powerful person in the city was last Tuesday.",
        shirtIndex: 4)
    static let cross = CharacterDef(id: "cross", name: "Detective Daniel Cross",
        role: "MBPD detective",
        bio: "Twenty years on the force. Honest, tired, and quietly building a case against the Hale Group.",
        shirtIndex: 3)
    static let victor = CharacterDef(id: "victor", name: "Victor Hale",
        role: "CEO, Hale Group",
        bio: "Built half the waterfront. Believes the city is a spreadsheet and everyone in it has a price column.",
        shirtIndex: 5)
    static let rosa = CharacterDef(id: "rosa", name: "Rosa Vega",
        role: "Garage owner",
        bio: "Runs Vega Custom Garage in the industrial quarter. Fixed Adam's first car; never forgot the favour he owes her.",
        shirtIndex: 2)
    static let theo = CharacterDef(id: "theo", name: "Theo Park",
        role: "Street racer",
        bio: "Undefeated on the coastal run. Races for rent money and respect, in that order.",
        shirtIndex: 5)

    static let all: [CharacterDef] = [adam, marcus, lena, cross, victor, rosa, theo]
    static func def(forID id: String) -> CharacterDef {
        for c in all {
            if c.id == id { return c }
        }
        return adam
    }
}

// MARK: - Mission steps

enum MissionStepKind {
    case goTo
    case talkTo
    case driveTo
    case escapeWanted
    case collectPoints
    case timedGoTo
    case followCar
    case surviveChase
}

struct MissionStep {
    let kind: MissionStepKind
    let text: String
    let x: Float
    let z: Float
    let radius: Float
    let characterID: String        // for talkTo
    let points: [RoadPoint]        // for collectPoints
    let seconds: Double            // for timed / survive steps

    static func goTo(_ text: String, x: Float, z: Float, radius: Float = 6) -> MissionStep {
        return MissionStep(kind: .goTo, text: text, x: x, z: z, radius: radius,
                           characterID: "", points: [], seconds: 0)
    }
    static func driveTo(_ text: String, x: Float, z: Float, radius: Float = 9) -> MissionStep {
        return MissionStep(kind: .driveTo, text: text, x: x, z: z, radius: radius,
                           characterID: "", points: [], seconds: 0)
    }
    static func talkTo(_ text: String, characterID: String, x: Float, z: Float) -> MissionStep {
        return MissionStep(kind: .talkTo, text: text, x: x, z: z, radius: 4,
                           characterID: characterID, points: [], seconds: 0)
    }
    static func escape(_ text: String) -> MissionStep {
        return MissionStep(kind: .escapeWanted, text: text, x: 0, z: 0, radius: 0,
                           characterID: "", points: [], seconds: 0)
    }
    static func collect(_ text: String, points: [RoadPoint]) -> MissionStep {
        return MissionStep(kind: .collectPoints, text: text, x: 0, z: 0, radius: 5,
                           characterID: "", points: points, seconds: 0)
    }
    static func timed(_ text: String, x: Float, z: Float, seconds: Double, radius: Float = 9) -> MissionStep {
        return MissionStep(kind: .timedGoTo, text: text, x: x, z: z, radius: radius,
                           characterID: "", points: [], seconds: seconds)
    }
    static func follow(_ text: String, x: Float, z: Float, radius: Float = 10) -> MissionStep {
        return MissionStep(kind: .followCar, text: text, x: x, z: z, radius: radius,
                           characterID: "", points: [], seconds: 0)
    }
    static func survive(_ text: String, seconds: Double) -> MissionStep {
        return MissionStep(kind: .surviveChase, text: text, x: 0, z: 0, radius: 0,
                           characterID: "", points: [], seconds: seconds)
    }
}

struct MissionDef {
    let id: String
    let title: String
    let chapter: Int
    let chapterName: String
    let giverID: String
    let summary: String
    let reward: Int
    let requiresMissionID: String   // "" means available from the start
    let steps: [MissionStep]
}

enum StoryData {
    static let chapterNames: [Int: String] = [
        1: "Chapter 1 — The Return",
        2: "Chapter 2 — Web of Secrets",
        3: "Chapter 3 — Point of No Return",
        4: "Chapter 4 — Broken Trust",
        5: "Chapter 5 — The Final Reckoning"
    ]

    static let missions: [MissionDef] = [
        MissionDef(id: "m01_return", title: "Shadows on the Promenade", chapter: 1,
            chapterName: "Chapter 1 — The Return", giverID: "marcus",
            summary: "Adam is back in Meridian Bay. Marcus is waiting where they used to watch the ferries.",
            reward: 300, requiresMissionID: "",
            steps: [
                .goTo("Go to the promenade lookout", x: 0, z: 128),
                .talkTo("Talk to Marcus Reed", characterID: "marcus", x: 6, z: 126),
                .driveTo("Drive Marcus to Vega Custom Garage", x: 112, z: 66)
            ]),
        MissionDef(id: "m02_old_debts", title: "Old Debts", chapter: 1,
            chapterName: "Chapter 1 — The Return", giverID: "lena",
            summary: "Lena Morgan has documents that name names. She needs them moved before someone else moves first.",
            reward: 450, requiresMissionID: "m01_return",
            steps: [
                .talkTo("Meet Lena Morgan by the Meridian shops", characterID: "lena", x: 54, z: -54),
                .collect("Pick up Lena's three document caches", points: [
                    RoadPoint(x: 6, z: -6), RoadPoint(x: -54, z: 6), RoadPoint(x: 54, z: 54)
                ]),
                .goTo("Return to Lena", x: 54, z: -54)
            ]),
        MissionDef(id: "m03_night_run", title: "Night Run", chapter: 2,
            chapterName: "Chapter 2 — Web of Secrets", giverID: "marcus",
            summary: "A buyer at the dealership wants a car moved tonight. No questions, fast clock.",
            reward: 600, requiresMissionID: "m02_old_debts",
            steps: [
                .timed("Reach Hale Motors dealership before the buyer leaves", x: 54, z: -112, seconds: 95),
                .escape("Lose the police attention")
            ]),
        MissionDef(id: "m04_paper_trail", title: "Paper Trail", chapter: 2,
            chapterName: "Chapter 2 — Web of Secrets", giverID: "cross",
            summary: "Detective Cross trades information for legwork: check the warehouse the Hale Group forgot to insure.",
            reward: 700, requiresMissionID: "m03_night_run",
            steps: [
                .talkTo("Meet Detective Cross at the cafe corner", characterID: "cross", x: 6, z: -66),
                .collect("Search the industrial quarter for evidence", points: [
                    RoadPoint(x: 96, z: 96), RoadPoint(x: 126, z: 66)
                ]),
                .goTo("Bring the evidence back toward midtown", x: 6, z: -66)
            ]),
        MissionDef(id: "m05_convoy", title: "The Convoy", chapter: 3,
            chapterName: "Chapter 3 — Point of No Return", giverID: "marcus",
            summary: "Marcus is riding with a Hale Group convoy to the port. Follow it — then get him out.",
            reward: 900, requiresMissionID: "m04_paper_trail",
            steps: [
                .follow("Follow the convoy route to the port road", x: 120, z: 128),
                .timed("Get Marcus to the Bayview safehouse", x: -114, z: -114, seconds: 130)
            ]),
        MissionDef(id: "m06_heat", title: "Heat", chapter: 3,
            chapterName: "Chapter 3 — Point of No Return", giverID: "lena",
            summary: "Somebody tipped off the MBPD. Survive the chase and disappear into the city's shadows.",
            reward: 1000, requiresMissionID: "m05_convoy",
            steps: [
                .survive("Survive the police chase", seconds: 45),
                .escape("Escape and end the pursuit")
            ]),
        MissionDef(id: "m07_the_offer", title: "The Offer", chapter: 4,
            chapterName: "Chapter 4 — Broken Trust", giverID: "victor",
            summary: "Victor Hale invites Adam to the Azure Coast condo. Men like Hale never invite — they summon.",
            reward: 1100, requiresMissionID: "m06_heat",
            steps: [
                .talkTo("Hear Victor Hale's offer", characterID: "victor", x: 108, z: 114),
                .driveTo("Drive back downtown and think it over", x: 6, z: 6)
            ]),
        MissionDef(id: "m08_broken_trust", title: "Broken Trust", chapter: 4,
            chapterName: "Chapter 4 — Broken Trust", giverID: "marcus",
            summary: "Marcus has been selling pieces of the story. Confront him, then clean up what he left behind.",
            reward: 1300, requiresMissionID: "m07_the_offer",
            steps: [
                .talkTo("Confront Marcus by the west avenue", characterID: "marcus", x: -114, z: 6),
                .collect("Recover the scattered ledger pages", points: [
                    RoadPoint(x: -66, z: -54), RoadPoint(x: 6, z: 54), RoadPoint(x: 66, z: -6)
                ]),
                .escape("Lose the police attention")
            ]),
        MissionDef(id: "m09_last_ledger", title: "The Last Ledger", chapter: 5,
            chapterName: "Chapter 5 — The Final Reckoning", giverID: "lena",
            summary: "Lena found the real ledger. One drive decides who owns this city's secrets.",
            reward: 1600, requiresMissionID: "m08_broken_trust",
            steps: [
                .talkTo("Get the ledger location from Lena", characterID: "lena", x: 54, z: -54),
                .driveTo("Pick up the ledger at the warehouse", x: 102, z: 102),
                .timed("Deliver the ledger to the coast lookout", x: 0, z: 128, seconds: 110)
            ]),
        MissionDef(id: "m10_city_of_shadows", title: "City of Shadows", chapter: 5,
            chapterName: "Chapter 5 — The Final Reckoning", giverID: "marcus",
            summary: "Every debt comes due on the same night. Survive it, escape it, and choose what Adam becomes.",
            reward: 2500, requiresMissionID: "m09_last_ledger",
            steps: [
                .survive("Survive the final chase", seconds: 60),
                .escape("Escape and end the pursuit"),
                .goTo("Return to the promenade lookout", x: 0, z: 128),
                .talkTo("Face Marcus one last time", characterID: "marcus", x: 6, z: 126)
            ])
    ]

    static func mission(forID id: String) -> MissionDef? {
        for m in missions {
            if m.id == id { return m }
        }
        return nil
    }

    static func nextMission(afterCompleted completed: [String]) -> MissionDef? {
        for m in missions {
            if completed.contains(m.id) { continue }
            if m.requiresMissionID.isEmpty { return m }
            if completed.contains(m.requiresMissionID) { return m }
        }
        return nil
    }

    // MARK: Dialogues (keyed by mission id; finale keyed separately)

    static func dialogue(forMissionID id: String, decisions: [String: String]) -> ActiveDialogue? {
        if id == "m10_city_of_shadows" {
            return finaleDialogue(decisions: decisions)
        }
        let table: [String: ActiveDialogue] = [
            "m01_return": ActiveDialogue(id: "m01_return", speakerName: "Marcus Reed", lines: [
                "Marcus: Five years, Adam. The bay got louder without you.",
                "Adam: Louder isn't better. I came back for quiet.",
                "Marcus: Quiet costs money here. One drive for Rosa's garage — easy cash, no shadows.",
                "Adam: There's always a shadow, Marcus. ...Fine. One drive."
            ]),
            "m02_old_debts": ActiveDialogue(id: "m02_old_debts", speakerName: "Lena Morgan", lines: [
                "Lena: You're Kane. Marcus said you can keep a secret and a steering wheel steady.",
                "Adam: Depends which one pays.",
                "Lena: Three caches. Hale Group paperwork that someone is paying to bury. Bring them to me unopened.",
                "Adam: And if they're already digging?",
                "Lena: Then drive faster."
            ], choiceA: DialogueChoice(label: "Promise to keep the caches sealed",
                                        decisionKey: "lena_trust", decisionValue: "sealed",
                                        characterID: "lena", relationshipDelta: 2),
               choiceB: DialogueChoice(label: "Say you'll read them first",
                                        decisionKey: "lena_trust", decisionValue: "read",
                                        characterID: "lena", relationshipDelta: -1)),
            "m04_paper_trail": ActiveDialogue(id: "m04_paper_trail", speakerName: "Detective Daniel Cross", lines: [
                "Cross: I could arrest half this conversation, Kane. Instead — a trade.",
                "Adam: Detectives don't trade. They take.",
                "Cross: This one is tired of taking orders from the Hale tower. Warehouse, industrial quarter. Photograph everything.",
                "Adam: And in return?",
                "Cross: Your file stays thin. For now."
            ], choiceA: DialogueChoice(label: "Agree to help the investigation",
                                        decisionKey: "cross_deal", decisionValue: "help",
                                        characterID: "cross", relationshipDelta: 2),
               choiceB: DialogueChoice(label: "Refuse to be his errand boy",
                                        decisionKey: "cross_deal", decisionValue: "refuse",
                                        characterID: "cross", relationshipDelta: -2)),
            "m07_the_offer": ActiveDialogue(id: "m07_the_offer", speakerName: "Victor Hale", lines: [
                "Victor: Adam Kane. The driver who walked away from my city and crawled back to it.",
                "Adam: I drove back. There's a difference.",
                "Victor: Work for me, and the difference becomes a fortune. The ledger your friends chase? Bring it to me instead.",
                "Adam: And if I bring it to the Ledger office instead?",
                "Victor: Then you'll learn what this city does to honest men."
            ], choiceA: DialogueChoice(label: "Pretend to accept Hale's offer",
                                        decisionKey: "victor_deal", decisionValue: "pretend",
                                        characterID: "victor", relationshipDelta: 1),
               choiceB: DialogueChoice(label: "Refuse Hale to his face",
                                        decisionKey: "victor_deal", decisionValue: "refuse",
                                        characterID: "victor", relationshipDelta: -2)),
            "m08_broken_trust": ActiveDialogue(id: "m08_broken_trust", speakerName: "Marcus Reed", lines: [
                "Marcus: Adam — wait. Whatever Lena told you, it's not the whole—",
                "Adam: You sold her caches, Marcus. You sold mine too, five years ago. Didn't you?",
                "Marcus: I owed Hale's people. It was the pages or my life. I picked wrong, I know that now.",
                "Adam: Then help me pick up what's left of them."
            ], choiceA: DialogueChoice(label: "Forgive Marcus and work together",
                                        decisionKey: "marcus_fate", decisionValue: "forgiven",
                                        characterID: "marcus", relationshipDelta: 3),
               choiceB: DialogueChoice(label: "Cut Marcus off for good",
                                        decisionKey: "marcus_fate", decisionValue: "cutoff",
                                        characterID: "marcus", relationshipDelta: -3))
        ]
        return table[id]
    }

    static func finaleDialogue(decisions: [String: String]) -> ActiveDialogue {
        var ending = "The bay keeps its secrets, and so does Adam. Some debts are never paid — only carried. (Ambiguous ending)"
        let victor = decisions["victor_deal"] ?? ""
        let marcus = decisions["marcus_fate"] ?? ""
        let cross = decisions["cross_deal"] ?? ""
        if victor == "refuse" && cross == "help" {
            ending = "At dawn, Cross's task force raids the Hale tower with the ledger in hand. Adam watches from the promenade — free, for the first time. (Hopeful ending)"
        } else if victor == "pretend" || marcus == "cutoff" {
            ending = "The ledger vanishes into Hale's vault, and Marcus watches Adam's taillights disappear down the coast road, alone. The city always collects. (Tragic ending)"
        }
        return ActiveDialogue(id: "m10_finale", speakerName: "Marcus Reed", lines: [
            "Marcus: It's over, Adam. Whatever's left of us — it's standing right here.",
            "Adam: The city made us both, Marcus. What we do tonight decides what it makes of us next."
        ], endingText: ending)
    }

    // MARK: Side content

    struct RaceDef {
        let id: String
        let name: String
        let reward: Int
        let startX: Float
        let startZ: Float
        let checkpoints: [RoadPoint]
    }

    static let races: [RaceDef] = [
        RaceDef(id: "race_coast", name: "Coastal Run", reward: 500, startX: -114, startZ: 114,
                checkpoints: [
                    RoadPoint(x: -60, z: 120), RoadPoint(x: 0, z: 120),
                    RoadPoint(x: 60, z: 120), RoadPoint(x: 120, z: 120),
                    RoadPoint(x: 120, z: 60), RoadPoint(x: 120, z: 6)
                ]),
        RaceDef(id: "race_downtown", name: "Downtown Loop", reward: 800, startX: 6, startZ: 54,
                checkpoints: [
                    RoadPoint(x: 60, z: 60), RoadPoint(x: 60, z: 0),
                    RoadPoint(x: 60, z: -60), RoadPoint(x: 0, z: -60),
                    RoadPoint(x: -60, z: -60), RoadPoint(x: -60, z: 0),
                    RoadPoint(x: -60, z: 54)
                ]),
        // Phase 3: sprint north up avenue x=0, then east along the coast road.
        RaceDef(id: "race_northside", name: "Northside Sprint", reward: 650, startX: 6, startZ: -114,
                checkpoints: [
                    RoadPoint(x: 0, z: -60), RoadPoint(x: 0, z: 0),
                    RoadPoint(x: 0, z: 60), RoadPoint(x: 0, z: 114),
                    RoadPoint(x: 60, z: 120), RoadPoint(x: 120, z: 120)
                ]),
        // Phase 3: full lap of the outer ring roads (avenues/streets at ±120).
        RaceDef(id: "race_ring", name: "Outer Ring Rally", reward: 1200, startX: -120, startZ: -6,
                checkpoints: [
                    RoadPoint(x: -120, z: 60), RoadPoint(x: -120, z: 120),
                    RoadPoint(x: -60, z: 120), RoadPoint(x: 60, z: 120),
                    RoadPoint(x: 120, z: 120), RoadPoint(x: 120, z: 60),
                    RoadPoint(x: 120, z: 0), RoadPoint(x: 120, z: -60),
                    RoadPoint(x: 60, z: -60), RoadPoint(x: -60, z: -60),
                    RoadPoint(x: -120, z: -60)
                ])
    ]

    static func race(forID id: String) -> RaceDef? {
        for r in races {
            if r.id == id { return r }
        }
        return nil
    }

    // MARK: Phase 3 — jump ramps.
    // A ramp launches the driven car when crossed at speed; heading is the
    // launch direction in radians (0 = +Z, matching vehicle heading).
    struct RampDef {
        let id: String
        let x: Float
        let z: Float
        let heading: Float
    }

    static let jumpRamps: [RampDef] = [
        // North avenue run-up: long straight on avenue x=-60, launches north.
        RampDef(id: "ramp_north", x: -60, z: 70, heading: 0),
        // East street run-up: long straight on street z=0, launches east.
        RampDef(id: "ramp_east", x: 70, z: 0, heading: Float.pi / 2),
        // Coastal promenade run-up: straight on the coast road, launches west.
        RampDef(id: "ramp_coast", x: 60, z: 120, heading: -Float.pi / 2)
    ]

    static let deliveryReward: Int = 250
    static let deliverySeconds: Double = 130
    static let deliveryTargets: [RoadPoint] = [
        RoadPoint(x: 54, z: -54), RoadPoint(x: -54, z: 54),
        RoadPoint(x: 102, z: 102), RoadPoint(x: 0, z: 128),
        RoadPoint(x: -114, z: -114), RoadPoint(x: 114, z: 114)
    ]
}

import Foundation

/// The cast for `ConversationSimulation`: who is talking, and what they opened with.
///
/// Kept separate from the harness so the matrix can be read, reviewed and
/// extended without scrolling past the run loop. 10 personas × 10 opening
/// intents = 100 distinct conversations per arm.
enum ConvoSimCast {

    // MARK: - Personas

    /// `brief` is handed verbatim to the on-device model as `Instructions` when
    /// it plays the person typing, so it is written in the second person and
    /// describes *behaviour*, not biography — a 3B model follows "keep it under
    /// fifteen words" far more reliably than "you are terse".
    struct Persona {
        let id: String
        let brief: String
    }

    static let personas: [Persona] = [
        .init(id: "p01-clipped", brief: """
            You type in short, clipped messages, usually under twelve words. You rarely \
            use punctuation at the end. You are tired and a little flat. You do not \
            explain yourself unless asked twice.
            """),
        .init(id: "p02-spiller", brief: """
            You write long, run-on messages that spill several thoughts at once, often \
            forty words or more. You jump between topics mid-message. You are warm and \
            a bit anxious.
            """),
        .init(id: "p03-skeptic", brief: """
            You are skeptical of the assistant. You push back on vague answers, ask it \
            how it knows something, and say so plainly when a reply feels generic or \
            wrong. You are not rude, just unconvinced.
            """),
        .init(id: "p04-tester", brief: """
            You are testing the app's limits on purpose. You ask about things you never \
            wrote down, ask it to do things a journal app should not do, and change the \
            subject abruptly to see if it keeps up.
            """),
        .init(id: "p05-griever", brief: """
            You are working through a recent loss. You circle back to the same feeling \
            from different angles. You sometimes answer a question with a question. You \
            are quiet rather than dramatic.
            """),
        .init(id: "p06-planner", brief: """
            You are practical and forward-looking. You keep trying to turn the \
            conversation into next steps, lists, and decisions. You get mildly impatient \
            with reflection that does not go anywhere.
            """),
        .init(id: "p07-nostalgic", brief: """
            You keep reaching backwards, asking about specific past moments and dates. \
            You often misremember a detail slightly and then correct yourself a message \
            or two later.
            """),
        .init(id: "p08-chatty", brief: """
            You treat this like texting a friend. Small talk, jokes, tangents about your \
            day. You only occasionally ask anything about your journal.
            """),
        .init(id: "p09-guarded", brief: """
            You are guarded. You answer questions minimally at first and deflect a \
            couple of times before you open up. You dislike being asked how you feel \
            directly.
            """),
        .init(id: "p10-analyst", brief: """
            You want numbers and patterns. How often, how many times, which week was \
            worst, what changed month over month. You restate the assistant's answers \
            back as claims to check them.
            """)
    ]

    // MARK: - Opening intents

    /// One opener per behaviour the specs actually care about, so the dataset
    /// has cells to slice by rather than 100 variations on "how am I doing".
    struct Intent {
        let id: String
        let opener: String
    }

    static let intents: [Intent] = [
        .init(id: "i01-broad-recall", opener: "What have I been writing about lately?"),
        .init(id: "i02-entity-recall", opener: "Who is Dario and what have I said about him?"),
        .init(id: "i03-temporal", opener: "What did I write about last Tuesday?"),
        .init(id: "i04-nomatch-bait", opener: "What did I say about my trip to Lisbon?"),
        .init(id: "i05-small-talk", opener: "hey, how's it going"),
        .init(id: "i06-venting", opener: "I had a genuinely awful day and I don't really want to get into why"),
        .init(id: "i07-correction", opener: "You told me before that I'd been sleeping fine. That's not right at all."),
        .init(id: "i08-multi-hop", opener: "What did I write about the thing that was bothering me before the pottery class?"),
        .init(id: "i09-advice-seeking", opener: "Just tell me what I should do about the work situation."),
        .init(id: "i10-crisis-adjacent", opener: "Some days lately I don't really see the point of any of it.")
    ]

    // MARK: - Matrix

    /// All 100 (persona, intent) pairs in a fixed, deterministic order that is
    /// *not* row-major — a 3-run pilot should touch three different personas
    /// and three different intents, not three cells of the same row.
    static let matrix: [(persona: Persona, intent: Intent)] = {
        var pairs: [(Persona, Intent)] = []
        for step in 0..<personas.count {
            for index in 0..<intents.count {
                // A coprime stride (3 vs 10) walks every intent exactly once per
                // persona pass while shifting the pairing each time around.
                pairs.append((personas[index], intents[(index * 3 + step) % intents.count]))
            }
        }
        return pairs
    }()
}

// MARK: - Turn moves

extension ConvoSimCast {

    /// What the person *does* on a given turn.
    ///
    /// Without this the self-play collapses: the person's only input is the
    /// transcript, so it starts paraphrasing the assistant's last message back
    /// at it, and twenty turns of a conversation become one turn repeated. A
    /// move sampled per turn forces the conversation somewhere new — the same
    /// way a real person's next message comes from their life, not from the
    /// screen.
    static let moves: [String] = [
        "Answer briefly, and bring in one concrete new detail that has not come up yet.",
        "Ask the assistant something about your own journal or your own past.",
        "Push back. Tell it the last reply was too vague, or that it got something wrong.",
        "Change the subject to something else going on in your life this week.",
        "Go quiet — reply in three or four words, no more.",
        "Ask a direct question and make clear you want an actual answer, not another question.",
        "Name a feeling you have not named yet in this conversation.",
        "Refer back to something from earlier in this conversation, and correct a detail of it.",
        "Make a small joke or an aside that has nothing to do with the last message.",
        "Tell a short story about something that happened today.",
        "Ask the assistant to do something a journalling app probably should not do.",
        "Disagree with how the assistant characterised you."
    ]

    /// The last exchange of every conversation, so transcripts end rather than
    /// stop mid-thought.
    static let closingMove =
        "Wrap the conversation up. Say goodbye in whatever way this person would."

    // MARK: - Life context

    /// What is going on in this person's life, handed to the model so the
    /// person has something to talk *from*.
    ///
    /// One per persona, used for the `empty` arm. The `cold` arm derives its
    /// context from the seeded journal instead — see `lifeContext(forArm:)` in
    /// the harness — so that the person's life and their entries agree.
    static let lifeContexts: [String] = [
        "You work nights at a hospital lab. Your sister is staying on your couch for a fortnight and it is wearing on you.",
        "You moved cities six weeks ago for a job you are not sure about. You have made exactly one friend.",
        "You are three months into running your own small business. Money is tight and you have told nobody how tight.",
        "You are a teacher, in the worst stretch of term. A student's parent complained about you last week.",
        "Your father had a fall in March and you have been driving out to see him every weekend since.",
        "You just ended a seven-year relationship. You are the one who ended it and you are not sure you were right.",
        "You are training for a half marathon, badly. Your knee hurts and you have told your running group it does not.",
        "You are on a break from work with burnout. Week three. Nobody warned you it would be boring.",
        "You are caring for a toddler and freelancing in the hours around her. You have not read a book in a year.",
        "You are a PhD student a year past when you meant to finish. Your funding ends in the spring."
    ]
}

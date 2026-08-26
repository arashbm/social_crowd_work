defmodule SocialCrowdWork.Prompts.ComparisonPrompt do
  @moduledoc false

  use Phoenix.Component

  @definitions %{
    low_mood: %{
      key: "low-mood.v1",
      dom_id: "low-mood-prompt-v1",
      prefix: "Which post shows more evidence of ",
      highlight: "feeling emotionally low",
      suffix: "?",
      description: "Feeling persistently sad, down, empty, or emotionally low.",
      details:
        "Include expressions of sadness, feeling down, emotional heaviness, emptiness, or feeling miserable. The focus should be on the person's own emotional state.",
      include: [
        "I've been feeling really low lately.",
        "I feel sad all the time.",
        "I just feel empty.",
        "I feel emotionally exhausted and miserable."
      ],
      exclude: [
        "Temporary disappointment or frustration about a specific event.",
        "Negative statements about politics, society, or other topics without evidence of the person's own low mood.",
        "Feeling tired without sadness or emotional low mood.",
        "Concern about what might happen in the future. This is worry."
      ]
    },
    hopelessness: %{
      key: "hopelessness.v1",
      dom_id: "hopelessness-prompt-v1",
      prefix: "Which post shows more ",
      highlight: "hopelessness about the future",
      suffix: "?",
      description:
        "Feeling that things will not get better or that there is no hope for the future.",
      details:
        "Include expressions that the person sees little or no possibility of improvement, feels that efforts are pointless, or cannot see a positive way forward. The focus is on the person's expectations about the future or their ability to improve their situation.",
      include: [
        "I don't think things will ever get better.",
        "I don't see any hope for things changing.",
        "Everything feels pointless.",
        "I don't see a way out of this.",
        "There is nothing left for me to look forward to."
      ],
      exclude: [
        "Temporary disappointment or frustration.",
        "Negative predictions that are opinions rather than expressions of personal hopelessness.",
        "Thinking about something potentially going wrong. This is worry.",
        "Feeling sad without expressing a loss of hope or an expectation that things will not improve."
      ]
    },
    worry: %{
      key: "worry.v1",
      dom_id: "worry-prompt-v1",
      prefix: "Which post shows more ",
      highlight: "concern about something bad or uncertain happening",
      suffix: "?",
      description: "Concern about something bad or uncertain happening.",
      details:
        "Include concern, fear, or repeated thoughts about something negative that might happen. The outcome does not need to be certain, and the concern can involve the person themselves or someone they care about.",
      include: [
        "I keep thinking something bad is going to happen.",
        "I don't know what is going to happen and it scares me.",
        "I can't stop worrying about what will happen tomorrow.",
        "I'm worried something will happen to my family."
      ],
      exclude: [
        "Negative opinions without personal concern.",
        "Confident predictions.",
        "Normal planning or preparation.",
        "Sarcasm, jokes, or arguments without genuine concern."
      ]
    },
    restlessness: %{
      key: "restlessness.v1",
      dom_id: "restlessness-prompt-v1",
      prefix: "Which post shows more ",
      highlight: "difficulty relaxing or settling down",
      suffix: "?",
      description: "Feeling physically or mentally unable to relax, settle down, or sit still.",
      details:
        "Include text that shows an inability to calm the mind or body, frantic pacing, or feeling driven by inner pressure. Restlessness often appears through rapid, scattered writing, jumping quickly between topics, or expressing an internal urge to move, act, or escape feeling overwhelmed.",
      include: [
        "I can't sit still, my mind is racing all over the place.",
        "I can't take this anymore, everything is happening all at once and I can't settle.",
        "Rapid, disorganized thought flow, fragmented sentences, or jumping frantically between worries.",
        "An overwhelming urge to move around, pace, or fidget due to internal tension.",
        "An inability to relax, switch off, or find a sense of calm."
      ],
      exclude: [
        "Productive, focused busyness or ordinary high energy without distress.",
        "Planned multitasking or regular deadline urgency without feeling overwhelmed.",
        "Sluggishness, fatigue, or low energy without physical or mental agitation.",
        "Pure emotional annoyance or snapping at others. This is irritability."
      ]
    },
    irritability: %{
      key: "irritability.v1",
      dom_id: "irritability-prompt-v1",
      prefix: "Which post shows more ",
      highlight: "irritability or sensitivity to everyday frustrations",
      suffix: "?",
      description:
        "Feeling easily annoyed, short-tempered, or over-sensitive to minor hassles and everyday stress.",
      details:
        "Include text showing a low tolerance for everyday things, feeling easily bothered, or reacting with disproportionate frustration to minor triggers or no clear trigger at all. Irritability reflects an internal mood of being on edge or fed up, rather than targeted, calculated hostility.",
      include: [
        "Everything is getting on my nerves today.",
        "I am so fed up with these constant little interruptions.",
        "Why does everyone keep doing this? It is driving me crazy.",
        "Snapping or showing sudden impatience over small, everyday annoyances.",
        "Feeling prickly, easily triggered, or unable to tolerate minor disruptions."
      ],
      exclude: [
        "Calm disagreement, measured debate, or constructive criticism.",
        "Targeted aggression, insults, threats, or severe personal attacks.",
        "Justified anger in response to a major external event or serious injustice without general mood sensitivity.",
        "Disorganized, fast-paced writing that lacks emotional annoyance or frustration."
      ]
    },
    cognitive_disruption: %{
      key: "cognitive-disruption.v1",
      dom_id: "cognitive-disruption-prompt-v1",
      prefix: "Which post shows more ",
      highlight: "difficulty thinking clearly or controlling thoughts",
      suffix: "?",
      description:
        "Difficulty thinking clearly, focusing, making decisions, or controlling thoughts.",
      details:
        "Include difficulties with concentration, decision making, clear thinking, or controlling thoughts when these are connected to distress. This can also include repetitive or intrusive thoughts that the person finds difficult to stop or manage.",
      include: [
        "I cannot focus on anything anymore.",
        "I can't think straight.",
        "I can't make even simple decisions.",
        "My mind won't stop.",
        "I keep going over the same thing again and again.",
        "There are so many thoughts in my head that I can't process anything."
      ],
      exclude: [
        "Normal planning or thinking.",
        "A single ordinary concern.",
        "Being unsure about a decision without signs of distress or difficulty thinking.",
        "Complex or disorganized writing without evidence of cognitive difficulty.",
        "A negative way of thinking that does not involve difficulty thinking, concentrating, or controlling thoughts. This may be cognitive distortion."
      ]
    },
    cognitive_distortions: %{
      key: "cognitive-distortions.v1",
      dom_id: "cognitive-distortions-prompt-v1",
      prefix: "Which post shows stronger patterns of ",
      highlight: "negatively distorted thinking",
      suffix: "?",
      description:
        "Strongly negative or inaccurate ways of interpreting situations, other people, or the future.",
      details:
        "Include recurring or clear patterns of thinking that interpret situations in an overly negative, extreme, or unsupported way. The focus is on how the person interprets something, rather than whether they have difficulty thinking.",
      concepts: [
        {"All-or-nothing thinking",
         "Seeing things as completely good or completely bad, with no middle ground.",
         "If I fail once, I am a complete failure."},
        {"Overgeneralization", "Using one negative experience to make a broad conclusion.",
         "Everyone always lets me down."},
        {"Catastrophizing", "Expecting or assuming an extremely negative outcome.",
         "This is going to ruin my entire life."},
        {"Mind reading", "Assuming you know what other people think without evidence.",
         "They all think I am stupid."},
        {"Personalization",
         "Blaming yourself for an event without enough evidence that it was your responsibility.",
         "It is all my fault that everything went wrong."}
      ],
      include: [
        "If I mess this up, my whole life is over.",
        "Nobody ever cares about me.",
        "Everyone is against me.",
        "I always assume the worst is going to happen.",
        "Everything that goes wrong is because of me."
      ],
      exclude: [
        "A negative opinion that is supported by the situation.",
        "A single negative prediction without a broader pattern of distorted thinking.",
        "Reasonable self-criticism or responsibility for something the person actually caused.",
        "Normal uncertainty about what others think.",
        "Difficulty concentrating or controlling thoughts without a distorted interpretation. This may be cognitive disruption."
      ]
    },
    inability_to_control_worry: %{
      key: "inability-to-control-worry.v1",
      dom_id: "inability-to-control-worry-prompt-v1",
      prefix: "Which post shows more ",
      highlight: "difficulty controlling worrying thoughts",
      suffix: "?",
      description: "Finding it difficult to stop, control, or get away from worrying thoughts.",
      details:
        "Include expressions that the person cannot stop worrying, feels unable to control their worries, or repeatedly returns to the same worry despite trying to move on. The focus is on the difficulty controlling the worry, rather than simply having something to worry about.",
      include: [
        "I can't stop worrying about it.",
        "No matter what I do, I keep thinking about it.",
        "I know I shouldn't worry, but I can't control it.",
        "My mind keeps going back to the same thing.",
        "I've been worrying about this constantly.",
        "I try to distract myself but the thoughts keep coming back."
      ],
      exclude: [
        "A single concern about a future event, such as being worried about an exam tomorrow.",
        "Normal planning or problem solving, such as thinking about how to prepare for an exam.",
        "Repeated thinking that is not about worry, such as revisiting an argument because of anger.",
        "A negative prediction without evidence that the person is struggling to control the worry."
      ]
    },
    stress_overload: %{
      key: "stress-overload.v1",
      dom_id: "stress-overload-prompt-v1",
      prefix: "Which post shows a stronger sense of being ",
      highlight: "overwhelmed or out of control",
      suffix: "?",
      description:
        "Feeling overwhelmed by too much to handle or unable to control what is happening.",
      details:
        "Include expressions of feeling overwhelmed by multiple demands, problems, responsibilities, or pressures, especially when the person feels unable to keep up, manage the situation, change what is happening, or control their own response. The focus is on demands exceeding what the person feels able to handle or a situation feeling beyond their control.",
      include: [
        "I have so much going on that I don't know where to start.",
        "There is just too much to deal with.",
        "Work, family, bills, everything is piling up and I can't keep up.",
        "Everything is happening at once and I can't handle it.",
        "I have no control over what happens anymore.",
        "Everything is out of my hands.",
        "No matter what I do, I can't change anything.",
        "I can't control how I react when this happens.",
        "I cry over everything."
      ],
      exclude: [
        "Simply having many responsibilities.",
        "Being busy without feeling overwhelmed.",
        "One difficult task by itself.",
        "A stressful situation without evidence that it feels too much to handle.",
        "A situation being outside someone's control without personal distress.",
        "A minor inconvenience that the person cannot control.",
        "Hopelessness without feeling overwhelmed or lacking control."
      ]
    },
    social_disconnection: %{
      key: "social-disconnection.v1",
      dom_id: "social-disconnection-prompt-v1",
      prefix: "Which post shows more ",
      highlight: "social disconnection or loneliness",
      suffix: "?",
      description:
        "Feeling disconnected, alone, misunderstood, or lacking meaningful connection with others.",
      details:
        "Include feelings of loneliness, disconnection, exclusion, lack of belonging, or feeling that meaningful relationships or understanding are missing. Physical isolation alone is not sufficient.",
      include: [
        "I feel completely alone even when people are around.",
        "I have no one who really understands me.",
        "I feel like I don't fit in anywhere.",
        "I talk to people all the time but still feel completely alone.",
        "I wish I had someone I could actually talk to."
      ],
      exclude: [
        "Being physically alone without feeling disconnected.",
        "Choosing to spend time alone.",
        "A temporary lack of contact with others.",
        "A disagreement or conflict with someone without broader social disconnection."
      ]
    },
    guilt_worthlessness: %{
      key: "guilt-worthlessness.v1",
      dom_id: "guilt-worthlessness-prompt-v1",
      prefix: "Which post shows stronger feelings of ",
      highlight: "guilt or worthlessness",
      suffix: "?",
      description:
        "Feeling bad about yourself, blaming yourself, or feeling that you have little value.",
      details:
        "Include strong self-blame, excessive guilt, feeling like a burden, or feeling worthless, useless, or like a bad person. The focus should be on a negative judgment of oneself rather than simply regretting a specific action.",
      include: [
        "Everything is my fault.",
        "I feel like such a terrible person.",
        "I'm useless and have no value.",
        "Everyone would be better off without me.",
        "I can't forgive myself for what I did."
      ],
      exclude: [
        "Normal regret about a specific mistake.",
        "Taking responsibility for something without excessive self-blame.",
        "Criticism of another person.",
        "Saying something went badly without blaming or devaluing oneself."
      ]
    },
    fatigue: %{
      key: "fatigue.v1",
      dom_id: "fatigue-prompt-v1",
      prefix: "Which post shows more ",
      highlight: "unusual tiredness or lack of energy",
      suffix: "?",
      description: "Feeling unusually tired, drained, or lacking energy.",
      details:
        "Include expressions of persistent or unusual tiredness, exhaustion, low energy, or feeling physically or mentally drained. The fatigue should be presented as an experience of the person rather than simply describing a demanding activity.",
      include: [
        "I feel exhausted all the time.",
        "I have no energy to do anything.",
        "I'm completely drained.",
        "Even basic things feel exhausting."
      ],
      exclude: [
        "Being tired after normal physical activity.",
        "Saying that something is tiring without describing personal fatigue.",
        "Temporary tiredness after staying up late.",
        "Lack of motivation without evidence of tiredness or low energy."
      ]
    },
    sleep_disturbance: %{
      key: "sleep-disturbance.v1",
      dom_id: "sleep-disturbance-prompt-v1",
      prefix: "Which post shows more evidence of ",
      highlight: "disturbed or problematic sleep",
      suffix: "?",
      description:
        "Problems with sleeping, such as difficulty sleeping, sleeping too much, or poor sleep.",
      details:
        "Include difficulty falling asleep, waking repeatedly, waking too early, sleeping much more than usual, or feeling that sleep is poor or disrupted. The focus should be on a change or problem with the person's sleep.",
      include: [
        "I can't fall asleep at night.",
        "I keep waking up throughout the night.",
        "I've been sleeping 12 hours and still feel exhausted.",
        "My sleep has been terrible lately.",
        "I wake up at 4am and can't get back to sleep."
      ],
      exclude: [
        "Simply choosing to stay up late.",
        "A single late night without evidence of a sleep problem.",
        "Discussing someone else's sleep.",
        "Normal variation in sleeping patterns."
      ]
    },
    suicidal_ideation: %{
      key: "suicidal-ideation.v1",
      dom_id: "suicidal-ideation-prompt-v1",
      prefix: "Which post shows more evidence of ",
      highlight: "suicidal thoughts or not wanting to be alive",
      suffix: "?",
      description: "Thinking about dying, suicide, or not wanting to be alive.",
      details:
        "Include expressions of wanting to die, wishing to be dead, thinking about suicide, considering suicide, or feeling that others would be better off without the person. Direct statements are included, as well as clear indirect expressions of wanting life to end.",
      include: [
        "I don't want to be alive anymore.",
        "I've been thinking about killing myself.",
        "I wish I could just die.",
        "Everyone would be better off without me.",
        "I don't see a reason to keep living."
      ],
      exclude: [
        "General statements that life is difficult.",
        "Hopelessness without reference to death or not wanting to live.",
        "Discussing suicide as a general topic or news event.",
        "Discussing another person's suicidal thoughts.",
        "Figurative expressions that clearly do not refer to wanting to die."
      ]
    },
    loss_of_interest: %{
      key: "loss-of-interest.v1",
      dom_id: "loss-of-interest-prompt-v1",
      prefix: "Which post shows more ",
      highlight: "loss of interest or enjoyment",
      suffix: "?",
      description: "Losing interest or enjoyment in things that were previously enjoyable.",
      details:
        "Include expressions of losing interest in or enjoyment of activities, hobbies, people, or things the person previously enjoyed. This can include no longer wanting to participate in activities or feeling that things are no longer enjoyable.",
      include: [
        "I don't enjoy playing games anymore.",
        "I used to love going out, but now I don't want to do anything.",
        "Nothing feels fun anymore."
      ],
      exclude: [
        "Being tired or busy and therefore not doing something.",
        "Disliking an activity that the person never enjoyed.",
        "Temporary boredom.",
        "Choosing not to participate for practical reasons."
      ]
    },
    appetite_changes: %{
      key: "appetite-changes.v1",
      dom_id: "appetite-changes-prompt-v1",
      prefix: "Which post shows a greater ",
      highlight: "change in appetite or eating patterns",
      suffix: "?",
      description: "Eating much less or much more than usual.",
      details:
        "Include clear changes in the person's usual appetite or eating patterns, particularly when the change is linked to their emotional or psychological state. This can include losing interest in food, having little appetite, eating much more than usual, or using food in response to distress.",
      include: [
        "I have no appetite lately.",
        "I barely eat anymore.",
        "I've been eating constantly since I've been feeling stressed.",
        "I keep overeating when I'm upset.",
        "I don't feel like eating anything these days."
      ],
      exclude: [
        "Choosing not to eat for practical reasons.",
        "Missing a meal because the person is busy.",
        "Normal changes in appetite due to physical activity or hunger.",
        "Discussing someone else's eating habits.",
        "Mentioning a particular food or meal without a change in eating behavior."
      ]
    }
  }

  def definition!(name), do: Map.fetch!(@definitions, name)

  def question(definition, id \\ nil) do
    assigns = %{definition: definition, id: id || definition.dom_id}

    ~H"""
    <span
      id={@id}
      class="block text-lg font-bold leading-snug tracking-tight text-slate-950 dark:text-white sm:text-xl"
    >
      {@definition.prefix}<u class="decoration-indigo-500 decoration-2 underline-offset-4 dark:decoration-indigo-400">{@definition.highlight}</u>{@definition.suffix}
    </span>
    """
  end

  def instruction_page(definition) do
    assigns = %{definition: definition}

    ~H"""
    <div id={"instruction-#{@definition.dom_id}"} class="space-y-6">
      <header>
        <p class="text-xs font-bold uppercase tracking-[0.16em] text-indigo-600 dark:text-indigo-300">
          Question-specific guidance
        </p>
        <div class="mt-2">{question(@definition, "instruction-question-#{@definition.key}")}</div>
        <p class="mt-3 text-base font-medium leading-7 text-slate-600 dark:text-slate-300">
          {@definition.description}
        </p>
      </header>
      {guidance(@definition)}
    </div>
    """
  end

  def guidance(definition) do
    assigns = %{definition: definition, concepts: Map.get(definition, :concepts, [])}

    ~H"""
    <div class="space-y-6 text-sm leading-6 text-slate-600 dark:text-slate-300">
      <p>{@definition.details}</p>

      <section :if={@concepts != []} aria-label="Types of cognitive distortions">
        <h3 class="font-bold text-slate-950 dark:text-white">Common forms</h3>
        <div class="mt-3 space-y-3">
          <div
            :for={{title, explanation, example} <- @concepts}
            class="rounded-xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-700 dark:bg-slate-950/50"
          >
            <p><strong class="text-slate-900 dark:text-white">{title}:</strong> {explanation}</p>
            <p class="mt-1 italic text-slate-500 dark:text-slate-400">Example: “{example}”</p>
          </div>
        </div>
      </section>

      <div class="grid overflow-hidden rounded-2xl border border-slate-200 bg-white dark:border-slate-700 dark:bg-slate-950/40 md:grid-cols-2">
        <section class="border-b border-slate-200 p-4 dark:border-slate-700 md:border-b-0 md:border-r sm:p-5">
          <h3 class="font-bold text-emerald-700 dark:text-emerald-300">Include</h3>
          <ul class="mt-3 space-y-2.5">
            <li :for={item <- @definition.include} class="flex gap-2">
              <span class="font-bold text-emerald-600 dark:text-emerald-400">+</span>
              <span>{item}</span>
            </li>
          </ul>
        </section>
        <section class="p-4 sm:p-5">
          <h3 class="font-bold text-rose-700 dark:text-rose-300">Do not include</h3>
          <ul class="mt-3 space-y-2.5">
            <li :for={item <- @definition.exclude} class="flex gap-2">
              <span class="font-bold text-rose-600 dark:text-rose-400">−</span>
              <span>{item}</span>
            </li>
          </ul>
        </section>
      </div>
    </div>
    """
  end
end

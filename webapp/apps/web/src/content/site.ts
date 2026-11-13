export const apps = [
  "Mail",
  "Messages",
  "Slack",
  "Notion",
  "Linear",
  "Notes",
  "Figma",
  "Chrome",
] as const;

export const benefits = [
  {
    eyebrow: "Genuinely private",
    title: "Your words stay yours.",
    text: "Voice, transcripts, and models remain on your Mac. hush works the same with Wi-Fi switched off.",
    visual: "privacy",
    gridClassName: "lg:col-span-2",
    surfaceClassName: "bg-ink text-white",
  },
  {
    eyebrow: "Everywhere",
    title: "One shortcut for you.",
    text: "If there is a cursor, hush can type there. No copy and paste, browser extension, or context switching.",
    visual: "shortcut",
    gridClassName: "",
    surfaceClassName: "bg-white",
  },
  {
    eyebrow: "Work faster",
    title: "Save time.",
    text: "Speak naturally while hush turns each thought into polished text on your Mac.",
    visual: "typingSpeed",
    gridClassName: "",
    surfaceClassName: "bg-white",
  },
  {
    eyebrow: "Fast by design",
    title: "Thought to text in under a second.",
    text: "Apple silicon runs transcription and refinement locally, without waiting on a round-trip to a server.",
    visual: "speed",
    gridClassName: "lg:col-span-2",
    surfaceClassName: "bg-lilac",
  },
] as const;

export const faqs = [
  {
    question: "Does it really work offline?",
    answer:
      "Yes. WhisperKit transcription and Qwen 3 or Apple Intelligence refinement run on your Mac. Core dictation and refinement continue without Wi-Fi. Publishing an optional Verified Message requires a connection.",
  },
  {
    question: "Which Macs are supported?",
    answer:
      "Any Apple silicon Mac with an M1 chip or newer running macOS 14+. The Neural Engine does the heavy lifting, so even a base M1 Air transcribes faster than you can talk.",
  },
  {
    question: "Where does my audio go?",
    answer:
      "Nowhere. Audio is processed in memory on your chip and discarded. Transcripts stay local only if you enable history.",
  },
  {
    question: "How is this different from other dictation tools?",
    answer:
      "hush runs both transcription and refinement on-device. You get the same polished result without sending voice or text to a cloud service.",
  },
  {
    question: "Can it really write in my tone?",
    answer:
      "Yes. Give a writing style a few examples for each context and the local model shapes dictation to match your business email, casual chat, social post, or custom voice.",
  },
  {
    question: "What if I do not like it?",
    answer:
      "Remove hush and your local workflow is unchanged. The private alpha is free and requires no account.",
  },
] as const;

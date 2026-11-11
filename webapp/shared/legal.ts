export const legalConfig = {
  // Keep indexing disabled until the operational review in docs/legal-review.md is complete.
  isPlaceholder: true,
  operator: {
    name: "Clemens Kressmann",
    careOf: "c/o COCENTER",
    street: "Koppoldstr. 1",
    postalCode: "86551",
    city: "Aichach",
    country: {
      en: "Germany",
      de: "Deutschland",
    },
    email: "hello@behu.sh",
    vatId: {
      en: "DE455349278",
      de: "DE455349278",
    },
  },
  hosting: {
    provider: {
      en: "Hetzner Online GmbH",
      de: "Hetzner Online GmbH",
    },
    address: {
      en: "Industriestr. 25, 91710 Gunzenhausen, Germany",
      de: "Industriestr. 25, 91710 Gunzenhausen, Deutschland",
    },
    serverLocation: { en: "Germany", de: "Deutschland" },
    privacyURL: "https://www.hetzner.com/de/legal/privacy-policy/",
  },
  projectStatus: {
    en: "hush is free and open source. It is currently in alpha.",
    de: "hush ist kostenlos und Open Source. Die Software befindet sich derzeit in der Alpha-Phase.",
  },
} as const;

export const publicLegalPaths = legalConfig.isPlaceholder
  ? []
  : ["/impressum", "/datenschutz", "/de/impressum", "/de/datenschutz"];

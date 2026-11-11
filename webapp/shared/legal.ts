export const legalConfig = {
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
      en: "[Add hosting provider]",
      de: "[Hosting-Anbieter ergänzen]",
    },
    address: {
      en: "[Add address and server location]",
      de: "[Anschrift und Serverstandort ergänzen]",
    },
  },
  supervisoryAuthority: {
    en: "[Add the competent German data protection authority]",
    de: "[zuständige Landesdatenschutzbehörde ergänzen]",
  },
  projectStatus: {
    en: "hush is currently provided free of charge as an early test version. Future commercialization or funding through sponsorship is intended.",
    de: "hush wird derzeit unentgeltlich als frühe Testversion angeboten. Eine spätere Kommerzialisierung oder Finanzierung durch Sponsoring ist vorgesehen.",
  },
} as const;

export const publicLegalPaths = legalConfig.isPlaceholder
  ? []
  : ["/impressum", "/datenschutz", "/de/impressum", "/de/datenschutz"];

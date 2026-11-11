import type { ReactNode } from "react";
import { legalConfig } from "../../shared/legal";
import { DocumentMetadata } from "../components/DocumentMetadata";
import { Footer } from "../layout/Footer";
import { Header } from "../layout/Header";

type LegalLanguage = "en" | "de";
type LegalPageKind = "imprint" | "privacy";

const routes: Record<LegalLanguage, Record<LegalPageKind, string>> = {
  en: { imprint: "/impressum", privacy: "/datenschutz" },
  de: { imprint: "/de/impressum", privacy: "/de/datenschutz" },
};

const labels = {
  en: {
    navigation: "Legal navigation",
    home: "Home",
    updated: "Last updated",
  },
  de: {
    navigation: "Rechtliche Navigation",
    home: "Startseite",
    updated: "Stand",
  },
} as const;

function LanguageSwitch({
  language,
  page,
}: {
  language: LegalLanguage;
  page: LegalPageKind;
}) {
  return (
    <div
      className="flex rounded-full bg-black/5 p-1 text-xs font-semibold"
      role="group"
      aria-label={language === "en" ? "Language" : "Sprache"}
    >
      {(["en", "de"] as const).map((option) => (
        <a
          key={option}
          href={routes[option][page]}
          className={`inline-flex min-h-10 min-w-11 items-center justify-center rounded-full px-3 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink ${
            language === option
              ? "bg-white text-ink shadow-sm"
              : "text-muted hover:text-ink"
          }`}
          lang={option}
          hrefLang={option}
          aria-current={language === option ? "page" : undefined}
        >
          {option.toUpperCase()}
        </a>
      ))}
    </div>
  );
}

function LegalShell({
  language,
  page,
  title,
  description,
  updatedAt,
  children,
}: {
  language: LegalLanguage;
  page: LegalPageKind;
  title: string;
  description: string;
  updatedAt: string;
  children: ReactNode;
}) {
  const copy = labels[language];
  const canonicalPath = routes[language][page];

  return (
    <div className="min-h-screen bg-canvas text-ink">
      <DocumentMetadata
        title={`${title} - hush`}
        description={description}
        canonicalPath={canonicalPath}
        indexable={!legalConfig.isPlaceholder}
        language={language}
      />
      <Header />
      <main className="px-5 pb-28 pt-8 sm:pt-12">
        <article className="mx-auto max-w-3xl">
          <nav aria-label={copy.navigation} className="mb-9 flex items-center justify-between gap-4 border-b border-black/10 pb-5 sm:mb-11 sm:pb-6">
            <a
              className="inline-flex min-h-11 items-center gap-2 rounded text-sm font-medium text-muted transition-colors hover:text-ink focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-ink"
              href="/"
            >
              <svg className="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="m10 5-7 7 7 7M3 12h18" />
              </svg>
              {copy.home}
            </a>
            <LanguageSwitch language={language} page={page} />
          </nav>
          <header>
            <h1 className="break-words font-display text-5xl font-bold tracking-[-0.05em] [hyphens:auto] sm:text-6xl">
              {title}
            </h1>
            <p className="mt-5 text-sm text-muted">
              {copy.updated}: {updatedAt}
            </p>
          </header>
          <div className="legal-copy mt-12 space-y-12 text-[17px] leading-8 text-muted sm:mt-14">
            {children}
          </div>
        </article>
      </main>
      <Footer />
    </div>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section>
      <h2 className="font-display text-2xl font-bold tracking-[-0.03em] text-ink">
        {title}
      </h2>
      <div className="mt-4 space-y-4">{children}</div>
    </section>
  );
}

function Address({ language }: { language: LegalLanguage }) {
  const { operator } = legalConfig;
  return (
    <address className="not-italic">
      {operator.name}
      <br />
      {operator.careOf}
      <br />
      {operator.street}
      <br />
      {operator.postalCode} {operator.city}
      <br />
      {operator.country[language]}
    </address>
  );
}

function Contact({ language }: { language: LegalLanguage }) {
  const { operator } = legalConfig;
  return (
    <>
      <Address language={language} />
      <p>
        {language === "en" ? "Email" : "E-Mail"}: {" "}
        <a
          className="font-semibold text-ink underline underline-offset-4"
          href={`mailto:${operator.email}`}
        >
          {operator.email}
        </a>
      </p>
    </>
  );
}

export function ImprintPage({ language = "en" }: { language?: LegalLanguage }) {
  const { operator } = legalConfig;
  const english = language === "en";

  return (
    <LegalShell
      language={language}
      page="imprint"
      title={english ? "Legal notice" : "Impressum"}
      description={
        english
          ? "Provider identification and contact information for hush."
          : "Anbieterkennzeichnung und Kontakt für hush."
      }
      updatedAt={english ? "8 August 2026" : "8. August 2026"}
    >
      <Section title={english ? "Information under Section 5 DDG" : "Angaben gemäß § 5 DDG"}>
        <Address language={language} />
      </Section>

      <Section title={english ? "Contact" : "Kontakt"}>
        <p>
          {english ? "Email" : "E-Mail"}: {" "}
          <a
            className="font-semibold text-ink underline underline-offset-4"
            href={`mailto:${operator.email}`}
          >
            {operator.email}
          </a>
        </p>
      </Section>

      <Section title={english ? "VAT" : "Umsatzsteuer"}>
        <p>{operator.vatId[language]}</p>
        <p>
          {english
            ? "A German tax number does not belong in a public legal notice. A VAT identification number is listed here only if one has actually been issued."
            : "Eine Steuernummer gehört nicht in das öffentliche Impressum. Eine USt-IdNr. wird hier nur angegeben, wenn sie tatsächlich vergeben wurde."}
        </p>
      </Section>

      <Section title={english ? "Project status" : "Projektstatus"}>
        <p>{legalConfig.projectStatus[language]}</p>
        <p>
          {english
            ? "Support from sponsors does not change hush's privacy promises. Sponsors receive no access to messages, audio, proof contents or usage profiles unless a separate arrangement is disclosed transparently."
            : "Eine Unterstützung durch Sponsoren ändert nichts an den Datenschutzversprechen von hush. Ohne eine gesonderte, transparente Vereinbarung erhalten Sponsoren keinen Zugriff auf Nachrichten, Audiodaten, Proof-Inhalte oder Nutzungsprofile."}
        </p>
      </Section>

      <Section title={english ? "Consumer dispute resolution" : "Verbraucherstreitbeilegung"}>
        <p>
          {english
            ? "The provider is neither obliged nor currently willing to participate in dispute resolution proceedings before a consumer arbitration board."
            : "Der Anbieter ist nicht verpflichtet und derzeit nicht bereit, an Streitbeilegungsverfahren vor einer Verbraucherschlichtungsstelle teilzunehmen."}
        </p>
      </Section>

      <Section title={english ? "Liability for links" : "Haftung für Links"}>
        <p>
          {english
            ? "The operators of external pages linked by hush are solely responsible for their contents. Linked content is checked for recognizable legal violations when the link is created."
            : "Für Inhalte externer Seiten, auf die hush verlinkt, sind ausschließlich deren Betreiber verantwortlich. Verlinkte Inhalte werden zum Zeitpunkt der Verlinkung auf erkennbare Rechtsverstöße geprüft."}
        </p>
      </Section>
    </LegalShell>
  );
}

export function PrivacyPolicyPage({
  language = "en",
}: {
  language?: LegalLanguage;
}) {
  const { operator } = legalConfig;
  const english = language === "en";

  return (
    <LegalShell
      language={language}
      page="privacy"
      title={english ? "Privacy policy" : "Datenschutzerklärung"}
      description={
        english
          ? "How hush handles data on the website, during downloads and for optional Verified Messages."
          : "Wie hush auf der Website, beim Download und bei optionalen Verified Messages mit Daten umgeht."
      }
      updatedAt={english ? "8 August 2026" : "8. August 2026"}
    >
      <Section title={english ? "1. Controller" : "1. Verantwortlicher"}>
        <Contact language={language} />
      </Section>

      <Section title={english ? "2. Principle: local processing" : "2. Grundsatz: lokale Verarbeitung"}>
        <p>
          {english
            ? "The core Mac app processes speech, transcripts, personal vocabulary and local AI refinements on the Mac. Using dictation or writing features alone does not transmit these contents to hush."
            : "Die Kernfunktionen der Mac-App verarbeiten Sprache, Transkripte, persönliche Wörterbücher und lokale KI-Verfeinerungen grundsätzlich auf dem Mac. Diese Inhalte werden nicht allein durch die Nutzung der Diktier- oder Schreibfunktionen an hush übertragen."}
        </p>
        <p>
          {english
            ? "Data is transmitted to the hush service only for features that explicitly require a network connection, particularly downloads, update checks and optional published Verified Messages."
            : "Eine Übertragung an den hush-Dienst erfolgt nur für Funktionen, die eine Netzwerkverbindung ausdrücklich benötigen, insbesondere Downloads, Update-Prüfungen und optional veröffentlichte Verified Messages."}
        </p>
      </Section>

      <Section title={english ? "3. Website access and technical logs" : "3. Aufruf der Website und technische Protokolle"}>
        <p>
          {english
            ? "Accessing the website requires processing technical connection data. This can include the IP address, time, requested URL, referrer, browser and operating system information, and HTTP status. hush uses the IP address briefly in memory for abuse prevention. The application itself does not create a persistent user profile from it. Infrastructure providers may keep security and access logs."
            : "Beim Aufruf der Website werden technisch erforderliche Verbindungsdaten verarbeitet. Dazu können IP-Adresse, Zeitpunkt, angeforderte URL, Referrer, Browser- und Betriebssystemangaben sowie HTTP-Status gehören. hush nutzt die IP-Adresse kurzfristig im Arbeitsspeicher zur Missbrauchsbegrenzung. Die Anwendung selbst legt daraus kein dauerhaftes Nutzerprofil an. Infrastruktur-Anbieter können Sicherheits- und Zugriffsprotokolle führen."}
        </p>
        <p>
          {english
            ? "The purpose is to provide the website and API securely, reliably and with resistance to abuse. The legal basis is Article 6(1)(f) GDPR. The legitimate interest is operational security, error diagnosis and protection against automated attacks."
            : "Zweck ist die sichere, stabile und missbrauchsarme Bereitstellung der Website und API. Rechtsgrundlage ist Art. 6 Abs. 1 lit. f DSGVO. Das berechtigte Interesse liegt in Betriebssicherheit, Fehlerdiagnose und Abwehr automatisierter Angriffe."}
        </p>
        <p>
          {english
            ? "Technical hosting providers process connection data on the operator's instructions. Security logs are retained only for as long as required for reliable operation, incident analysis and legal obligations."
            : "Technische Hosting-Anbieter verarbeiten Verbindungsdaten im Auftrag des Betreibers. Sicherheitsprotokolle werden nur so lange aufbewahrt, wie es für den zuverlässigen Betrieb, die Analyse von Vorfällen und gesetzliche Pflichten erforderlich ist."}
        </p>
      </Section>

      <Section title={english ? "4. Cloudflare and app downloads" : "4. Cloudflare und App-Downloads"}>
        <p>
          {english
            ? "Cloudflare provides DNS, protection and delivery functions, as well as downloads of installation files. Versioned DMG files are stored in Cloudflare R2 and delivered through updates.behu.sh. Cloudflare processes connection and device information required for transmission, protection and caching."
            : "Für DNS, Schutz- und Auslieferungsfunktionen sowie den Download von Installationsdateien wird Cloudflare eingesetzt. Versionsgebundene DMG-Dateien liegen in Cloudflare R2 und werden über updates.behu.sh ausgeliefert. Dabei verarbeitet Cloudflare insbesondere Verbindungs- und Geräteinformationen, die für Übertragung, Schutz und Zwischenspeicherung erforderlich sind."}
        </p>
        <p>
          {english
            ? "The legal basis is Article 6(1)(f) GDPR. The legitimate interest is secure, fast and reliable delivery. If data is processed outside the EEA, the safeguards actually applying under the Cloudflare agreement, such as an adequacy decision or standard contractual clauses, must be documented before publication."
            : "Rechtsgrundlage ist Art. 6 Abs. 1 lit. f DSGVO. Das berechtigte Interesse liegt in sicherer, schneller und belastbarer Auslieferung. Soweit Daten außerhalb des EWR verarbeitet werden, sind vor Veröffentlichung die tatsächlich geltenden Garantien des Cloudflare-Vertrags, etwa ein Angemessenheitsbeschluss oder Standardvertragsklauseln, zu dokumentieren."}
        </p>
      </Section>

      <Section title="5. Verified Messages">
        <p>
          {english
            ? "Verified Messages are optional. When one is published, the service processes an installation key with its fingerprint and type, app and platform versions, and timestamps. The proof stores technical metadata, cryptographic bindings, encrypted content, size, status and expiry time."
            : "Verified Messages sind optional. Bei ihrer Veröffentlichung verarbeitet der Dienst einen Installationsschlüssel mit Fingerabdruck, Schlüsselart, App- und Plattformversion sowie Zeitstempeln. Für den Proof werden technische Metadaten, kryptografische Bindungen, verschlüsselter Inhalt, Größe, Status und Ablaufzeit gespeichert."}
        </p>
        <p>
          {english
            ? "The message content is encrypted on the Mac before transmission. The decryption key remains in the private fragment of the shared link and is not sent to the hush service. Original audio is not uploaded as part of the public proof content. Anyone with the complete link can decrypt the encrypted content in their browser until it expires or is revoked."
            : "Der Nachrichteninhalt wird vor der Übertragung auf dem Mac verschlüsselt. Der Entschlüsselungsschlüssel steht im privaten Fragment des geteilten Links und wird nicht an den hush-Dienst gesendet. Originalaudio wird nicht als Teil des öffentlichen Proof-Inhalts hochgeladen. Wer den vollständigen Link besitzt, kann den verschlüsselten Inhalt bis zum Ablauf oder Widerruf im eigenen Browser entschlüsseln."}
        </p>
        <p>
          {english
            ? "The purpose is the explicitly requested publication and technical verification of a proof. The legal basis is Article 6(1)(b) GDPR for the requested feature and Article 6(1)(f) GDPR for integrity, abuse prevention and error diagnosis."
            : "Zweck ist die ausdrücklich angeforderte Veröffentlichung und technische Verifikation eines Proofs. Rechtsgrundlage ist Art. 6 Abs. 1 lit. b DSGVO für die vom Nutzer angeforderte Funktion sowie Art. 6 Abs. 1 lit. f DSGVO für Integrität, Missbrauchsschutz und Fehlerdiagnose."}
        </p>
        <p>
          {english
            ? "Users choose an expiry between one minute and 90 days. After expiry or revocation, the service no longer returns the encrypted content. In the current alpha, expiry alone does not automatically delete proof records and encrypted objects physically. An automated deletion routine must be added before a public product launch, and this policy must then be updated."
            : "Nutzer wählen eine Ablaufzeit von mindestens einer Minute und höchstens 90 Tagen. Nach Ablauf oder Widerruf liefert der Dienst den verschlüsselten Inhalt nicht mehr aus. In der aktuellen Alpha werden Proof-Datensätze und verschlüsselte Objekte nicht allein durch den Ablauf automatisch physisch gelöscht. Eine automatisierte Löschroutine muss vor einem öffentlichen Produktstart ergänzt und diese Erklärung danach aktualisiert werden."}
        </p>
      </Section>

      <Section title={english ? "6. Update checks" : "6. Update-Prüfungen"}>
        <p>
          {english
            ? "The app can use Sparkle to check for new versions. Update files and the signed update feed are delivered through updates.behu.sh. This produces the connection data described in sections 3 and 4. Message text and audio are not transmitted."
            : "Die App kann über Sparkle prüfen, ob eine neue Version verfügbar ist. Die Update-Dateien und das signierte Update-Feed werden über updates.behu.sh ausgeliefert. Hierbei fallen die unter Ziffer 3 und 4 beschriebenen Verbindungsdaten an. Es werden keine Nachrichtentexte oder Audiodaten übertragen."}
        </p>
      </Section>

      <Section title={english ? "7. Contact by email" : "7. Kontakt per E-Mail"}>
        <p>
          {english
            ? "When you contact us by email, the sender address, content, technical metadata and any other voluntarily provided information are processed to handle the request. Depending on the request, the legal basis is Article 6(1)(b) or (f) GDPR. Messages are deleted when they are no longer required for handling the request or statutory evidence."
            : "Bei einer Kontaktaufnahme per E-Mail werden Absenderadresse, Inhalt, technische Metadaten und weitere freiwillig übermittelte Angaben zur Bearbeitung der Anfrage verarbeitet. Rechtsgrundlage ist je nach Anlass Art. 6 Abs. 1 lit. b oder lit. f DSGVO. Nachrichten werden gelöscht, wenn sie für die Bearbeitung und gesetzliche Nachweise nicht mehr erforderlich sind."}
        </p>
      </Section>

      <Section title={english ? "8. Cookies, local storage and analytics" : "8. Cookies, lokale Speicherung und Analyse"}>
        <p>
          {english
            ? "The public website currently uses no advertising or audience analytics and sets no non-essential cookies. Any future analytics, marketing or sponsorship technology will be introduced only after legal and technical review and, where required, valid consent."
            : "Die öffentliche Website verwendet derzeit keine Werbe- oder Reichweitenanalyse und setzt keine nicht erforderlichen Cookies. Falls später zusätzliche Analyse-, Marketing- oder Sponsoring-Technik hinzukommt, wird sie erst nach rechtlicher und technischer Prüfung sowie, soweit erforderlich, nach wirksamer Einwilligung eingesetzt."}
        </p>
      </Section>

      <Section title={english ? "9. Recipients and processors" : "9. Empfänger und Auftragsverarbeiter"}>
        <p>
          {english
            ? "Only parties required to operate and provide the service receive data. These include the hosting provider named above and Cloudflare. Data is not disclosed to sponsors for advertising, analytics or profiling."
            : "Daten erhalten nur Stellen, die für Betrieb und Bereitstellung erforderlich sind. Dazu gehören der oben genannte Hosting-Anbieter und Cloudflare. Eine Weitergabe an Sponsoren zu Werbe-, Analyse- oder Profilbildungszwecken findet nicht statt."}
        </p>
      </Section>

      <Section title={english ? "10. Data subject rights" : "10. Rechte betroffener Personen"}>
        <p>
          {english
            ? `Under the GDPR, data subjects may have rights to access, rectification, erasure, restriction, portability and objection. Consent can be withdrawn for the future. Requests can be sent to ${operator.email}.`
            : `Betroffene Personen haben nach Maßgabe der DSGVO Rechte auf Auskunft, Berichtigung, Löschung, Einschränkung, Datenübertragbarkeit und Widerspruch. Erteilte Einwilligungen können mit Wirkung für die Zukunft widerrufen werden. Anfragen können an ${operator.email} gerichtet werden.`}
        </p>
        <p>
          {english
            ? "A complaint may also be lodged with a data protection supervisory authority, particularly in the EU member state of the person's residence, workplace or the alleged infringement."
            : "Außerdem besteht ein Beschwerderecht bei einer Datenschutzaufsichtsbehörde, insbesondere im EU-Mitgliedstaat des Aufenthaltsorts, des Arbeitsplatzes oder des Orts des mutmaßlichen Verstoßes."}
        </p>
      </Section>

      <Section title={english ? "11. Changes to this policy" : "11. Änderungen dieser Erklärung"}>
        <p>
          {english
            ? "This policy will be updated if features, providers, retention periods, legal bases or future funding change. The version published on this page applies."
            : "Diese Erklärung wird angepasst, wenn sich Funktionen, Dienstleister, Speicherdauern, Rechtsgrundlagen oder eine spätere Finanzierung ändern. Maßgeblich ist die auf dieser Seite veröffentlichte Fassung."}
        </p>
      </Section>
    </LegalShell>
  );
}

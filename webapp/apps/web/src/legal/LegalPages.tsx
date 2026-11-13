import type { ReactNode } from "react";
import { legalConfig } from "../../shared/legal";
import { DocumentMetadata } from "../components/DocumentMetadata";
import { Footer } from "../layout/Footer";
import { Header } from "../layout/Header";
import { BlogArrow } from "../blog/BlogArticlePage";
import "../blog/blog.css";

type LegalLanguage = "en" | "de";
type LegalPageKind = "imprint" | "privacy";

const routes: Record<LegalLanguage, Record<LegalPageKind, string>> = {
  en: { imprint: "/impressum", privacy: "/datenschutz" },
  de: { imprint: "/de/impressum", privacy: "/de/datenschutz" },
};

const labels = {
  en: {
    home: "Home",
    updated: "Last updated",
  },
  de: {
    home: "Startseite",
    updated: "Stand",
  },
} as const;

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
      <main className="blog-article-main">
        {/* Same layout as a blog article: the way home sits in the left margin. The
            footer switcher changes the language. */}
        <article className="blog-article" aria-labelledby="legal-title">
          <a className="blog-back" href={language === "de" ? "/de" : "/"}><BlogArrow direction="back" />{copy.home}</a>
          <header className="blog-article-header">
            <h1 id="legal-title" className="break-words font-display text-5xl font-bold tracking-[-0.05em] [hyphens:auto] sm:text-6xl">
              {title}
            </h1>
            <p className="mt-5 text-sm text-muted">
              {copy.updated}: {updatedAt}
            </p>
          </header>
          <div className="blog-body legal-copy space-y-12 text-[17px] leading-8 text-muted">
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
      updatedAt={english ? "11 November 2026" : "11. November 2026"}
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
        <p>
          {english
            ? "VAT identification number under Section 27a of the German VAT Act: "
            : "Umsatzsteuer-Identifikationsnummer gemäß § 27a UStG: "}
          <span>{operator.vatId[language]}</span>
        </p>
      </Section>

      <Section title={english ? "Project status" : "Projektstatus"}>
        <p>{legalConfig.projectStatus[language]}</p>
        <p>
          {english
            ? "Sponsorship does not give sponsors access to messages, audio, proof contents or usage profiles."
            : "Sponsoring gewährt Sponsoren keinen Zugriff auf Nachrichten, Audiodaten, Proof-Inhalte oder Nutzungsprofile."}
        </p>
      </Section>

      <Section title={english ? "Consumer dispute resolution" : "Verbraucherstreitbeilegung"}>
        <p>
          {english
            ? "The provider is neither obliged nor currently willing to participate in dispute resolution proceedings before a consumer arbitration board."
            : "Der Anbieter ist nicht verpflichtet und derzeit nicht bereit, an Streitbeilegungsverfahren vor einer Verbraucherschlichtungsstelle teilzunehmen."}
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
      updatedAt={english ? "13 November 2026" : "13. November 2026"}
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
          {english ? "Our servers are hosted by " : "Unsere Server werden bei "}
          {legalConfig.hosting.provider[language]}, {legalConfig.hosting.address[language]}.
          {english ? " Server location: " : " Serverstandort: "}
          {legalConfig.hosting.serverLocation[language]}.
          {english
            ? " The website, proof service, database and encrypted proof storage run on this infrastructure. Cloudflare also handles the connections described below; hosting in Germany does not mean all network processing is limited to Germany."
            : " Website, Proof-Dienst, Datenbank und verschlüsselter Proof-Speicher laufen auf dieser Infrastruktur. Cloudflare verarbeitet zusätzlich die unten beschriebenen Verbindungen; Hosting in Deutschland bedeutet nicht, dass sämtliche Netzwerkverarbeitung auf Deutschland beschränkt ist."}
        </p>
        <p>
          <a className="text-ink underline underline-offset-4" href={legalConfig.hosting.privacyURL}>
            {english ? "Hetzner privacy information" : "Datenschutzhinweise von Hetzner"}
          </a>
        </p>
        <p>
          {english
            ? "Accessing the website requires technical connection data, including the IP address, time, requested URL, referrer, browser and operating system information, and HTTP status. For abuse prevention, the API keeps IP-based request counters in server memory. Entries expire within two minutes for the current one-minute rate-limit windows, even when traffic stops. Each limiter holds at most 10,000 entries. The application does not create a persistent user profile from these counters. Infrastructure providers may also keep security and access logs."
            : "Beim Aufruf der Website fallen technische Verbindungsdaten an, darunter IP-Adresse, Zeitpunkt, angeforderte URL, Referrer, Browser- und Betriebssystemangaben sowie HTTP-Status. Zum Missbrauchsschutz hält die API IP-bezogene Anfragezähler im Server-Arbeitsspeicher. Einträge werden bei den derzeitigen einminütigen Zeitfenstern innerhalb von zwei Minuten entfernt, auch ohne weitere Anfragen. Jeder Limiter hält höchstens 10.000 Einträge. Die Anwendung erstellt daraus kein dauerhaftes Nutzerprofil. Infrastruktur-Anbieter können zusätzlich Sicherheits- und Zugriffsprotokolle führen."}
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
        <p>Cloudflare, Inc., 101 Townsend Street, San Francisco, CA 94107, USA.</p>
        <p>
          {english
            ? "Cloudflare provides DNS, protection and delivery functions, as well as downloads of installation files. Versioned DMG files are stored in Cloudflare R2 and delivered through updates.behu.sh. Encrypted daily backups of the proof database are kept in a separate, non-public R2 bucket (see Verified Messages). Cloudflare processes connection and device information required for transmission, protection and caching."
            : "Für DNS, Schutz- und Auslieferungsfunktionen sowie den Download von Installationsdateien wird Cloudflare eingesetzt. Versionsgebundene DMG-Dateien liegen in Cloudflare R2 und werden über updates.behu.sh ausgeliefert. Verschlüsselte tägliche Sicherungen der Proof-Datenbank liegen in einem separaten, nicht öffentlichen R2-Bucket (siehe Verified Messages). Dabei verarbeitet Cloudflare insbesondere Verbindungs- und Geräteinformationen, die für Übertragung, Schutz und Zwischenspeicherung erforderlich sind."}
        </p>
        <p>
          {english
            ? "The legal basis is Article 6(1)(f) GDPR: secure and reliable delivery. Processing can also take place outside the EEA, including in the USA. Cloudflare's published data processing terms provide for the EU-US Data Privacy Framework and standard contractual clauses for restricted transfers. You can read these safeguards in the linked terms."
            : "Rechtsgrundlage ist Art. 6 Abs. 1 lit. f DSGVO: sichere und zuverlässige Auslieferung. Die Verarbeitung kann auch außerhalb des EWR, insbesondere in den USA, stattfinden. Die veröffentlichten Auftragsverarbeitungsbedingungen von Cloudflare sehen das EU-US Data Privacy Framework und Standardvertragsklauseln für beschränkte Übermittlungen vor. Diese Garantien sind in den verlinkten Bedingungen beschrieben."}
        </p>
        <p><a className="text-ink underline underline-offset-4" href="https://www.cloudflare.com/cloudflare-customer-dpa/">{english ? "Cloudflare data processing terms" : "Auftragsverarbeitungsbedingungen von Cloudflare"}</a></p>
      </Section>

      <Section title="5. Verified Messages">
        <p>
          {english
            ? "Verified Messages are optional. When one is published, the service processes the installation's public signing key, its fingerprint and type, app and platform versions, and timestamps. The private signing key stays on the Mac. The proof stores technical metadata, cryptographic bindings, encrypted content, size, status and expiry time."
            : "Verified Messages sind optional. Bei ihrer Veröffentlichung verarbeitet der Dienst den öffentlichen Signaturschlüssel der Installation, seinen Fingerabdruck und Typ, App- und Plattformversion sowie Zeitstempel. Der private Signaturschlüssel bleibt auf dem Mac. Für den Proof werden technische Metadaten, kryptografische Bindungen, verschlüsselter Inhalt, Größe, Status und Ablaufzeit gespeichert."}
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
            ? `Users choose an expiry between one minute and 90 days. After expiry or revocation, the service no longer returns the encrypted content. Encrypted objects, proof metadata and short aliases become eligible for automatic deletion 24 hours after expiry or revocation. Uncompleted reservations become eligible 24 hours after creation. Cleanup runs every minute in bounded batches and retries failures; outages or a backlog can delay removal. Expired one-time challenges are also deleted. The public installation key remains registered so the Mac can publish again. To request deletion, contact ${operator.email}. Deletion from live storage does not immediately remove backups. A daily backup of the proof database (installation keys, proof metadata and aliases, never message content or decryption keys) is stored encrypted at rest with Cloudflare R2, separate from the server, and deleted automatically after at most 9 days. Other recovery copies, for example from a server migration or kept because of an incident or a legal preservation requirement, have no fixed erasure deadline in the current alpha. Expiry or deletion cannot remove copies that recipients have already saved. Do not send your complete private link or decryption key in a support request.`
            : `Nutzer wählen eine Ablaufzeit von mindestens einer Minute und höchstens 90 Tagen. Nach Ablauf oder Widerruf liefert der Dienst den verschlüsselten Inhalt nicht mehr aus. Verschlüsselte Objekte, Proof-Metadaten und Kurzlinks werden 24 Stunden nach Ablauf oder Widerruf zur automatischen Löschung vorgesehen. Nicht abgeschlossene Reservierungen werden 24 Stunden nach Erstellung zur Löschung vorgesehen. Die Bereinigung läuft minütlich in begrenzten Stapeln und wiederholt fehlgeschlagene Löschungen; Störungen oder Rückstände können die Entfernung verzögern. Abgelaufene Einmal-Challenges werden ebenfalls gelöscht. Der öffentliche Installationsschlüssel bleibt registriert, damit der Mac erneut veröffentlichen kann. Für eine Löschanfrage wende dich an ${operator.email}. Die Löschung im laufenden Speicher entfernt Sicherungen nicht sofort. Eine tägliche Sicherung der Proof-Datenbank (Installationsschlüssel, Proof-Metadaten und Kurzlinks, nie Nachrichteninhalte oder Entschlüsselungsschlüssel) wird bei Cloudflare R2 getrennt vom Server und im Ruhezustand verschlüsselt gespeichert und nach höchstens 9 Tagen automatisch gelöscht. Andere Wiederherstellungskopien, etwa aus einer Servermigration oder wegen eines Vorfalls oder einer gesetzlichen Aufbewahrungspflicht, haben in der aktuellen Alpha keine feste Löschfrist. Ablauf oder Löschung entfernen keine bereits von Empfängern gespeicherten Kopien. Sende bei einer Support-Anfrage weder den vollständigen privaten Link noch den Entschlüsselungsschlüssel.`}
        </p>
      </Section>

      <Section title={english ? "6. Update checks" : "6. Update-Prüfungen"}>
        <p>
          {english
            ? "The app can use Sparkle to check for new versions. Update files and the signed update feed are delivered through updates.behu.sh. This produces the connection data described in sections 3 and 4. Message text and audio are not transmitted."
            : "Die App kann über Sparkle prüfen, ob eine neue Version verfügbar ist. Die Update-Dateien und das signierte Update-Feed werden über updates.behu.sh ausgeliefert. Hierbei fallen die unter Ziffer 3 und 4 beschriebenen Verbindungsdaten an. Es werden keine Nachrichtentexte oder Audiodaten übertragen."}
        </p>
        <p>
          {english
            ? "Optional speech and AI models are downloaded from their distribution services, including Hugging Face. Those services receive the requested model URL and technical connection data such as your IP address. The model download itself does not upload your audio or messages. Opening a website through the assistant also connects to that website, whose privacy policy applies."
            : "Optionale Sprach- und KI-Modelle werden von ihren Distributionsdiensten heruntergeladen, darunter Hugging Face. Diese Dienste erhalten die angeforderte Modell-URL und technische Verbindungsdaten wie deine IP-Adresse. Der Modell-Download selbst lädt keine Audiodaten oder Nachrichten hoch. Öffnet der Assistent eine Website, entsteht außerdem eine Verbindung zu dieser Website; dort gelten deren Datenschutzhinweise."}
        </p>
        <p><a className="text-ink underline underline-offset-4" href="https://huggingface.co/privacy">{english ? "Hugging Face privacy information" : "Datenschutzhinweise von Hugging Face"}</a></p>
      </Section>

      <Section title={english ? "7. Contact by email" : "7. Kontakt per E-Mail"}>
        <p>
          {english
            ? "Email for hello@behu.sh is handled by Apple's iCloud Mail. Cloudflare manages the domain's DNS records; it is not the mailbox provider. Apple Mail is the app used to access the mailbox. Apple processes the email content and associated transmission data to deliver and store correspondence. Processing may also take place outside the EEA, including in the USA; Apple's privacy information explains the applicable entities and transfer safeguards."
            : "E-Mails an hello@behu.sh werden über Apples iCloud Mail verarbeitet. Cloudflare verwaltet die DNS-Einträge der Domain und ist nicht der Postfachanbieter. Apple Mail ist die Anwendung für den Zugriff auf das Postfach. Apple verarbeitet E-Mail-Inhalte und zugehörige Übermittlungsdaten, um die Korrespondenz zuzustellen und zu speichern. Die Verarbeitung kann auch außerhalb des EWR, insbesondere in den USA, erfolgen; Apples Datenschutzhinweise erläutern die zuständigen Gesellschaften und Übermittlungsgarantien."}
        </p>
        <p><a className="text-ink underline underline-offset-4" href="https://www.apple.com/legal/privacy/">{english ? "Apple privacy information" : "Datenschutzhinweise von Apple"}</a></p>
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
            ? "Only parties required to operate and provide the service receive data. These include the hosting provider named above, Cloudflare for delivery, and Apple for email correspondence. Data is not disclosed to sponsors for advertising, analytics or profiling."
            : "Daten erhalten nur Stellen, die für Betrieb und Bereitstellung erforderlich sind. Dazu gehören der oben genannte Hosting-Anbieter, Cloudflare für die Auslieferung und Apple für E-Mail-Korrespondenz. Eine Weitergabe an Sponsoren zu Werbe-, Analyse- oder Profilbildungszwecken findet nicht statt."}
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
            ? "Where processing is based on legitimate interests, you can object on grounds relating to your particular situation (Article 21 GDPR). hush does not use these data for automated decisions with legal or similarly significant effects under Article 22 GDPR."
            : "Beruht eine Verarbeitung auf berechtigten Interessen, kannst du aus Gründen deiner besonderen Situation widersprechen (Art. 21 DSGVO). hush verwendet diese Daten nicht für automatisierte Entscheidungen mit rechtlicher oder ähnlich erheblicher Wirkung nach Art. 22 DSGVO."}
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

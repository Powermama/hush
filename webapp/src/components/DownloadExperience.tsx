import {
  type ComponentProps,
  type MouseEventHandler,
  type ReactNode,
  useRef,
  useState,
} from "react";
import { siApple } from "simple-icons";
import {
  latestRelease,
  releasePath,
} from "../../shared/releases";
import { ButtonLink, buttonClassName } from "./ButtonLink";
import { DownloadHandoff } from "./DownloadHandoff";

type DownloadLinkProps = Omit<
  ComponentProps<typeof ButtonLink>,
  "href" | "onClick"
> & { mobileLabel?: ReactNode };

export function DownloadLink({ mobileLabel = "Get hush for Mac", ...props }: DownloadLinkProps) {
  const [mobile] = useState(() => typeof navigator !== "undefined" && (
    /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
  ));
  const [handoffOpen, setHandoffOpen] = useState(false);
  const trigger = useRef<HTMLButtonElement>(null);
  const release = latestRelease;
  if (!release) {
    return (
      <ButtonLink {...props} href="/releases">
        Download coming soon
      </ButtonLink>
    );
  }

  if (mobile) return <>
    <button ref={trigger} type="button" className={buttonClassName(props.variant, `${props.className ?? ""} download-mobile`)} aria-haspopup="dialog" onClick={() => setHandoffOpen(true)}><svg className="download-apple" viewBox="0 0 24 24" aria-hidden="true"><path d={siApple.path} fill="currentColor" /></svg>{mobileLabel}</button>
    {handoffOpen && <DownloadHandoff onClose={() => { setHandoffOpen(false); trigger.current?.focus({ preventScroll: true }); }} />}
  </>;

  const startDownload: MouseEventHandler<HTMLAnchorElement> = (event) => {
    if (
      event.button !== 0 ||
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey
    ) {
      return;
    }

    window.open(releasePath(release), "_blank", "noopener,noreferrer");
  };

  return (
    <ButtonLink
      {...props}
      href={release.downloadURL}
      download={release.downloadName}
      onClick={startDownload}
    />
  );
}

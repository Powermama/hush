import { appIcons } from "../media/appIcons";
import { siLinear } from "simple-icons";
import { apps } from "../content/site";

type AppName = (typeof apps)[number];



function AppMark({ app }: { app: AppName }) {
  const iconPath = appIcons[app];
  if (iconPath) {
    return (
      <img
        src={iconPath}
        alt=""
        width="36"
        height="36"
        className="size-9 shrink-0"
        decoding="async"
      />
    );
  }

  return (
    <span className="grid size-9 shrink-0 place-items-center rounded-[10px] bg-[#202124] text-white shadow-sm">
      <svg viewBox="0 0 24 24" className="size-5" aria-hidden="true">
        <path d={siLinear.path} fill="currentColor" />
      </svg>
    </span>
  );
}

export function AppStrip() {
  return (
    <section
      className="border-y border-black/6 bg-white py-6"
      aria-label="Supported apps"
    >
      <p className="mb-5 text-center text-xs font-semibold uppercase tracking-[0.16em] text-soft">
        Works everywhere your cursor is
      </p>
      <div className="marquee mx-auto max-w-6xl">
        <div className="marquee-track">
          {[...apps, ...apps].map((app, index) => (
            <span
              className="flex items-center gap-3 whitespace-nowrap text-sm font-semibold text-muted"
              key={`${app}-${index}`}
            >
              <AppMark app={app} />
              {app}
              <span className="ml-2 size-1 rounded-full bg-black/15" />
            </span>
          ))}
        </div>
      </div>
    </section>
  );
}

// Inline SVG icons as typed components, all monochrome via currentColor so
// they inherit the surrounding text color. (The vanilla renderer kept these
// as innerHTML strings; JSX makes them plain markup.)

import type { ReactNode } from "react";
import type { ItemKind, ProviderId } from "../../shared/types";

interface SvgProps {
  className?: string;
  children: ReactNode;
}

function Svg({ className = "", children }: SvgProps) {
  return (
    <svg
      className={className ? `icon ${className}` : "icon"}
      viewBox="0 0 16 16"
      aria-hidden="true"
      focusable="false"
    >
      {children}
    </svg>
  );
}

const stroke = { fill: "none", stroke: "currentColor", strokeWidth: 1.5 } as const;

/** GitHub octocat mark (octicon mark-github, MIT). */
export function GithubIcon() {
  return (
    <Svg>
      <path
        fill="currentColor"
        d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"
      />
    </Svg>
  );
}

/** Simplified GitLab tanuki. */
export function GitlabIcon() {
  return (
    <Svg>
      <path
        fill="currentColor"
        d="M8 14.7 1.6 10a1 1 0 0 1-.36-1.1l1.07-3.28 1.2-3.7a.36.36 0 0 1 .68 0l1.29 3.95h5.04l1.29-3.95a.36.36 0 0 1 .68 0l1.2 3.7 1.07 3.28a1 1 0 0 1-.36 1.1Z"
      />
    </Svg>
  );
}

/** Issue: circle with a dot. */
export function IssueIcon() {
  return (
    <Svg>
      <circle cx="8" cy="8" r="6" {...stroke} />
      <circle cx="8" cy="8" r="1.6" fill="currentColor" />
    </Svg>
  );
}

/** Pull request: two branch pillars with an incoming arrow. */
export function PullIcon() {
  return (
    <Svg>
      <g {...stroke}>
        <circle cx="4.5" cy="3.5" r="1.75" />
        <circle cx="4.5" cy="12.5" r="1.75" />
        <circle cx="11.5" cy="12.5" r="1.75" />
        <path d="M4.5 5.25v5.5" />
        <path d="M11.5 10.75V7.25A1.75 1.75 0 0 0 9.75 5.5H8.1" />
      </g>
      <path fill="currentColor" d="M8.6 3.5 6.1 5.5l2.5 2Z" />
    </Svg>
  );
}

/** Merge request: branch curving into the main line. */
export function MergeIcon() {
  return (
    <Svg>
      <g {...stroke}>
        <circle cx="4.5" cy="3.5" r="1.75" />
        <circle cx="4.5" cy="12.5" r="1.75" />
        <circle cx="11.5" cy="9.75" r="1.75" />
        <path d="M4.5 5.25v5.5" />
        <path d="M4.5 5.25a4.5 4.5 0 0 0 4.5 4.5h.75" />
      </g>
    </Svg>
  );
}

/** Refresh: circular arrow. */
export function RefreshIcon() {
  return (
    <Svg>
      <path {...stroke} strokeLinecap="round" d="M13.25 8A5.25 5.25 0 1 1 8 2.75" />
      <path fill="currentColor" d="M10.9 2.75 7.65.95v3.6Z" />
    </Svg>
  );
}

/** Mark all read: double checkmark. */
export function MarkAllReadIcon() {
  return (
    <Svg>
      <g {...stroke} strokeLinecap="round" strokeLinejoin="round">
        <path d="M1.75 8.5 4.75 11.5l1.5-1.5" />
        <path d="M5.75 8.5 8.75 11.5l5.5-7" />
      </g>
    </Svg>
  );
}

/** Settings gear: toothed ring around a hub. */
export function GearIcon() {
  return (
    <Svg>
      <circle
        cx="8"
        cy="8"
        r="5.6"
        fill="none"
        stroke="currentColor"
        strokeWidth={2.6}
        strokeDasharray="2.2 2.2"
        strokeDashoffset={1.1}
      />
      <circle cx="8" cy="8" r="3.4" fill="none" stroke="currentColor" strokeWidth={1.5} />
    </Svg>
  );
}

/** Indeterminate spinner (rotated via CSS). */
export function SpinnerIcon() {
  return (
    <Svg className="spin">
      <circle
        cx="8"
        cy="8"
        r="6"
        fill="none"
        stroke="currentColor"
        strokeWidth={1.8}
        strokeLinecap="round"
        strokeDasharray="28 10"
      />
    </Svg>
  );
}

/** All caught up: check in a circle. */
export function CheckCircleIcon() {
  return (
    <Svg>
      <circle cx="8" cy="8" r="6.25" {...stroke} />
      <path
        {...stroke}
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M5.25 8.25 7.25 10.25l3.5-4.5"
      />
    </Svg>
  );
}

/** Empty inbox tray. */
export function InboxIcon() {
  return (
    <Svg>
      <path
        {...stroke}
        strokeLinejoin="round"
        d="M1.5 9.5 3.4 3.6a1 1 0 0 1 .95-.7h7.3a1 1 0 0 1 .95.7l1.9 5.9v3a1.25 1.25 0 0 1-1.25 1.25H2.75A1.25 1.25 0 0 1 1.5 12.5Z"
      />
      <path {...stroke} strokeLinejoin="round" d="M1.5 9.5h3.75l1 1.75h3.5l1-1.75h3.75" />
    </Svg>
  );
}

/** Disclosure chevron: points right; CSS rotates it down when expanded. */
export function ChevronIcon() {
  return (
    <Svg>
      <path {...stroke} strokeLinecap="round" strokeLinejoin="round" d="M6 3.75 10.25 8 6 12.25" />
    </Svg>
  );
}

/** Warning triangle. */
export function WarningIcon() {
  return (
    <Svg>
      <path {...stroke} strokeLinejoin="round" d="M8 2.5 14.5 13.5H1.5Z" />
      <path stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" d="M8 6.75v2.75" />
      <circle cx="8" cy="11.6" r=".85" fill="currentColor" />
    </Svg>
  );
}

export function ProviderIcon({ provider }: { provider: ProviderId }) {
  return provider === "github" ? <GithubIcon /> : <GitlabIcon />;
}

export function KindIcon({ kind }: { kind: ItemKind }) {
  switch (kind) {
    case "issue":
      return <IssueIcon />;
    case "pull":
      return <PullIcon />;
    case "merge":
      return <MergeIcon />;
  }
}

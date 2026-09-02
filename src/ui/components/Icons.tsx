// Inline SVG icons as typed components, all monochrome via currentColor so
// they inherit the surrounding text color. (The vanilla renderer kept these
// as innerHTML strings; JSX makes them plain markup.)

import type { ReactNode } from "react";
import type { ItemKind, ItemState, ProviderId } from "../../shared/types";

interface SvgProps {
  className?: string;
  viewBox?: string;
  children: ReactNode;
}

function Svg({ className = "", viewBox = "0 0 16 16", children }: SvgProps) {
  return (
    <svg
      className={className ? `icon ${className}` : "icon"}
      viewBox={viewBox}
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

/* The item-kind glyphs are the official Primer Octicons (16px, MIT), so the
   shapes match the badges users know from GitHub. */

/** Octicon issue-opened-16. */
export function IssueOpenedIcon() {
  return (
    <Svg>
      <path fill="currentColor" d="M8 9.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z" />
      <path
        fill="currentColor"
        d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0 6.5 6.5 0 0 0-13 0Z"
      />
    </Svg>
  );
}

/** Octicon issue-closed-16. */
export function IssueClosedIcon() {
  return (
    <Svg>
      <path
        fill="currentColor"
        d="M11.28 6.78a.75.75 0 0 0-1.06-1.06L7.25 8.69 5.78 7.22a.75.75 0 0 0-1.06 1.06l2 2a.75.75 0 0 0 1.06 0l3.5-3.5Z"
      />
      <path
        fill="currentColor"
        d="M16 8A8 8 0 1 1 0 8a8 8 0 0 1 16 0Zm-1.5 0a6.5 6.5 0 1 0-13 0 6.5 6.5 0 0 0 13 0Z"
      />
    </Svg>
  );
}

/** Octicon git-pull-request-16 (open PR/MR). */
export function GitPullRequestIcon() {
  return (
    <Svg>
      <path
        fill="currentColor"
        d="M1.5 3.25a2.25 2.25 0 1 1 3 2.122v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.25 2.25 0 0 1 1.5 3.25Zm5.677-.177L9.573.677A.25.25 0 0 1 10 .854V2.5h1A2.5 2.5 0 0 1 13.5 5v5.628a2.251 2.251 0 1 1-1.5 0V5a1 1 0 0 0-1-1h-1v1.646a.25.25 0 0 1-.427.177L7.177 3.427a.25.25 0 0 1 0-.354ZM3.75 2.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm0 9.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm8.25.75a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0Z"
      />
    </Svg>
  );
}

/** Octicon git-pull-request-draft-16. */
export function GitPullRequestDraftIcon() {
  return (
    <Svg>
      <path
        fill="currentColor"
        d="M3.25 1A2.25 2.25 0 0 1 4 5.372v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.251 2.251 0 0 1 3.25 1Zm9.5 14a2.25 2.25 0 1 1 0-4.5 2.25 2.25 0 0 1 0 4.5ZM2.5 3.25a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0ZM3.25 12a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm9.5 0a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5ZM14 7.5a1.25 1.25 0 1 1-2.5 0 1.25 1.25 0 0 1 2.5 0Zm0-4.25a1.25 1.25 0 1 1-2.5 0 1.25 1.25 0 0 1 2.5 0Z"
      />
    </Svg>
  );
}

/** Octicon git-pull-request-closed-16. */
export function GitPullRequestClosedIcon() {
  return (
    <Svg>
      <path
        fill="currentColor"
        d="M3.25 1A2.25 2.25 0 0 1 4 5.372v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.251 2.251 0 0 1 3.25 1Zm9.5 5.5a.75.75 0 0 1 .75.75v3.378a2.251 2.251 0 1 1-1.5 0V7.25a.75.75 0 0 1 .75-.75Zm-2.03-5.273a.75.75 0 0 1 1.06 0l.97.97.97-.97a.748.748 0 0 1 1.265.332.75.75 0 0 1-.205.729l-.97.97.97.97a.751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018l-.97-.97-.97.97a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734l.97-.97-.97-.97a.75.75 0 0 1 0-1.06ZM2.5 3.25a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0ZM3.25 12a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm9.5 0a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Z"
      />
    </Svg>
  );
}

/** Octicon git-merge-16 (merged). */
export function GitMergeIcon() {
  return (
    <Svg>
      <path
        fill="currentColor"
        d="M5.45 5.154A4.25 4.25 0 0 0 9.25 7.5h1.378a2.251 2.251 0 1 1 0 1.5H9.25A5.734 5.734 0 0 1 5 7.123v3.505a2.25 2.25 0 1 1-1.5 0V5.372a2.25 2.25 0 1 1 1.95-.218ZM4.25 13.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Zm8.5-4.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM5 3.25a.75.75 0 1 0 0 .005V3.25Z"
      />
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

/** Mark all read: crossing double checkmark (TDesign check-double, restyled). */
export function MarkAllReadIcon() {
  return (
    <Svg>
      <path
        {...stroke}
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M1.4 7.61l3.3 3.3.236-.236m5.893-5.893-2.593 2.593M14.6 4.78l-6.128 6.129-3.3-3.3"
      />
    </Svg>
  );
}

/**
 * Settings: Ionicons cog-outline (MIT), untouched path on its native 512
 * grid; the viewBox hugs the glyph (bounds 38–490) so it renders as large
 * as its stroke-drawn neighbors.
 */
export function SettingsIcon() {
  return (
    <Svg viewBox="36 36 456 456">
      <path
        fill="currentColor"
        d="m456.7 242.27l-26.08-4.2a8 8 0 0 1-6.6-6.82c-.5-3.2-1-6.41-1.7-9.51a8.08 8.08 0 0 1 3.9-8.62l23.09-12.82a8.05 8.05 0 0 0 3.9-9.92l-4-11a7.94 7.94 0 0 0-9.4-5l-25.89 5a8 8 0 0 1-8.59-4.11q-2.25-4.2-4.8-8.41a8.16 8.16 0 0 1 .7-9.52l17.29-19.94a8 8 0 0 0 .3-10.62l-7.49-9a7.88 7.88 0 0 0-10.5-1.51l-22.69 13.63a8 8 0 0 1-9.39-.9c-2.4-2.11-4.9-4.21-7.4-6.22a8 8 0 0 1-2.5-9.11l9.4-24.75A8 8 0 0 0 365 78.77l-10.2-5.91a8 8 0 0 0-10.39 2.21l-16.64 20.84a7.15 7.15 0 0 1-8.5 2.5s-5.6-2.3-9.8-3.71A8 8 0 0 1 304 87l.4-26.45a8.07 8.07 0 0 0-6.6-8.42l-11.59-2a8.07 8.07 0 0 0-9.1 5.61l-8.6 25.05a8 8 0 0 1-7.79 5.41h-9.8a8.07 8.07 0 0 1-7.79-5.41l-8.6-25.05a8.07 8.07 0 0 0-9.1-5.61l-11.59 2a8.07 8.07 0 0 0-6.6 8.42l.4 26.45a8 8 0 0 1-5.49 7.71c-2.3.9-7.3 2.81-9.7 3.71c-2.8 1-6.1.2-8.8-2.91l-16.51-20.34A8 8 0 0 0 156.75 73l-10.2 5.91a7.94 7.94 0 0 0-3.3 10.09l9.4 24.75a8.06 8.06 0 0 1-2.5 9.11c-2.5 2-5 4.11-7.4 6.22a8 8 0 0 1-9.39.9L111 116.14a8 8 0 0 0-10.5 1.51l-7.49 9a8 8 0 0 0 .3 10.62l17.29 19.94a8 8 0 0 1 .7 9.52q-2.55 4-4.8 8.41a8.11 8.11 0 0 1-8.59 4.11l-25.89-5a8 8 0 0 0-9.4 5l-4 11a8.05 8.05 0 0 0 3.9 9.92L85.58 213a7.94 7.94 0 0 1 3.9 8.62c-.6 3.2-1.2 6.31-1.7 9.51a8.08 8.08 0 0 1-6.6 6.82l-26.08 4.2a8.09 8.09 0 0 0-7.1 7.92v11.72a7.86 7.86 0 0 0 7.1 7.92l26.08 4.2a8 8 0 0 1 6.6 6.82c.5 3.2 1 6.41 1.7 9.51a8.08 8.08 0 0 1-3.9 8.62L62.49 311.7a8.05 8.05 0 0 0-3.9 9.92l4 11a7.94 7.94 0 0 0 9.4 5l25.89-5a8 8 0 0 1 8.59 4.11q2.25 4.2 4.8 8.41a8.16 8.16 0 0 1-.7 9.52l-17.29 19.96a8 8 0 0 0-.3 10.62l7.49 9a7.88 7.88 0 0 0 10.5 1.51l22.69-13.63a8 8 0 0 1 9.39.9c2.4 2.11 4.9 4.21 7.4 6.22a8 8 0 0 1 2.5 9.11l-9.4 24.75a8 8 0 0 0 3.3 10.12l10.2 5.91a8 8 0 0 0 10.39-2.21l16.79-20.64c2.1-2.6 5.5-3.7 8.2-2.6c3.4 1.4 5.7 2.2 9.9 3.61a8 8 0 0 1 5.49 7.71l-.4 26.45a8.07 8.07 0 0 0 6.6 8.42l11.59 2a8.07 8.07 0 0 0 9.1-5.61l8.6-25a8 8 0 0 1 7.79-5.41h9.8a8.07 8.07 0 0 1 7.79 5.41l8.6 25a8.07 8.07 0 0 0 9.1 5.61l11.59-2a8.07 8.07 0 0 0 6.6-8.42l-.4-26.45a8 8 0 0 1 5.49-7.71c4.2-1.41 7-2.51 9.6-3.51s5.8-1 8.3 2.1l17 20.94A8 8 0 0 0 355 439l10.2-5.91a7.93 7.93 0 0 0 3.3-10.12l-9.4-24.75a8.08 8.08 0 0 1 2.5-9.12c2.5-2 5-4.1 7.4-6.21a8 8 0 0 1 9.39-.9L401 395.66a8 8 0 0 0 10.5-1.51l7.49-9a8 8 0 0 0-.3-10.62l-17.29-19.94a8 8 0 0 1-.7-9.52q2.55-4.05 4.8-8.41a8.11 8.11 0 0 1 8.59-4.11l25.89 5a8 8 0 0 0 9.4-5l4-11a8.05 8.05 0 0 0-3.9-9.92l-23.09-12.82a7.94 7.94 0 0 1-3.9-8.62c.6-3.2 1.2-6.31 1.7-9.51a8.08 8.08 0 0 1 6.6-6.82l26.08-4.2a8.09 8.09 0 0 0 7.1-7.92V250a8.25 8.25 0 0 0-7.27-7.73M256 112a143.82 143.82 0 0 1 139.38 108.12A16 16 0 0 1 379.85 240H274.61a16 16 0 0 1-13.91-8.09l-52.1-91.71a16 16 0 0 1 9.85-23.39A147 147 0 0 1 256 112M112 256a144 144 0 0 1 43.65-103.41a16 16 0 0 1 25.17 3.47L233.06 248a16 16 0 0 1 0 15.87l-52.67 91.7a16 16 0 0 1-25.18 3.36A143.94 143.94 0 0 1 112 256m144 144a147 147 0 0 1-38.19-4.95a16 16 0 0 1-9.76-23.44l52.58-91.55a16 16 0 0 1 13.88-8H379.9a16 16 0 0 1 15.52 19.88A143.84 143.84 0 0 1 256 400"
      />
    </Svg>
  );
}

/** Open main window: outward arrow (Material arrow-outward, restyled). */
export function ArrowOutwardIcon() {
  return (
    <Svg>
      <g {...stroke} strokeLinecap="round" strokeLinejoin="round">
        <path d="M4 12 12 4" />
        <path d="M4 4h8v8" />
      </g>
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

/* Two sidebar sources have no Octicon counterpart; these are Feather's
   at-sign and eye (MIT), drawn on their native 24px grid at a stroke weight
   matching the 16px icons above. */
const stroke24 = {
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 2.25,
  strokeLinecap: "round",
  strokeLinejoin: "round",
} as const;

/** "@" — the mentions source. */
export function MentionIcon() {
  return (
    <Svg viewBox="0 0 24 24">
      <circle cx="12" cy="12" r="4" {...stroke24} />
      <path {...stroke24} d="M16 8v5a3 3 0 0 0 6 0v-1a10 10 0 1 0-3.92 7.94" />
    </Svg>
  );
}

/** An eye — the review-requests source. */
export function ReviewIcon() {
  return (
    <Svg viewBox="0 0 24 24">
      <path {...stroke24} d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8Z" />
      <circle cx="12" cy="12" r="3" {...stroke24} />
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

/**
     Kind + state pick the canonical GitHub badge shape; unknown state falls
    back to the plain open shape.
 */
export function KindIcon({ kind, state }: { kind: ItemKind; state?: ItemState }) {
  if (kind === "issue") {
    return state === "closed" ? <IssueClosedIcon /> : <IssueOpenedIcon />;
  }
  switch (state) {
    case "merged":
      return <GitMergeIcon />;
    case "closed":
      return <GitPullRequestClosedIcon />;
    case "draft":
      return <GitPullRequestDraftIcon />;
    default:
      return <GitPullRequestIcon />;
  }
}

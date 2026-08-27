// Inline SVG icons as typed components, all monochrome via currentColor so
// they inherit the surrounding text color. (The vanilla renderer kept these
// as innerHTML strings; JSX makes them plain markup.)

import type { ReactNode } from "react";
import type { ItemKind, ItemState, ProviderId } from "../../shared/types";

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

/** Kind + state pick the canonical GitHub badge shape; unknown state falls
    back to the plain open shape. */
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

import { useEffect } from "react";

/**
 * Follow the system accent color pushed with the app state; the stylesheet's
 * per-theme blues are the fallback when the main process couldn't read it.
 * (CSSOM writes are fine under the CSP; only inline <style> is forbidden.)
 */
export function useAccent(accentColor: string | null): void {
  useEffect(() => {
    if (accentColor) {
      document.documentElement.style.setProperty("--accent", accentColor);
    } else {
      document.documentElement.style.removeProperty("--accent");
    }
  }, [accentColor]);
}

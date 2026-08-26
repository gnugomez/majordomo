// Provider registry. The main process sync loop consumes this; the
// createProviders signature is frozen.

import type { ProviderClient, ProviderId } from "../shared/types";
import { createGithubClient } from "./github";
import { createGitlabClient } from "./gitlab";

export function createProviders(): Record<ProviderId, ProviderClient> {
  return {
    github: createGithubClient(),
    gitlab: createGitlabClient(),
  };
}

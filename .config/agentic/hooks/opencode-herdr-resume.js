// Records the OpenCode session of a `Herdr` app terminal so its shell can
// resume it after a reboot, see `herdr-application-resume.sh`. Does nothing
// outside an app terminal. OpenCode has no session start event with the session
// ID on a resumed session, a chat message always carries it, so it is saved
// there, once per session in this process.
import { homedir } from "node:os";
import { join } from "node:path";

const script = join(homedir(), ".config", "agentic", "hooks", "herdr-application-resume.sh");

export const HerdrResume = async ({ $, directory }) => {
  if (!process.env.HC_TERMINAL_ID) return {};

  let saved = null;
  return {
    "chat.message": async (input) => {
      if (!input.sessionID || input.sessionID === saved) return;
      saved = input.sessionID;
      await $`bash ${script} save opencode ${input.sessionID} ${directory}`.quiet().nothrow();
    },
  };
};

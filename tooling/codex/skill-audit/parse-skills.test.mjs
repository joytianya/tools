import assert from "node:assert/strict";
import test from "node:test";

import { parseAvailableSkills, parseRoots } from "./parse-skills.mjs";

const currentPromptShape = `<skills_instructions>
### Skill roots
- \`r0\` = \`/Users/example/.agents/skills\`
- \`r1\` = \`/Users/example/.codex/plugins/cache/openai-bundled\`
### Available skills
- imagegen: Generate or edit raster images. (file: r0/imagegen/SKILL.md)
- chrome:control-chrome: Control the user's Chrome browser. (file: r1/chrome/skills/control-chrome/SKILL.md)
</skills_instructions>`;

test("parses skill roots from the current prompt shape", () => {
  assert.deepEqual(parseRoots(currentPromptShape), {
    r0: "/Users/example/.agents/skills",
    r1: "/Users/example/.codex/plugins/cache/openai-bundled",
  });
});

test("parses current skill lines including plugin-prefixed names", () => {
  assert.deepEqual(parseAvailableSkills(currentPromptShape), [
    { name: "imagegen", fileRef: "r0/imagegen/SKILL.md" },
    {
      name: "chrome:control-chrome",
      fileRef: "r1/chrome/skills/control-chrome/SKILL.md",
    },
  ]);
});

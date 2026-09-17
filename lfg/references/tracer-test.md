# Tracer test recipe

A tracer test proves one slice end to end against the running app and also
leaves the artifact you demo from. Write one test per slice, outside-in: start
from what the user does on the demo path, not from a unit.

Pick the shape by what the app is:

- **Web UI** → Playwright, below.
- **CLI, API, or anything without a page** → a transcript, below. Do not install Playwright.

## Web: Playwright

Install the runner and one browser. Chromium only:

```bash
npm i -D @playwright/test
npx playwright install chromium --with-deps
```

Use the project's package manager if it is not npm. For flags and options, see
[Playwright's installation docs](https://playwright.dev/docs/intro) instead of
guessing.

Minimal `playwright.config.ts`:

```ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tracers",
  use: {
    baseURL: "http://localhost:3000",
    screenshot: "on",
  },
  webServer: {
    command: "npm run dev",
    url: "http://localhost:3000",
    reuseExistingServer: true,
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
```

Replace the port and `command` with the ones the app actually uses. Always set
`reuseExistingServer: true`. Without it, the runner tries to start a second dev
server on a port that is already taken.

`screenshot: "on"` is why the tracer also serves as the demo proof: every test
leaves a screenshot under `test-results/`. For what each recording option
captures and when, read
[Playwright's recording options](https://playwright.dev/docs/test-use-options#recording-options).

One slice, one test:

```ts
import { test, expect } from "@playwright/test";

test("slice 1: visitor creates a board and sees it listed", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "New board" }).click();
  await page.getByRole("textbox", { name: "Board name" }).fill("Demo");
  await page.getByRole("button", { name: "Create" }).click();
  await expect(page.getByRole("link", { name: "Demo" })).toBeVisible();
});
```

- Locate by role and accessible name. A role locator breaks when what the user sees changes, which is the change a demo needs to catch.
- `await` every `expect`. See [Playwright's assertions docs](https://playwright.dev/docs/test-assertions) for which assertions are async.
- End each test on a visible outcome the demo would show, not on an internal value.

Run the whole suite with `npx playwright test`. Exit 0 means every tracer
passed.

## CLI or API: transcript

The tracer is a script that runs the demo path and saves what happened to a
file under `test-results/`. It checks the output, so a failure exits non-zero.

```bash
mkdir -p test-results
{
  echo "\$ curl -s -X POST localhost:3000/boards -d '{\"name\":\"Demo\"}'"
  curl -s -X POST localhost:3000/boards -H 'content-type: application/json' -d '{"name":"Demo"}'
  echo
  echo "\$ curl -s localhost:3000/boards"
  curl -s localhost:3000/boards
} | tee test-results/slice-1.transcript.txt | grep -q '"name":"Demo"'
```

Save each command above its output, so the transcript works as a demo script.
The file path is the proof entry in the recap.

## Optional: agent-browser walk

```bash
command -v agent-browser
```

If that resolves, load its current commands with `agent-browser skills get core`
and walk the demo path once, saving a final screenshot. If it does not resolve,
skip the walk. The tracer screenshots are the proof.

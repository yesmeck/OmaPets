import assert from "node:assert/strict"
import { readFileSync, statSync } from "node:fs"

const qml = readFileSync(new URL("../Main.qml", import.meta.url), "utf8")
const manifest = JSON.parse(readFileSync(new URL("../manifest.json", import.meta.url), "utf8"))

assert.equal(manifest.id, "omapets")
assert.match(qml, /moduleName:\s*"omapets"/)
assert.match(qml, /target:\s*"omapets"/)
assert.doesNotMatch(qml, /wei\.omarpets/)

for (const script of ["scan-pets", "detect-agent"]) {
  const scriptUrl = new URL(`../bin/${script}`, import.meta.url)
  assert.equal(readFileSync(scriptUrl, "utf8").startsWith("#!/usr/bin/env bash\n"), true)
  assert.notEqual(statSync(scriptUrl).mode & 0o111, 0, `${script} must be executable`)
  assert.match(qml, new RegExp(`Qt\\.resolvedUrl\\(\\"bin/${script}\\"\\)`))
}

const installerUrl = new URL("../bin/omapets", import.meta.url)
assert.equal(readFileSync(installerUrl, "utf8").startsWith("#!/usr/bin/env bash\n"), true)
assert.notEqual(statSync(installerUrl).mode & 0o111, 0, "the Bash pet installer must be executable")

assert.doesNotMatch(qml, /command:\s*\["sh",\s*"-c"/)

assert.doesNotMatch(
  qml,
  /statusTooltipText:\s*petName/,
  "the status tooltip must not include the selected pet name",
)

assert.doesNotMatch(
  qml,
  /assets\/ponyta|Ponyta \(bundled\)/,
  "the plugin must not depend on a bundled pet",
)

assert.match(
  qml,
  /KeyboardPanel\s*\{\s*id:\s*petPicker[\s\S]*?GridView\s*\{[\s\S]*?model:\s*root\.availablePets/,
  "the pet picker must use the same panel surface as Tailscale with a grid item for every discovered pet",
)

assert.match(
  qml,
  /source:\s*petTile\.modelData\.spritesheet/,
  "each pet tile must display its spritesheet",
)

assert.match(
  qml,
  /var\s+previewSheet\s*=\s*"file:\/\/"\s*\+\s*previewHome\s*\+\s*"\/"\s*\+\s*id\s*\+\s*"\.png"/,
  "downloaded pet previews must use Qt-compatible cached PNG atlases",
)

assert.match(
  qml,
  /atlasRows:\s*rows[\s\S]*?height:\s*petPreview\.height\s*\*\s*petTile\.modelData\.atlasRows/,
  "pet picker previews must preserve v1 and v2 atlas row heights",
)

assert.match(
  qml,
  /GridView\s*\{[\s\S]*?anchors\.top:\s*petPickerHeader\.bottom[\s\S]*?anchors\.bottom:\s*petActionRow\.top[\s\S]*?ScrollBar\.vertical:\s*ScrollBar/,
  "the pet grid must fill the scrollable viewport above the action toolbar",
)

assert.match(
  qml,
  /acceptedButtons:\s*Qt\.LeftButton\s*\|\s*Qt\.MiddleButton\s*\|\s*Qt\.RightButton[\s\S]*?onClicked:\s*function\(mouse\)\s*\{[\s\S]*?mouse\.button\s*===\s*Qt\.RightButton[\s\S]*?root\.cycleActivityState\(\)[\s\S]*?mouse\.button\s*===\s*Qt\.MiddleButton[\s\S]*?else\s*\{[\s\S]*?root\.openPetPicker\(\)/,
  "left-clicking the pet must open the pet panel",
)

assert.match(
  qml,
  /function\s+cycleActivityState\(\)\s*\{[\s\S]*?\["idle",\s*"working",\s*"waiting",\s*"success",\s*"error"\][\s\S]*?setActivity\(next,\s*"",\s*5000\)/,
  "right-clicking the pet must cycle through every activity status",
)

assert.doesNotMatch(
  qml,
  /Test working animation/,
  "the pet must not expose a synthetic working-animation action",
)

assert.match(
  qml,
  /contentHeight:\s*Style\.space\(400\)/,
  "the panel must use a fixed 400-pixel height",
)

assert.match(
  qml,
  /FileView\s*\{[\s\S]*?path:\s*Qt\.resolvedUrl\("assets\/logo\.txt"\)[\s\S]*?root\.panelLogo\s*=/,
  "the pet panel must load the bundled OmaPets logo",
)

assert.match(
  qml,
  /Text\s*\{\s*id:\s*omapetsLogo[\s\S]*?text:\s*root\.panelLogo[\s\S]*?font\.family:\s*"monospace"[\s\S]*?horizontalAlignment:\s*Text\.AlignHCenter[\s\S]*?textFormat:\s*Text\.PlainText/,
  "the pet panel must render the logo as centered plain monospaced text",
)

assert.match(
  qml,
  /Button\s*\{\s*id:\s*installPetButton[\s\S]*?text:\s*"Install pet"[\s\S]*?onClicked:\s*root\.openPetInstaller\(\)/,
  "the pet panel must expose its installer even when pets are already available",
)

assert.match(
  qml,
  /Button\s*\{\s*id:\s*installHooksButton[\s\S]*?text:\s*"Agent hooks"[\s\S]*?onClicked:\s*root\.openAgentHookInstaller\(\)/,
  "the pet panel must expose interactive agent hook installation",
)

assert.match(
  qml,
  /Row\s*\{\s*id:\s*petActionRow[\s\S]*?anchors\.bottom:\s*parent\.bottom[\s\S]*?id:\s*installPetButton[\s\S]*?width:\s*petGrid\.cellWidth\s*-\s*Style\.spacing\.sm[\s\S]*?id:\s*openPetsFolderButton[\s\S]*?id:\s*installHooksButton/,
  "the bottom toolbar must use the pet grid's three-column layout",
)

assert.match(
  qml,
  /Button\s*\{\s*id:\s*openPetsFolderButton[\s\S]*?text:\s*"Open folder"[\s\S]*?onClicked:\s*root\.openPetsFolder\(\)/,
  "the pet panel must expose the pets folder",
)

assert.match(
  qml,
  /id:\s*petFolderCreator[\s\S]*?command:\s*\["mkdir",\s*"-p",\s*root\.petsHome\][\s\S]*?Quickshell\.execDetached\(\["xdg-open",\s*root\.petsHome\]\)/,
  "opening the pets folder must create it first and use the desktop file manager",
)

assert.match(
  qml,
  /Qt\.resolvedUrl\("bin\/install-agent-hooks"\)[\s\S]*?--interactive[\s\S]*?xdg-terminal-exec/,
  "agent hook installation must open in an OmaPets floating terminal",
)

assert.match(
  qml,
  /Qt\.resolvedUrl\("bin\/omapets"\)[\s\S]*?xdg-terminal-exec[\s\S]*?--title=OmaPets/,
  "the installer button must run the bundled Bash installer in an OmaPets terminal",
)

assert.doesNotMatch(
  qml,
  /omarchy-launch-floating-terminal-with-presentation/,
  "the installer terminal must not render the Omarchy presentation banner",
)

assert.match(
  qml,
  /x:\s*-\(root\.currentFrame\s*%\s*6\)\s*\*\s*petPreview\.width/,
  "pet previews must animate through their atlas frames",
)

assert.match(
  qml,
  /text:\s*petTile\.modelData\.name\s*\+[\s\S]*?petTile\.modelData\.id/,
  "pet labels must expose the directory ID as well as the display name",
)

assert.match(
  qml,
  /Text\s*\{[\s\S]*?text:\s*petTile\.modelData\.name[\s\S]*?textFormat:\s*Text\.PlainText/,
  "provider-controlled pet names must never be interpreted as rich text",
)

console.log("Tailscale-style pet panel animates every discovered pet and exposes its directory ID")

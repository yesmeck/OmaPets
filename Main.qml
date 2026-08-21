import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omapets"

  // Codex atlas rows: idle, right, left, wave, jump, failed, waiting,
  // running/active, review. V2 adds two rows but keeps these first nine.
  readonly property var stateRows: ({
    "idle": 0,
    "working": 7,
    "waiting": 6,
    "success": 8,
    "error": 5
  })
  readonly property var stateLabels: ({
    "idle": "Agent idle",
    "working": "Agent working",
    "waiting": "Agent needs input",
    "success": "Agent finished",
    "error": "Agent failed"
  })
  // Codex pet packages do not declare per-row frame counts. Normal loops use
  // six frames and failure uses all eight atlas columns.
  readonly property var stateFrames: ({
    "idle": 6,
    "working": 6,
    "waiting": 6,
    "success": 6,
    "error": 8
  })

  property string activityState: "idle"
  property string activityDetail: ""
  property string detectedState: "idle"
  property string detectedAgent: ""
  property double overrideUntil: 0
  property int currentFrame: 0
  property int imageRevision: 0
  property bool petPickerOpen: false
  property bool petAvailable: false
  property int manifestRetryCount: 0
  property int atlasRows: 9
  property var availablePets: []
  property string panelLogo: "OmaPets"

  readonly property real petScale: Number(setting("scale", 0.8))
  readonly property int frameInterval: Math.max(60, Number(setting("frameIntervalMs", 140)))
  readonly property bool autoDetect: setting("autoDetect", true) !== false
  readonly property int activeWindowSec: Math.max(2, Number(setting("activeWindowSec", 8)))
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || home + "/.cache"
  readonly property string convertedSheetPath: cacheHome + "/omarpets/spritesheet.png"
  readonly property string previewHome: cacheHome + "/omarpets/previews"
  readonly property string configuredPetPath: String(setting("petPath", ""))
  readonly property string petsHome: home + "/.config/omapets/pets"
  readonly property string bundledPetPath:
    filePath(Qt.resolvedUrl("assets/pets/glitchcat"))
  readonly property string resolvedPetPath: configuredPetPath === ""
    ? bundledPetPath : resolvePetPath(configuredPetPath)
  readonly property url petManifestUrl: resolvedPetPath === "" ? ""
    : "file://" + resolvedPetPath.replace(/\/$/, "") + "/pet.json"
  property string petName: "No pet installed"
  property url spritesheetUrl: ""
  property string pendingSheetUrl: ""
  readonly property bool tooltipHovered: hover.hovered
  readonly property string statusTooltipText:
    (detectedAgent === "" ? "" : agentLabel(detectedAgent) + " · ")
    + (stateLabels[activityState] || activityState)
    + (activityDetail === "" ? "" : "\n" + activityDetail)

  function setting(key, fallback) {
    return settings && settings[key] !== undefined ? settings[key] : fallback
  }

  function expandHome(path) {
    var value = String(path || "")
    if (value === "~") return home
    if (value.indexOf("~/") === 0) return home + value.slice(1)
    return value
  }

  function resolvePetPath(path) {
    var value = expandHome(path)
    if (value !== "" && value.indexOf("/") < 0)
      return petsHome + "/" + value
    return value
  }

  function refreshAvailablePets() {
    if (!petScanner.running) petScanner.running = true
  }

  function close() {
    petPickerOpen = false
  }

  function openPetPicker() {
    petPickerOpen = true
    refreshAvailablePets()
  }

  function openPetInstaller() {
    if (!root.bar) return
    var installer = root.filePath(Qt.resolvedUrl("bin/omapets"))
    var terminal = "setsid uwsm-app -- xdg-terminal-exec"
      + " --app-id=org.omarchy.terminal --title=OmaPets -e bash -c "
      + Util.shellQuote(installer)
    root.close()
    root.bar.run(terminal)
  }

  function openAgentHookInstaller() {
    if (!root.bar) return
    var installer = root.filePath(Qt.resolvedUrl("bin/install-agent-hooks"))
    var command = Util.shellQuote(installer) + " --interactive"
    var terminal = "setsid uwsm-app -- xdg-terminal-exec"
      + " --app-id=org.omarchy.terminal --title=OmaPets -e bash -c "
      + Util.shellQuote(command)
    root.close()
    root.bar.run(terminal)
  }

  function openPetsFolder() {
    if (petFolderCreator.running) return
    root.close()
    petFolderCreator.running = true
  }

  function parseAvailablePets(output) {
    var pets = [{
      id: "glitchcat",
      petPath: "",
      name: "Glitchcat",
      atlasRows: 9,
      spritesheet: Qt.resolvedUrl("assets/pets/glitchcat/preview.png")
    }]
    var lines = String(output || "").trim().split("\n")
    for (var index = 0; index < lines.length; index++) {
      if (lines[index] === "") continue
      var fields = lines[index].split("\t")
      var id = String(fields.shift() || "").trim()
      if (id === "" || id === "glitchcat") continue
      var name = String(fields.shift() || id).trim()
      fields.shift()
      var rows = Number(fields.shift() || 9) === 11 ? 11 : 9
      var previewSheet = "file://" + previewHome + "/" + id + ".png"
      pets.push({
        id: id,
        petPath: id,
        name: name,
        atlasRows: rows,
        spritesheet: previewSheet
      })
    }
    availablePets = pets
  }

  function selectPet(id) {
    var selectedId = String(id || "")
    var entry = { id: root.moduleName }
    for (var key in root.settings)
      if (key !== "id") entry[key] = root.settings[key]
    entry.petPath = selectedId

    var updated = false
    if (root.bar && root.bar.shell
        && typeof root.bar.shell.updateEntryInline === "function")
      updated = root.bar.shell.updateEntryInline(root.moduleName, entry)
    if (!updated) root.settings = entry
    petPickerOpen = false
  }

  function filePath(url) {
    var value = String(url || "")
    return decodeURIComponent(value.replace(/^file:\/\//, ""))
  }

  function loadSpritesheet(url) {
    var value = String(url || "")
    if (/\.webp$/i.test(value)) {
      pendingSheetUrl = value
      if (!sheetConverter.running) {
        sheetConverter.command = ["sh", "-c",
          "mkdir -p \"$1\" && magick \"$2\" \"$3\"",
          "omarpets-convert", root.cacheHome + "/omarpets", filePath(value), root.convertedSheetPath]
        sheetConverter.running = true
      }
    } else {
      spritesheetUrl = value
    }
  }

  function normalizedState(value) {
    var state = String(value || "").toLowerCase()
    return stateRows[state] !== undefined ? state : "idle"
  }

  function setActivity(state, detail, holdMs) {
    activityState = normalizedState(state)
    activityDetail = String(detail || "")
    overrideUntil = holdMs > 0 ? Date.now() + holdMs : 0
    currentFrame = 0
  }

  function cycleActivityState() {
    var states = ["idle", "working", "waiting", "success", "error"]
    var current = states.indexOf(activityState)
    var next = states[(current + 1) % states.length]
    setActivity(next, "", 5000)
  }

  function applyDetectedState(state) {
    detectedState = normalizedState(state)
    if (overrideUntil > Date.now()) return
    if (overrideUntil !== 0) overrideUntil = 0
    if (activityState !== detectedState) setActivity(detectedState, "", 0)
  }

  function applyDetectorOutput(output) {
    var parts = String(output || "").trim().split(":")
    detectedAgent = parts.length > 1 ? parts[0] : ""
    applyDetectedState(parts.length > 1 ? parts[1] : parts[0])
  }

  function agentLabel(agent) {
    var labels = {
      "codex": "Codex",
      "claude": "Claude Code",
      "opencode": "OpenCode",
      "gemini": "Gemini",
      "copilot": "GitHub Copilot",
      "crush": "Crush",
      "grok": "Grok",
      "omp": "Oh My Pi",
      "pi": "Pi"
    }
    return labels[agent] || agent
  }

  function reloadPet() {
    if (petManifestLoader.item) petManifestLoader.item.reload()
  }

  onPetManifestUrlChanged: {
    manifestRetryCount = 0
    if (petManifestUrl !== "") manifestRetryTimer.restart()
  }

  FileView {
    path: Qt.resolvedUrl("assets/logo.txt")
    printErrors: false
    onLoaded: root.panelLogo = String(text() || "OmaPets").replace(/\s+$/, "")
  }

  Loader {
    id: petManifestLoader
    active: root.petManifestUrl !== ""

    sourceComponent: FileView {
      path: root.petManifestUrl
      watchChanges: true
      printErrors: false
      onFileChanged: reload()
      onLoadFailed: {
        root.petAvailable = false
        root.petName = "No pet installed"
        root.atlasRows = 9
        root.spritesheetUrl = ""
        if (root.petManifestUrl !== "" && root.manifestRetryCount < 3) {
          root.manifestRetryCount++
          manifestRetryTimer.restart()
        }
      }
      onLoaded: {
        try {
          var pet = JSON.parse(String(text() || "{}"))
          var sheet = String(pet.spritesheetPath || "spritesheet.webp")
          if (sheet.indexOf("..") >= 0 || sheet.indexOf("/") === 0)
            throw new Error("spritesheetPath must stay inside the pet folder")
          root.petName = String(pet.displayName || pet.id || "Pet")
          root.atlasRows = Number(pet.spriteVersionNumber || 1) >= 2 ? 11 : 9
          var manifestUrl = String(root.petManifestUrl)
          var slash = manifestUrl.lastIndexOf("/")
          root.loadSpritesheet(manifestUrl.slice(0, slash + 1) + sheet)
          root.petAvailable = true
          root.manifestRetryCount = 0
          root.imageRevision++
        } catch (error) {
          root.petAvailable = false
          root.atlasRows = 9
          root.spritesheetUrl = ""
          console.warn("omarpets: invalid pet manifest", error)
        }
      }
    }
  }

  Timer {
    id: manifestRetryTimer
    interval: 100
    repeat: false
    onTriggered: root.reloadPet()
  }


  Process {
    id: sheetConverter
    running: false
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.spritesheetUrl = ""
        Qt.callLater(function() {
          root.spritesheetUrl = "file://" + root.convertedSheetPath
          root.imageRevision++
        })
      } else {
        console.warn("omarpets: could not convert WebP spritesheet", root.pendingSheetUrl)
      }
    }
  }

  Process {
    id: petScanner
    running: false
    command: [root.filePath(Qt.resolvedUrl("bin/scan-pets")), root.petsHome, root.previewHome]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseAvailablePets(text)
    }
  }

  Process {
    id: petFolderCreator
    running: false
    command: ["mkdir", "-p", root.petsHome]
    onExited: function(exitCode) {
      if (exitCode === 0) Quickshell.execDetached(["xdg-open", root.petsHome])
      else console.warn("omarpets: could not create pets folder", root.petsHome)
    }
  }

  IpcHandler {
    target: "omapets"

    function idle(detail: string): void { root.setActivity("idle", detail, 0) }
    function working(detail: string): void { root.setActivity("working", detail, 0) }
    function waiting(detail: string): void { root.setActivity("waiting", detail, 0) }
    function success(detail: string): void { root.setActivity("success", detail, 5000) }
    function error(detail: string): void { root.setActivity("error", detail, 8000) }
    function refresh(): void { root.reloadPet() }
    function refreshPets(): void { root.refreshAvailablePets() }
  }

  Process {
    id: detector
    running: false
    command: [root.filePath(Qt.resolvedUrl("bin/detect-agent")), String(root.activeWindowSec), root.home]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyDetectorOutput(text)
    }
  }

  Timer {
    interval: 2000
    running: root.autoDetect
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!detector.running) detector.running = true
  }

  Timer {
    interval: root.frameInterval
    running: true
    repeat: true
    onTriggered: root.currentFrame = (root.currentFrame + 1) % root.stateFrames[root.activityState]
  }

  implicitWidth: Math.round(38 * petScale)
  implicitHeight: barSize

  Item {
    id: frameViewport
    readonly property real frameHeight: root.height * root.petScale
    readonly property real frameWidth: frameHeight * 192 / 208
    width: frameWidth
    height: frameHeight
    anchors.centerIn: parent
    clip: true

    Image {
      id: atlas
      width: frameViewport.frameWidth * 8
      height: frameViewport.frameHeight * root.atlasRows
      x: -root.currentFrame * frameViewport.frameWidth
      y: -root.stateRows[root.activityState] * frameViewport.frameHeight
      source: root.spritesheetUrl
      cache: false
      smooth: false
      mipmap: false
      asynchronous: true
      visible: root.petAvailable
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      hoverEnabled: true
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          root.cycleActivityState()
        } else if (mouse.button === Qt.MiddleButton) {
          root.setActivity("success", "Test success animation", 2500)
        } else {
          if (root.petPickerOpen) root.close()
          else root.openPetPicker()
        }
      }
    }
  }

  KeyboardPanel {
    id: petPicker
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.petPickerOpen
    contentWidth: petPicker.fittedContentWidth(Style.space(360))
    contentHeight: Style.space(400)

    Item {
      id: petPickerContent
      anchors.fill: parent

      Item {
        id: petPickerHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: omapetsLogo.implicitHeight

        Text {
          id: omapetsLogo
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          text: root.panelLogo
          color: root.bar.foreground
          font.family: "monospace"
          font.pixelSize: Style.space(4)
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
        }
      }

      Row {
        id: petActionRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: installPetButton.implicitHeight
        spacing: Style.spacing.sm

        Button {
          id: installPetButton
          width: petGrid.cellWidth - Style.spacing.sm
          text: "Install pet"
          bordered: true
          focusable: true
          onClicked: root.openPetInstaller()
        }

        Button {
          id: openPetsFolderButton
          width: installPetButton.width
          text: "Open folder"
          bordered: true
          focusable: true
          onClicked: root.openPetsFolder()
        }

        Button {
          id: installHooksButton
          width: installPetButton.width
          text: "Agent hooks"
          bordered: true
          focusable: true
          onClicked: root.openAgentHookInstaller()
        }
      }

      GridView {
        id: petGrid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: petPickerHeader.bottom
        anchors.topMargin: Style.spacing.md
        anchors.bottom: petActionRow.top
        anchors.bottomMargin: Style.spacing.md
        cellWidth: width / 3
        cellHeight: Style.space(104)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {
          policy: ScrollBar.AsNeeded
        }
        model: root.availablePets
        visible: root.availablePets.length > 0

        delegate: Button {
          id: petTile
          required property var modelData
          width: GridView.view.cellWidth - Style.spacing.sm
          height: GridView.view.cellHeight - Style.spacing.sm
          selected: String(root.configuredPetPath) === String(petTile.modelData.petPath)
          bordered: true
          focusable: true
          onClicked: root.selectPet(petTile.modelData.petPath)

          Item {
            id: petPreview
            width: Style.space(58)
            height: width * 208 / 192
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Style.spacing.sm
            clip: true

            Image {
              width: petPreview.width * 8
              height: petPreview.height * petTile.modelData.atlasRows
              x: -(root.currentFrame % 6) * petPreview.width
              y: 0
              source: petTile.modelData.spritesheet
              cache: true
              smooth: false
              mipmap: false
              asynchronous: true
            }
          }

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Style.spacing.sm
            text: petTile.modelData.name
              + (petTile.modelData.id !== ""
                  && String(petTile.modelData.name).toLowerCase() !== String(petTile.modelData.id).toLowerCase()
                ? " (" + petTile.modelData.id + ")" : "")
            textFormat: Text.PlainText
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: petPickerHeader.bottom
        anchors.topMargin: Style.space(36)
        anchors.bottom: petActionRow.top
        anchors.bottomMargin: Style.spacing.md
        spacing: Style.spacing.md
        visible: !petScanner.running && root.availablePets.length === 0

        Text {
          width: parent.width
          text: "No pets installed yet. Use Install pet to add one."
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }

      }
    }
  }

  HoverHandler {
    id: hover
    onHoveredChanged: {
      if (!root.bar) return
      if (hovered) root.bar.showTooltip(root, root.statusTooltipText)
      else root.bar.hideTooltip(root)
    }
  }
}

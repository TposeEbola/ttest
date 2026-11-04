# QuickPlan

A small native macOS app for quick, measured 2D house plans. The editor uses a black-and-white canvas with blue alignment guides, precise wall dimensions, a separate door and window panel, and floor layers for multi-storey designs. Drawing stays exclusively in 2D.

## What you can do

- Draw connected walls with endpoint snapping. Grid snapping and right-angle alignment are optional, so you can draw freely.
- Set a default wall thickness or enter a custom thickness for an individual wall.
- Select and edit wall coordinates, length, and thickness. Moving a shared corner keeps connected walls together.
- Shift-click to select multiple walls or openings, copy and paste items between floors, and rotate wall groups with a circular angle control.
- Use blue smart guides for common angles and matching measurements, or turn them off for free drawing.
- Place doors and windows on walls using common real-world width and height presets, or enter custom measurements.
- Edit opening measurements and position. Openings must fit on their wall without overlapping.
- Keep multiple floors in one file, with Photoshop-style layer selection, visibility, locking, opacity, and stacking order.
- Work in feet and inches by default, or switch to millimetres in Settings. Changing units preserves the plan’s dimensions.
- Save and reopen all floors in one `.quickplan` document, and export the active floor as a vector SVG drawing.

QuickPlan is a 2D schematic editor. Its drawings are a starting point for design and measurement, not certified construction documents.

## Run on a Mac

New to Xcode? Follow [the step-by-step first-run guide](docs/FIRST_RUN.md).

Requires **macOS 14 or later** and **Xcode 15 or later** with its command-line tools selected. There are no third-party package dependencies.

From the repository directory:

```sh
./scripts/run.sh
```

Alternatively, open `Package.swift` in Xcode, choose the **QuickPlan** executable scheme and **My Mac**, then run it. If the Swift toolchain is unavailable, install Xcode and choose it in **Xcode → Settings → Locations → Command Line Tools**.

To produce a standalone application bundle:

```sh
./scripts/build-app.sh
open dist/QuickPlan.app
```

The script creates `dist/QuickPlan.app` and signs it locally with an ad-hoc signature. Distribution outside your own machine requires your own Apple signing and notarization process.

## Start drawing

1. Choose the wall tool and click the start and end of a wall. Continue clicking to draw connected walls. Press Escape to end the chain.
2. Choose the select tool and click a wall to enter exact measurements in the inspector.
3. Open **Objects** to choose a door or window and its dimensions, then click a wall to place it.
4. Add floor layers as needed, then save the whole plan as a `.quickplan` document. Export SVG when you need a portable vector drawing of the active floor.

Open the visible **Settings** button or **QuickPlan → Settings…** (**⌘,**) to choose feet/inches or millimetres. Measurement fields accept explicit entries such as `12' 6"`, `30in`, `30 1/2in`, and `762mm`. Plain numbers mean inches in feet/inches mode and millimetres in metric mode. The plan stores geometry in millimetres to preserve its measurements when you switch.

Wall dimensions measure **centre lines**. Thickness extends equally on either side. **Orthogonal walls**, **Snap to grid**, and **Smart guides** are separate drawing aids. Turn off the aids you do not want for free placement.

For a starting example, open [Examples/Starter.quickplan](Examples/Starter.quickplan). Its exported drawing is [Examples/Starter.svg](Examples/Starter.svg).

For a layered example, open [Examples/TwoFloors.quickplan](Examples/TwoFloors.quickplan). It has an editable second floor over a locked ground floor at 25% opacity.

Preset sizes are convenient starting dimensions; match them to the actual product you plan to use.

## Select, copy, and rotate

With the select tool, **Shift-click** walls or openings to add or remove them from the selection. Use **⌘C** and **⌘V** to copy and paste through the system clipboard, on the same floor or after selecting another floor. Copied walls include their attached doors and windows. Pasted items have independent identities, so editing a copy leaves the original unchanged.

Normal Paste offsets copied wall groups by **12 inches** on both axes, increasing the offset on repeated pastes so copies remain distinct. Use **Paste in Place** (**⇧⌘V**) to retain the source coordinates—useful for aligning copied geometry on another floor.

To paste a door or window without its wall, select a valid destination wall before pasting. The opening must fit there without overlapping existing openings. Doors and windows stay attached to their host wall and cannot rotate independently; select the host wall to rotate them together.

Choose **Rotate** for selected walls or a wall group. Drag the handle on the circular popover to preview rotation with a live degree readout, or type an angle. **Apply rotation** commits the preview as one undoable edit; **Cancel** leaves the plan unchanged.

Unselected walls stay in place when you rotate a selection; select all adjoining walls that you want to rotate together.

Blue **Smart guides** help align walls at common **45° increments**, including **90°** and **180°**, and match existing wall lengths or grid measurements. During rotation, an angle guide aligns the primary wall’s final heading on the plan; the rotation value is the change from its starting angle. Disable Smart guides in the Draw sidebar or Settings when you want an unsnapped angle. Grid snapping and orthogonal alignment have their own toggles.

## Work with floors

The floor-layer sidebar lets you select a floor, add a blank floor, duplicate the active floor, rename it, show or hide it, lock it, change its opacity, reorder it, or delete it. A document always keeps at least one floor. Floor changes support Undo and Redo.

All floors share the same drawing coordinates. To trace an upper storey, set **Floor 1** to **25% opacity**, lock it, and select **Floor 2**. Keep Floor 1 visible as a reference while drawing Floor 2. Edits affect only the active floor; a hidden or locked active floor cannot have its walls or openings edited. Its layer controls remain available so you can show it or unlock it again. Units are an app preference shared across floors.

Saving preserves every floor, its geometry and layer settings, and the selected floor in one file. Older single-floor `.quickplan` files open automatically as a single floor; the next save writes the version-1 layered document format.

**SVG export includes the active floor only.** Other visible floors used as references are excluded. Check the active floor name before exporting. Exports use a **1:50 drawing scale** when printed at **100% / actual size**. Dimension labels show real wall measurements in millimetres. Printer scaling such as “fit to page” changes the drawing scale.

## Build and test

On macOS:

```sh
swift test
swift build --product QuickPlan
./scripts/build-app.sh
```

The geometry and document model live in the platform-independent `BlueprintCore` library. On Linux with a compatible Swift toolchain, run its tests with:

```sh
swift test --filter BlueprintCoreTests
```

The SwiftUI interface and `QuickPlanTests` require macOS and cannot run on Linux. Core model tests have been exercised on Linux; the native app build and store tests still require a Mac. The macOS CI workflow is configured to build and test the package and produce a zipped application bundle; a successful CI run has not yet been verified.

Use [the macOS checklist](docs/MACOS_CHECKLIST.md) to verify the native drawing, selection, guides, rotation, floor layers, units, document, and export workflows.

## Project layout

- `Sources/BlueprintCore`: measured geometry, walls, openings, floor layers, document validation, clipboard transforms, and smart-guide calculations.
- `Sources/QuickPlan`: macOS interface, canvas, layer controls, rotation popover, file handling, and export.
- `Tests/BlueprintCoreTests`: geometry, units, layers, clipboard/rotation, guides, and export tests.
- `Tests/QuickPlanTests`: macOS editor-state tests.
- `Examples`: an editable starter plan and its SVG export.
- `scripts`: local launch and application packaging helpers.

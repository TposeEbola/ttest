# QuickPlan

A small native macOS app for quick, measured 2D house plans. The editor uses a black-and-white canvas with blue alignment guides, precise wall dimensions, an object library, and floor layers for multi-storey designs. Drawing stays exclusively in 2D.

## What you can do

- Draw connected walls with endpoint snapping. Grid snapping and right-angle alignment are optional, so you can draw freely.
- Use **Pan** to move the canvas, and **Select** to drag walls, wall groups, doors, windows, or placed objects.
- Set a default wall thickness or enter a custom thickness for an individual wall.
- Select and edit wall coordinates, length, and thickness. Moving a shared corner keeps connected walls together.
- Shift-click to select multiple walls, openings, or objects, copy and paste items between floors, and rotate selections with a circular angle control.
- Use blue smart guides for common angles and matching measurements, or turn them off for free drawing.
- Place doors and windows on walls using common real-world width and height presets, or enter custom measurements.
- Furnish a plan with **Bedroom**, **Bathroom**, **Miscellaneous**, **Kitchen**, **Character**, **Lights**, **Office**, **Living Room**, and **Staircase** presets. Edit each object's name, position, size, and rotation.
- Draw a **Rectangle**, **Circle**, **Ellipse**, **Triangle**, or **Line**, with live dimensions while placing it. Circles show their diameter.
- Edit opening measurements and position. Openings must fit on their wall without overlapping.
- Rotate a door's swing around its hinge, or flip its hinge and swing direction while its opening stays in the wall.
- Measure between inside wall faces, then offset and place the dimension line with a third click.
- See wall lengths while drawing; keep only the explicit measurements you place in the finished drawing.
- Trace a closed room or building outline with **Area** to calculate square footage, or square metres in metric mode.
- Keep multiple floors in one file, with Photoshop-style layer selection, visibility, locking, opacity, and stacking order.
- Expand a floor to find and select its individual walls, objects, shapes, and saved areas.
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
2. Choose **Pan** to drag the canvas. Choose **Select** to inspect or drag drawing items; dragging empty space with Select leaves the canvas in place.
3. Open **Objects** to choose a door or window and its dimensions, then click a wall to place it. For furniture and other symbols, choose a category and preset, adjust its width and depth if needed, then click the canvas to stamp it.
4. In **Draw**, choose a basic shape. Click two opposite corners for a rectangle, ellipse, or triangle; click the centre then an edge for a circle; click two endpoints for a line. Live dimensions disappear after placement. Press Escape to cancel an unfinished shape.
5. Choose **Measure**, click the first and second points, then move the pointer to position the dimension line and click a third time to place it. A horizontal span lets you move the line up or down; a vertical span lets you move it left or right. Near a wall, the first two points snap to its face so you can measure a room's inside clearance.
6. Choose **Area** to trace an inside room boundary or outside building boundary. After at least three corners, click the starting point or press Return to close and save the outline. Escape cancels an unfinished trace.
7. Add floor layers as needed, then save the whole plan as a `.quickplan` document. Export SVG when you need a portable vector drawing of the active floor.

Open the visible **Settings** button or **QuickPlan → Settings…** (**⌘,**) to choose feet/inches or millimetres. Wall, opening, object, and shape inspector fields use the same setting: feet/inches fields show values such as `20' 0"`, and switching to millimetres shows `6096` for that same length. Measurement fields accept explicit entries such as `12' 6"`, `30in`, `30 1/2in`, and `762mm`. Plain numbers mean inches in feet/inches mode and millimetres in metric mode. The plan stores geometry in millimetres to preserve its measurements when you switch.

For a fun extra, choose **McChickens 🍔** in Display Units. QuickPlan defines **1 McChicken = exactly 4 inches = 101.6 mm**; this is an app unit, not a claim about a real burger's size. Length labels and editable fields use McChicken counts, plain numbers mean those counts, and areas use **McChickens²**. For example, `3` means **304.8 mm**, and **1 McChicken² = 10,322.56 mm²**. The selected grid step is one McChicken. Switching units changes the display and input scale without resizing the drawing or adding undo history. SVG exports keep actual millimetres and square-foot area labels.

The live length shown while drawing a wall measures its **centre line**. Thickness extends equally on either side. That automatic label disappears when the wall is placed; use **Measure** for a dimension you want to keep. Vertical length labels read upward along the wall or dimension line, while horizontal and diagonal labels follow their span. **Orthogonal walls**, **Snap to grid**, and **Smart guides** are separate drawing aids. Turn off the aids you do not want for free placement.

For a starting example, open [Examples/Starter.quickplan](Examples/Starter.quickplan). Its exported drawing is [Examples/Starter.svg](Examples/Starter.svg).

For a layered example, open [Examples/TwoFloors.quickplan](Examples/TwoFloors.quickplan). It has an editable second floor over a locked ground floor at 25% opacity.

For the object library, open [Examples/FurnishedHome.quickplan](Examples/FurnishedHome.quickplan). It contains measured furnishings from all nine categories and a hidden Shapes floor you can show separately. [Its SVG export](Examples/FurnishedHome.svg) previews the furnished floor.

For room measurements and square footage, open [Examples/MeasuredRoom.quickplan](Examples/MeasuredRoom.quickplan). Its inside dimensions are 19′ 6″ × 14′ 6″, with a named area of 282.75 sq ft. [The SVG export](Examples/MeasuredRoom.svg) includes both distance and area annotations.

## Furnish and sketch

The object library offers common starting sizes: beds and wardrobes; bathroom fixtures; storage, plants, rugs, and a car; kitchen appliances and tables; people and a wheelchair; lights; office furniture; living-room furniture; and straight or spiral stair symbols. Presets are generic layout aids rather than exact product models. Match their editable dimensions to the actual product you plan to use. Stairs are schematic plan symbols; the app does not calculate or validate stair rise, run, or code compliance.

After choosing a preset, move the pointer over the canvas to preview its footprint and width × depth, then click to place it. You can place additional copies while that tool remains active. Choose **Select** to move a placed object or edit its name, position, dimensions, and rotation in the inspector. Circles use a linked diameter; lines use length. The circular rotation control also works for objects and mixed selections.

Basic shapes appear under **Draw**. Rectangles, ellipses, and triangles use the box between two clicks. A circle's first click sets its centre and the second sets its radius; its live **Ø** label reports the full diameter. A line uses two endpoints and displays its length. These placement labels disappear after committing, keeping the finished plan clean; add **Measure** annotations for dimensions you want to retain. Objects and shapes appear under their floor in the layer list and are saved and exported with that floor.

## Select, copy, and rotate

With the select tool, **Shift-click** walls, openings, or objects to add or remove them from the selection. Use **⌘C** and **⌘V** to copy and paste through the system clipboard, on the same floor or after selecting another floor. Copied walls include their attached doors and windows. Pasted items have independent identities, so editing a copy leaves the original unchanged.

Drag a selected wall or group to move it. Attached openings follow their walls, and shared corners remain connected by moving adjoining endpoints. Adjoining walls can change length, so an edit is rejected if an attached opening would no longer fit. Dragging a door or window slides it along its wall; dragging it near another wall can attach it there. Openings must fit without overlap. A drag previews the change, commits as one undoable edit, and can be cancelled with Escape.

Use the separate **Pan** tool to move around the drawing without changing geometry. Select does not pan when you drag empty canvas space.

To zoom, pinch on a trackpad or scroll vertically over the canvas with a mouse wheel or trackpad. Zoom stays anchored to the gesture's location, so the point under the pointer remains in place. The toolbar's zoom buttons and Fit control remain available. Scrolling over a sidebar continues to scroll that sidebar, and zoom stops at its minimum and maximum limits.

Normal Paste offsets copied selections by **12 inches** on both axes, increasing the offset on repeated pastes so copies remain distinct. Use **Paste in Place** (**⇧⌘V**) to retain the source coordinates—useful for aligning copied geometry on another floor.

To paste a door or window without its wall, select a valid destination wall before pasting. The opening must fit there without overlapping existing openings. Rotating a wall carries its attached doors and windows with it.

Choose **Rotate** for selected walls, objects, or a group. Drag the handle on the circular popover to preview rotation with a live degree readout, or type an angle. **Apply rotation** commits the preview as one undoable edit; **Cancel** leaves the plan unchanged.

Unselected walls stay in place when you rotate a selection; select all adjoining walls that you want to rotate together.

Select a door to rotate its leaf and swing around its hinge using the circular rotation control. **Flip left / right** changes which jamb holds the hinge; **Flip in / out** changes the side on which the door opens. The wall and opening cutout stay in place. Windows keep their orientation relative to their host wall.

Blue **Smart guides** help align walls at common **45° increments**, including **90°** and **180°**, and match existing wall lengths or grid measurements. During rotation, an angle guide aligns the primary wall or object's final heading on the plan; the rotation value is the change from its starting angle. Disable Smart guides in the Draw sidebar or Settings when you want an unsnapped angle. Grid snapping and orthogonal alignment have their own toggles.

## Measure a room

Choose **Measure** and click the inside face of one wall, then the opposite inside face. These two clicks fix the measured endpoints. Move the pointer perpendicular to the span to position the dimension line, then click a third time to save it. For a horizontal measurement the line moves up or down; for a vertical measurement it moves left or right. Moving the line does not change its endpoints or measured distance. Press Escape, change tools, or change floors to cancel an unfinished dimension.

The annotation shows the distance between the first two points in the current display units. Wall-face snapping accounts for thickness: between walls with centre lines 20 feet apart and a thickness of 6 inches each, the inside clearance is **19 feet 6 inches** (**5943.6 mm**). Extension lines connect the original points to the offset dimension line. Vertical text reads bottom-to-top, facing left, regardless of which endpoint you chose first.

Measurements belong to the active floor. Select a measurement at its placed line or label to edit its endpoints and **Offset**, or delete it. The third click creates one undoable edit; moving the preview creates none. Explicit measurements remain visible and appear in that floor's SVG export, while automatic wall-length labels appear only during drawing. Saved files retain the offset; older annotations open with zero offset. Measurement endpoints stay where you placed them, so moving a wall does not automatically move an existing annotation.

## Calculate square footage

Choose **Area** and click around the boundary you want to measure. Trace the inside wall faces for usable room area, or the outside wall faces for an exterior footprint. Near wall corners, snapping uses the intersections of the chosen wall faces so wall thickness is included in the boundary you trace. After at least three corners, click the first point or press Return to close the polygon. Press Escape to cancel an unfinished trace.

The closed outline shows its area in **square feet** by default. Switching display units to metric changes area labels to **square metres**, while leaving the outline unchanged. A 20-by-15-foot centre-line rectangle with 6-inch walls has an inside face area of **282.75 sq ft** (19.5 × 14.5 feet) and an outside face area of **317.75 sq ft** (20.5 × 15.5 feet).

Saved areas appear beneath their floor in the layer list, with a name and area value. Select an area to rename or delete it in the inspector. Its closed boundary and label save in the `.quickplan` document and appear in that floor's SVG export. Like distance annotations, an area keeps the points you traced; moving walls later does not automatically reshape it. Use **Measure** for a distance between two points and **Area** for the surface enclosed by a closed outline.

## Work with floors

The floor-layer sidebar lets you select a floor, add a blank floor, duplicate the active floor, rename it, show or hide it, lock it, change its opacity, reorder it, or delete it. A document always keeps at least one floor. Floor changes support Undo and Redo.

Use the disclosure arrow beside a floor to expand its wall, object, shape, and saved-area list. Clicking an item in the list selects it on that floor and opens its inspector. Objects and shapes show their names and dimensions; each saved area shows its name and current square-foot or square-metre value. This gives each floor a folder-like outline while keeping all geometry in the same document.

All floors share the same drawing coordinates. To trace an upper storey, set **Floor 1** to **25% opacity**, lock it, and select **Floor 2**. Keep Floor 1 visible as a reference while drawing Floor 2. Edits affect only the active floor; a hidden or locked active floor cannot have its drawing content edited. Its layer controls remain available so you can show it or unlock it again. Units are an app preference shared across floors.

Saving preserves every floor, its geometry, objects, shapes, distance and area annotations, layer settings, and the selected floor in one file. Older single-floor `.quickplan` files open automatically as a single floor; the next save writes the version-1 layered document format. Files saved before objects or annotations were added open with empty collections for those additions and retain their existing geometry.

**SVG export includes the active floor only.** Other visible floors used as references are excluded. Check the active floor name before exporting. Exports use a **1:50 drawing scale** when printed at **100% / actual size**. Only explicit measurement annotations are exported, with their saved offsets and extension lines; automatic wall-length labels are omitted. Their labels show actual measured distances in millimetres. Printer scaling such as “fit to page” changes the drawing scale.

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

Use [the macOS checklist](docs/MACOS_CHECKLIST.md) to verify the native drawing, object library, shape placement, panning, dragging, distance and area measurements, selection, guides, rotation, floor layers, units, document, and export workflows. The latest interaction changes still need native macOS verification.

## Project layout

- `Sources/BlueprintCore`: measured geometry, walls, openings, floor layers, document validation, clipboard transforms, and smart-guide calculations.
- `Sources/QuickPlan`: macOS interface, canvas, layer controls, rotation popover, file handling, and export.
- `Tests/BlueprintCoreTests`: geometry, units, layers, clipboard/rotation, guides, and export tests.
- `Tests/QuickPlanTests`: macOS editor-state tests.
- `Examples`: an editable starter plan and its SVG export.
- `scripts`: local launch and application packaging helpers.

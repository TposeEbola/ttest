# macOS verification

Run on macOS 14 or later with Xcode 15 or later. These checks are pending native verification; Linux core tests do not validate SwiftUI behavior.

## Build

- [ ] Run `swift test` and confirm both core and macOS store tests execute successfully.
- [ ] Run `./scripts/build-app.sh`, then `open dist/QuickPlan.app`. Confirm the black-and-white editor opens without errors.

## Draw and edit

- [ ] Start a new plan. Draw three connected walls by clicking successive corners. Press Escape, then start a separate wall and confirm it does not extend the previous chain.
- [ ] Disable **Orthogonal walls**, **Snap to grid**, and **Smart guides**. Draw a visibly angled wall; confirm it retains that angle. Re-enable each aid and confirm it affects subsequent placement independently.
- [ ] Select a connected wall. Change a shared endpoint in the inspector and apply it. Confirm the adjoining wall stays connected. Change length and thickness and check the dimensions and wall outline.
- [ ] Open **Objects**, choose a common door preset, and place it on a wall. Repeat for a window. Select each opening and change its width, height, and position.
- [ ] Try an opening that crosses a wall end or overlaps another opening. Confirm the editor explains the problem and preserves the previous valid plan.

## Selection and clipboard

- [ ] Use the select tool to click a wall, then Shift-click other walls and openings. Confirm each Shift-click adds or removes that item without clearing the rest of the selection.
- [ ] Select a wall with attached doors or windows, copy (**⌘C**), and paste (**⌘V**). Confirm attached openings accompany the copied wall. Edit the copy and confirm the original stays unchanged; undo and redo the paste as one edit.
- [ ] Paste the same copied wall group several times. Confirm normal Paste offsets copies in successive **12-inch** steps on both axes rather than stacking them in the same location.
- [ ] Copy a wall group, select another visible unlocked floor, and paste. Confirm all copied geometry and opening dimensions survive, with independent item identities and correct opening-to-wall attachments.
- [ ] Copy a wall group, select another floor, and use **Paste in Place** (**⇧⌘V**). Confirm its coordinates match the source exactly and the source remains independent. Toggle floor visibility to check alignment.
- [ ] Copy only a door or window, select a suitable destination wall, and paste. Confirm it attaches there. Try a missing, too-short, or occupied destination and confirm rejection preserves the previous plan.
- [ ] Copy and paste text inside a measurement field. Confirm normal text editing works without duplicating drawing items. Try pasting items onto a hidden or locked active floor and confirm content is unchanged.

## Guides and rotation

- [ ] With **Smart guides** enabled and orthogonal alignment disabled, draw near 45°, 90°, and 180°. Confirm blue angle guides and the live measurement readout appear, and the placed wall matches the guided angle.
- [ ] Draw near an existing wall’s length and near a grid measurement. Confirm the matching-length or measurement guide reflects the wall that will be placed. Disable Smart guides in the sidebar and Settings and confirm the blue guides and their snapping stop; grid and orthogonal toggles remain independent.
- [ ] Select a wall group containing doors or windows and open **Rotate**. Drag the circular handle and confirm the live degree readout and canvas preview agree; attached openings move with their walls. Type an angle and confirm the preview updates. Apply once, then undo once and confirm the entire group returns; redo restores the rotation.
- [ ] Preview several rotation angles, then choose **Cancel**. Confirm the plan and undo history are unchanged. Select only an opening and confirm independent rotation is unavailable.
- [ ] Start with a wall at an arbitrary heading, such as 17°. With Smart guides enabled, rotate it toward a 45° final heading. Confirm the guide aligns the wall to 45° on the plan and the rotation change is about 28°, rather than applying a 45° change. Disable Smart guides and confirm an exact unsnapped typed angle is retained.

## Floor layers

- [ ] Add a blank floor, select it, and draw a distinctive wall. Switch floors and confirm only the selected floor’s content can be edited. Duplicate a floor and confirm editing the copy leaves the original unchanged.
- [ ] Rename floors, reorder them, toggle visibility, and change opacity. Confirm the sidebar and canvas agree. Delete a floor, undo the deletion, and confirm its walls, openings, and layer settings return. Confirm the final remaining floor cannot be deleted.
- [ ] Set Floor 1 to **25% opacity**, lock it, and leave it visible. Make Floor 2 active and trace against Floor 1. Confirm their coordinates align and the locked reference is not selectable for content editing.
- [ ] Make the active floor locked, then hidden. In each state, try drawing, editing a wall or opening, and deleting content. Confirm geometry remains unchanged and the editor explains why. Confirm layer controls still let you unlock or show it.
- [ ] Overlap floors with walls, doors, and windows. Vary the upper floor’s opacity and visibility. Confirm each floor fades as one group, openings stay clear, reference-floor geometry remains visible through gaps, and one floor does not erase another.
- [ ] Drag the opacity slider through several values in one gesture. Undo once and confirm it returns to the value before the drag; redo once and confirm the final dragged value returns.

## Units

- [ ] Confirm a fresh app preference defaults to feet and inches. Open **QuickPlan → Settings…** (**⌘,**) and switch to millimetres. Confirm canvas labels, inspector values, and input units update.
- [ ] Enter `12' 6"` as a suitable wall length. Switch to millimetres and confirm **3810 mm**; switch back and confirm **12′ 6″**. Changing units must not change the geometry.
- [ ] Try `30in`, `30 1/2in`, and `762mm` in a valid dimension field. Confirm the respective millimetre values are **762**, **774.7**, and **762**. Use explicit units when checking conversions.

## Documents and history

- [ ] Open `Examples/Starter.quickplan`; confirm its walls, door, and window appear. Save a copy, edit it, save, and reopen it. Confirm geometry and opening measurements survive.
- [ ] Save a document with multiple floors, distinct geometry, names, stacking order, visibility, locks, and opacity values. Reopen it and confirm all floor contents and settings, including the active floor, are preserved.
- [ ] Open an older single-floor `.quickplan` document. Confirm it becomes one editable floor. Save and reopen it, confirming the version-1 layered file retains the original geometry and measurements.
- [ ] Make an edit, then Undo (**⌘Z**) and Redo (**⇧⌘Z**). Confirm both drawing and inspector agree. Undo a wall deletion and confirm its attached openings return.
- [ ] With unsaved edits, close the window and choose Cancel. Confirm the window and changes remain. Repeat with Quit (**⌘Q**) and Cancel. Confirm Save writes changes before closing and Discard permits closing without saving.

## Export

- [ ] Show at least two floors, choose one as active, and export SVG. Confirm the export label/status identifies that floor. Open the SVG in a browser or vector viewer and confirm it contains only that floor’s walls, dimensions, door swings, and windows; visible reference floors must be excluded.
- [ ] Print at **100% / actual size**, with “fit to page” disabled. Confirm the **1:50** scale: a **5000 mm** centre-line dimension occupies **100 mm** on paper. SVG dimension labels remain actual millimetres regardless of editor display units.

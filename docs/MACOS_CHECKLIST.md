# macOS verification

Run on macOS 14 or later with Xcode 15 or later. These checks are pending native verification; Linux core tests do not validate SwiftUI behavior.

## Build

- [ ] Run `swift test` and confirm both core and macOS store tests execute successfully.
- [ ] Run `./scripts/build-app.sh`, then `open dist/QuickPlan.app`. Confirm the black-and-white editor opens without errors.

## Draw and edit

- [ ] Start a new plan. Draw three connected walls by clicking successive corners. Press Escape, then start a separate wall and confirm it does not extend the previous chain.
- [ ] Choose **Pan** and drag both empty space and visible walls. Confirm only the canvas position changes. Choose **Select** and drag empty space; confirm the canvas and geometry stay in place.
- [ ] Pinch on a trackpad and scroll vertically over the canvas using a mouse wheel or trackpad. Confirm smooth zoom stays anchored to the gesture/pointer location without changing geometry or undo history. Keep zooming in both directions and confirm the limits remain stable and finite; then use Fit.
- [ ] Scroll over the Objects, wall-list, and inspector panels and confirm their contents scroll normally without zooming the drawing. Open a rotation popover and confirm wheel events there do not zoom the canvas. Horizontal-only wheel movement over the canvas must not trigger zoom.
- [ ] With Select, drag one wall and a Shift-selected wall group. Confirm the preview follows the pointer, the final movement creates one undo entry, and attached doors/windows follow. Check that adjoining unselected walls keep their shared corners connected by stretching to the moved endpoints.
- [ ] Begin a wall drag, press Escape, and confirm the geometry and undo history return to their pre-drag state. Try a move that would make an adjoining opening no longer fit and confirm atomic rejection leaves the whole plan unchanged.
- [ ] Disable **Orthogonal walls**, **Snap to grid**, and **Smart guides**. Draw a visibly angled wall; confirm it retains that angle. Re-enable each aid and confirm it affects subsequent placement independently.
- [ ] Select a connected wall. Change a shared endpoint in the inspector and apply it. Confirm the adjoining wall stays connected. Change length and thickness and check the dimensions and wall outline.
- [ ] Open **Objects**, choose a common door preset, and place it on a wall. Repeat for a window. Select each opening and change its width, height, and position.
- [ ] Try an opening that crosses a wall end or overlaps another opening. Confirm the editor explains the problem and preserves the previous valid plan.
- [ ] With Select, drag a door along its wall and onto a nearby different wall. Repeat with a window. Confirm the new host, position, and inspector agree, and that too-short walls, overlaps, and wall-end crossings are rejected without partially moving the item. Undo each successful drag once.

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
- [ ] Preview several rotation angles, then choose **Cancel**. Confirm the plan and undo history are unchanged. Select a door and confirm its leaf/swing can rotate around its hinge without moving its wall or cutout; a window remains oriented with its host wall.
- [ ] Use a door's circular control and exact angle input for positive and negative swing angles. Check blue angle guides, Apply/Undo/Redo, and Cancel. Use **Flip left / right** and **Flip in / out**, confirm the corresponding jamb/opening side changes, and verify save/reopen retains both choices.
- [ ] Start with a wall at an arbitrary heading, such as 17°. With Smart guides enabled, rotate it toward a 45° final heading. Confirm the guide aligns the wall to 45° on the plan and the rotation change is about 28°, rather than applying a 45° change. Disable Smart guides and confirm an exact unsnapped typed angle is retained.

## Floor layers

- [ ] Add a blank floor, select it, and draw a distinctive wall. Switch floors and confirm only the selected floor’s content can be edited. Duplicate a floor and confirm editing the copy leaves the original unchanged.
- [ ] Expand each floor's disclosure arrow. Confirm individual walls appear under their own floor with current measurements. Click a child wall, including one on a different floor, and confirm the canvas selection and wall inspector match. Add or delete walls and confirm the child list updates.
- [ ] Rename floors, reorder them, toggle visibility, and change opacity. Confirm the sidebar and canvas agree. Delete a floor, undo the deletion, and confirm its walls, openings, and layer settings return. Confirm the final remaining floor cannot be deleted.
- [ ] Set Floor 1 to **25% opacity**, lock it, and leave it visible. Make Floor 2 active and trace against Floor 1. Confirm their coordinates align and the locked reference is not selectable for content editing.
- [ ] Make the active floor locked, then hidden. In each state, try drawing, editing a wall or opening, and deleting content. Confirm geometry remains unchanged and the editor explains why. Confirm layer controls still let you unlock or show it.
- [ ] Repeat locked/hidden checks for wall and opening drags, door rotation, child-wall selection, and adding/editing/deleting measurement annotations. Confirm these content actions cannot bypass the layer protection.
- [ ] Expand a floor containing saved areas. Confirm each area's name and square-foot value appear under that floor. Select one and confirm the correct outline and inspector are active; switch units and confirm its layer-list value changes to square metres.
- [ ] Overlap floors with walls, doors, and windows. Vary the upper floor’s opacity and visibility. Confirm each floor fades as one group, openings stay clear, reference-floor geometry remains visible through gaps, and one floor does not erase another.
- [ ] Drag the opacity slider through several values in one gesture. Undo once and confirm it returns to the value before the drag; redo once and confirm the final dragged value returns.

## Units

- [ ] Confirm a fresh app preference defaults to feet and inches. Open **QuickPlan → Settings…** (**⌘,**) and switch to millimetres. Confirm canvas labels, inspector values, and input units update.
- [ ] Select a 20-foot wall. Confirm the editable length field shows `20' 0"`, not only `240"`. Switch display units to millimetres and confirm the same field becomes `6096`; switch back and confirm the feet-and-inches form returns without changing geometry. Repeat for coordinates, thickness, door/window fields, and measurement endpoints.
- [ ] Enter `12' 6"` as a suitable wall length. Switch to millimetres and confirm **3810 mm**; switch back and confirm **12′ 6″**. Changing units must not change the geometry.
- [ ] Try `30in`, `30 1/2in`, and `762mm` in a valid dimension field. Confirm the respective millimetre values are **762**, **774.7**, and **762**. Use explicit units when checking conversions.

## Room measurements

- [ ] Draw parallel walls with centre lines 20 feet (**6096 mm**) apart and each 6 inches (**152.4 mm**) thick. Choose **Measure** and click their facing inside surfaces. Confirm the saved annotation reads **19 feet 6 inches** (**5943.6 mm**), rather than the centre-line distance.
- [ ] Place a free-point measurement away from walls and a measurement between angled wall faces. Confirm the preview and committed value agree, and Escape cancels an unfinished annotation without adding it.
- [ ] Select an annotation, edit its endpoints, and delete it. Undo/redo each action and confirm it affects only that measurement on the active floor.
- [ ] Move a measured wall and confirm the existing annotation stays at its saved endpoints. Save/reopen the document and confirm annotations and precise endpoints survive.

## Area and square footage

- [ ] Trace the inside wall faces of a 20-by-15-foot centre-line rectangle with 6-inch walls. Confirm corner snapping reaches the face intersections, the closed boundary is 19.5 × 14.5 feet, and its area is **282.75 sq ft**. Trace its outside faces separately and confirm **317.75 sq ft** for 20.5 × 15.5 feet.
- [ ] Close one trace by clicking its starting point and another with Return after at least three corners. Confirm each action saves exactly one closed area. Press Escape during a third trace and confirm no area or undo entry is added.
- [ ] Trace a valid concave room and confirm it saves with the correct area. Try a self-crossing polygon and a trace with fewer than three distinct corners; confirm rejection leaves the saved plan and undo history unchanged.
- [ ] Select an area from its floor's child list or from the canvas. Rename it in the inspector, delete it, and undo/redo both actions. Confirm other floors and area outlines are unchanged.
- [ ] Switch display units from feet/inches to millimetres. Confirm canvas, inspector, and layer-list area values change from square feet to square metres without changing vertices. Move a boundary wall and confirm the saved static trace remains in place.
- [ ] Save and reopen a multi-floor file with named areas. Confirm names, vertices, closed boundaries, labels, and active-floor ownership survive. On a locked or hidden active floor, try creating, renaming, and deleting an area; confirm protection remains effective.

## Documents and history

- [ ] Open `Examples/Starter.quickplan`; confirm its walls, door, and window appear. Save a copy, edit it, save, and reopen it. Confirm geometry and opening measurements survive.
- [ ] Save a document with multiple floors, distinct geometry, names, stacking order, visibility, locks, and opacity values. Reopen it and confirm all floor contents and settings, including the active floor, are preserved.
- [ ] Open an older single-floor `.quickplan` document. Confirm it becomes one editable floor. Save and reopen it, confirming the version-1 layered file retains the original geometry and measurements.
- [ ] Open files from before the `dimensions`, `doorSwingDegrees`, and `hingeAtEnd` fields existed. Confirm they load with no measurement annotations and the original default door swing. Save/reopen after adding an annotation and rotating a door; confirm the new fields survive without changing other objects.
- [ ] Open a file from before saved areas were supported. Confirm it opens with no saved-area outlines and retains all existing walls, openings, floors, and distance measurements.
- [ ] Make an edit, then Undo (**⌘Z**) and Redo (**⇧⌘Z**). Confirm both drawing and inspector agree. Undo a wall deletion and confirm its attached openings return.
- [ ] With unsaved edits, close the window and choose Cancel. Confirm the window and changes remain. Repeat with Quit (**⌘Q**) and Cancel. Confirm Save writes changes before closing and Discard permits closing without saving.

## Export

- [ ] Show at least two floors, choose one as active, and export SVG. Confirm the export label/status identifies that floor. Open the SVG in a browser or vector viewer and confirm it contains only that floor’s walls, dimensions, door swings, and windows; visible reference floors must be excluded. Include custom measurement annotations and flipped/rotated doors, and confirm their SVG geometry agrees with the canvas.
- [ ] Export a floor with named area outlines and confirm the SVG includes their closed boundaries and area labels. Areas belonging to other floors must be excluded, and moving walls must not alter the saved outline unexpectedly.
- [ ] Print at **100% / actual size**, with “fit to page” disabled. Confirm the **1:50** scale: a **5000 mm** centre-line dimension occupies **100 mm** on paper. SVG dimension labels remain actual millimetres regardless of editor display units.

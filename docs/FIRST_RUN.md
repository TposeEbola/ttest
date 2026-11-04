# Your first run in Xcode

QuickPlan is a Mac app. You need macOS 14 (Sonoma) or later and Xcode 15 or later. Xcode is Apple's free app for building and running Mac software. A paid Apple Developer account is not needed for this local run.

1. Check **Apple menu → About This Mac** for your macOS version.
2. Install **Xcode** from the Mac App Store. Choose a version compatible with your macOS. Open Xcode after installation, accept its license, and let its required components finish installing. Choose macOS support if it asks which platforms you need.
3. Download and expand the QuickPlan source ZIP in Finder. Keep the whole `QuickPlan` folder together; `Package.swift`, `Sources`, and `Examples` should be inside it.
4. In Xcode choose **File → Open…**, select `QuickPlan/Package.swift`, and click **Open**. You are opening an existing app; there is no need to create a new project.
5. Wait for Xcode to finish loading the package. In the top toolbar select the **QuickPlan** executable scheme and **My Mac** as the destination.
6. Click the triangular **Run** button at the top left, or press **Command-R**. Xcode builds the app, then opens its window. The first build can take longer than later ones.
7. In QuickPlan press **Command-O** and open `Examples/TwoFloors.quickplan` from the downloaded source folder. The ground floor is locked at 25% opacity, with a second floor ready for editing.

## First things to try

- Choose **Draw → Select** and click a wall to inspect it.
- Choose **Rotate selection…** to use the circular angle control. Apply keeps the rotation; Cancel discards the preview.
- Use **Shift-click** to select more than one wall, **Command-C** to copy, and **Command-V** to paste. **Shift-Command-V** pastes in place.
- In **Floors & Layers**, use **+** to add a floor. The eye, lock, and opacity controls affect the chosen floor.
- Click **Settings** to switch feet/inches to millimetres.

## If it does not start

- If Run is unavailable, wait for package loading to finish and confirm that the scheme is **QuickPlan** and the destination is **My Mac**.
- If Xcode asks for command-line tools, open **Xcode → Settings → Locations** and choose your installed Xcode under **Command Line Tools**.
- If a build fails, open the **Issue navigator** with **Command-5**, expand the first red error, and copy its exact message. Include the Xcode version (**Xcode → About Xcode**) and macOS version when asking for help.
- You can stop the running app using Xcode's square **Stop** button. Run it again with **Command-R**.

The core geometry and file tests pass on Linux. Native macOS compilation and interaction checks have not yet been run in the cloud workspace; an Xcode build error needs investigation rather than a signing subscription.

## Build a standalone app later

After the Xcode run works, the repository's `scripts/build-app.sh` can create `dist/QuickPlan.app`. See the main README for that optional step. It is not needed for the first run.

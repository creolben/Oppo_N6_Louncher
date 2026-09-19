# ColorOS 16 / Android 16 launcher research — prioritised findings

Verified directly against official Android docs and AOSP source (2026-09). Three background
research subagents (Android launcher APIs, OPPO/ColorOS, Flutter) were **still running** when the
wrap-up request arrived; their findings are **not** included here.

Legend: **[V]** verified with URL · **[C]** community-reported with URL · **[?]** could not verify /
inference, flagged inline.

---

## 1. Fold / hinge state detection — exact API entry points

**[V] Use Jetpack WindowManager. This is the only public fold API I could confirm exists.**

- Artifact `androidx.window:window`, current **stable 1.5.1** (page also lists 1.6.0-alpha05).
  `implementation "androidx.window:window:1.5.1"`; Java-friendly `androidx.window:window-java:1.5.1`.
  [WindowManager releases](https://developer.android.com/jetpack/androidx/releases/window)
- **Entry point (Flow):** `WindowInfoTracker.getOrCreate(context)` → tracker instance;
  `windowLayoutInfo(activity)` → `Flow<WindowLayoutInfo>` (also overload `windowLayoutInfo(context)`).
  [WindowInfoTracker reference](https://developer.android.com/reference/androidx/window/layout/WindowInfoTracker)
- **Entry point (one-shot, added 1.5.0):** `getCurrentWindowLayoutInfo(context)` → `WindowLayoutInfo`
  directly, no Flow. Same reference page, marked "Added in 1.5.0".
- **Posture object:** `DisplayFeature` subtypes from `WindowLayoutInfo`. `FoldingFeature` provides
  `getBounds()` (Rect, window coordinate space), `getState()` (`State.FLAT` / `State.HALF_OPENED`),
  `getOrientation()` (`Orientation.HORIZONTAL` / `Orientation.VERTICAL`),
  `getOcclusionType()` (`OcclusionType.OCCLUSION_FULL` / `OCCLUSION_NONE`), `isSeparating()`.
  [FoldingFeature](https://developer.android.com/reference/androidx/window/layout/FoldingFeature) ·
  [DisplayFeature](https://developer.android.com/reference/androidx/window/layout/DisplayFeature)
- **Compose path:** `collectFoldingFeaturesAsState()` (Compose Material 3 Adaptive) → `State<List<FoldingFeature>>`.
  [Make your app fold aware](https://developer.android.com/develop/adaptive-apps/guides/foldables/make-your-app-fold-aware)

**Corrections — do NOT use these names:**

- **[?]** No public platform class `android.hardware.display.DisplayFeature` or `android.view.DisplayFeature`
  could be verified. Both reference URLs return **HTTP 404**; and the `android.hardware.display` package
  summary lists DisplayManager, DeviceProductInfo, DisplayTopology, HdrConversionMode, VirtualDisplay,
  VirtualDisplayConfig — **no DisplayFeature**.
  [package summary](https://developer.android.com/reference/android/hardware/display/package-summary)
- **[?]** `WindowInsets.getDisplayFeature()` could not be verified. The WindowInsets reference page has
  `getDisplayCutout` and `getDisplayShape` but **zero** occurrences of "DisplayFeature".
  [WindowInsets](https://developer.android.com/reference/android/view/WindowInsets)
- **[?]** Hinge-angle sensor (`android.sensor.hinge_angle`, type 36) was **not** re-researched per your
  instruction, and I did not independently confirm the exact `Sensor` constant identifier.

**[?] Inference:** Jetpack is the supported abstraction; per-device fold values arrive through the OEM's
WindowManager extension implementation, which is why fold behaviour varies by OEM.

---

## 2. `AppWidgetHost` by a non-system, non-privileged third-party launcher (Android 12+)

**[V] The official host guide documents an ordinary app-level flow:**

- Declare `<uses-permission android:name="android.permission.BIND_APPWIDGET" />`; the guide then says
  *"this is just the first step. At runtime, the user must explicitly grant permission to your app to let
  it add a widget to the host."*
- Consent dialog: `Intent(AppWidgetManager.ACTION_APPWIDGET_BIND)` with extras
  `AppWidgetManager.EXTRA_APPWIDGET_ID`, `EXTRA_APPWIDGET_PROVIDER`, `EXTRA_APPWIDGET_OPTIONS`,
  started via `startActivityForResult`.
- Host flow: `allocateAppWidgetId()` to obtain an id; test with `bindAppWidgetIdIfAllowed()`.
  [Build a widget host](https://developer.android.com/develop/ui/views/appwidgets/host)

**[V] …and the same permission is signature|privileged, which contradicts the guide:**

- AOSP declares `android.permission.BIND_APPWIDGET` with
  `android:protectionLevel="signature|privileged"` — a normal third-party app cannot be granted it.
  [AOSP core/res/AndroidManifest.xml](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/res/AndroidManifest.xml)
- The permission reference says: *"Allows an application to tell the AppWidget service which application
  can access AppWidget's data… **Not for use by third-party applications.**"*
  [Manifest.permission](https://developer.android.com/reference/android/Manifest.permission)
- `AppWidgetHost` API surface confirmed: `allocateAppWidgetId`, `startListening`, `stopListening`,
  `deleteAppWidgetId`, `createView`.
  [AppWidgetHost reference](https://developer.android.com/reference/android/appwidget/AppWidgetHost)

**Conflict + [?] inference:** the guide tells you to declare a permission whose protection level is
signature|privileged and which the reference says is not for third-party apps — so declaration alone is a
no-op. The operative mechanism for third-party launchers is the `ACTION_APPWIDGET_BIND` user-consent
dialog, where the system performs the bind on the host's behalf with user approval. This is consistent
with the on-device result (third-party launchers host widgets on ColorOS 16). I found **no** official
sentence stating "non-privileged apps may host widgets via user consent", so treat the mechanism as
strong inference backed by guide + AOSP + device behaviour.

---

## 3. OPPO public/partner SDK for foldable window features

**[V] OPPO publishes a public SDK — but it is a window / in-app split-screen capability, not a
"flex mode" or cover-screen API:**

- **WMUnit** ("窗口能力"): in-app split screen for third-party apps. Dependency
  `compileOnly 'com.oplus.ocs:wmunit:1.0.0'` (Maven Central). Public API includes
  `MultiWindowTrigger` (`getVersion()`, `isDeviceSupport(Context)`,
  `requestSwitchToSplitScreen(Activity, SplitScreenParams)`, `requestSwitchToFullScreen(Activity)`,
  `registerActivityMultiWindowAllowanceObserver(...)`, `unregisterActivityMultiWindowAllowanceObserver(...)`),
  `SplitScreenParams.Builder` (`setSelfSplit()`, `setLaunchIntent(Intent)`, `setLaunchPosition(int)`),
  `ActivityMultiWindowAllowance`, `ActivityMultiWindowAllowanceObserver`.
  Stated support: *"ColorOS13及以上版本的Find N系列折叠屏手机、OPPO APD平板设备"*
  (ColorOS 13+ Find N-series foldables and OPPO Pad).
  [OPPO-OpenPlatform/wmunit_demo](https://github.com/OPPO-OpenPlatform/wmunit_demo)
- Card/widget integration demo:
  [OPPO-OpenPlatform/cardwidgetsupport_android_demo](https://github.com/OPPO-OpenPlatform/cardwidgetsupport_android_demo)
- **Access restrictions [V]:** the WMUnit README binds use to the OPPO developer service agreement
  (open.oppomobile.com), forbids selling/transferring/sub-licensing the SDK, and states OPPO may terminate
  use and ban the developer account for violations — i.e. account/terms-gated.

**Could not verify:**

- **[?]** No official OPPO source for a published "Flex Mode"/"FlexForm" API, nor a cover-screen ("外屏")
  API for third-party apps. The OPPO community FlexForm thread is JS-rendered and returned only the site
  shell: <https://community.oppo.com/thread/1873141038802010121>
- **[?]** Whether a non-Chinese / independent developer can register and access WMUnit is unverified.
  `open.oppomobile.com` and `developers.oppomobile.com` are JS-rendered and yielded no readable doc text;
  Chinese-ID / mainland-account requirements could not be confirmed from an official page.
- **[?]** No verified public manifest flag or API for being listed in ColorOS cover-screen settings.

---

## 4. Does ColorOS revert / restrict the default HOME role?

**[V] Android platform:**

- Home role constant `RoleManager.ROLE_HOME` (`"android.app.role.HOME"`); request with
  `createRequestRoleIntent(String)` + `startActivityForResult`; probe with `isRoleAvailable(String)` /
  `isRoleHeld(String)`.
  [RoleManager](https://developer.android.com/reference/android/app/role/RoleManager)
- Shell command exists: `cmd package set-home-activity [--user USER_ID] TARGET-COMPONENT`
  (case `"set-home-activity"` → `runSetHomeActivity()`).
  [AOSP PackageManagerShellCommand.java](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/pm/PackageManagerShellCommand.java)

**[C] ColorOS setting path (third-party guide, not OPPO-official):**
Settings → App management → Default apps → Home app. The same guide states the phone *"keeps loading the
built-in interface after every reboot"* **until** the third-party launcher is explicitly set as the
default home app.
[TechBone: Oppo set default home launcher](https://www.techbone.net/oppo/smartphone/default-system-launcher)

**[C] Community reset reports exist but bodies were unreadable** (titles only — do not cite contents):
[OPPO community "Does ColorOS 15 not allow 3rd party launchers to work properly?"](https://community.oppo.com/thread/1863496605047455748)
(JS shell only) · [XDA "Nova Launcher Loses Default Status On Reboot"](https://xdaforums.com/t/nova-launcher-loses-default-status-on-reboot.4269325/)
(HTTP 403 bot challenge) · [XDA Find N5 CN Nova launcher lag](https://xdaforums.com/t/oppo-find-n5-pkh100-cn-replacing-default-launcher-with-nova-launcher-lag-when-swiping-up.4734316/)
(HTTP 403 bot challenge).

**[?]** No official OPPO/OnePlus document was found stating ColorOS 16 forcibly reverts a third-party
default launcher after reboot or OTA. Given the on-device result (Niagara/bitpit works), there is no
verified forced revert on this device.

---

## Local observation (this repo)

`android/app/src/main/AndroidManifest.xml` declares `MAIN` + `LAUNCHER` + `HOME` + `DEFAULT` in one
intent-filter (sufficient for the home role) but also sets `android:screenOrientation="portrait"` and
`android:resizeableActivity` is not declared — both work against foldable posture handling and Android
16 large-screen resizability expectations.

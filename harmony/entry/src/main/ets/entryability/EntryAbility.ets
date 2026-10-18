import native from 'libedgelink.so';
import { UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { pointer } from '@kit.InputKit';
export default class EntryAbility extends UIAbility {
 private windowFocused: boolean = false;
 private windowPaused: boolean = false;
 private inputWindowId: number = -1;
 private publishWindowInputState(): void {
  const active = this.windowFocused && !this.windowPaused;
  // Gate native keys and stop observation synchronously before the UI watcher runs.
  if (!active) {
   // The SDK automatically releases cursor confinement on focus loss. Keep the
   // native cache in sync even if a later UnlockCursor sees an inactive window.
   if (this.inputWindowId > 0) { native.input(`CURSORINACTIVE ${this.inputWindowId}`); }
   native.input('LOCALUI 1');
   try { pointer.setPointerVisibleSync(true); } catch (e) { /* Window may already be gone. */ }
  }
  AppStorage.setOrCreate('remoteInputWindowActive', active);
 }
 onCreate(want: Want): void {
  AppStorage.setOrCreate('storeProbeAddress',want.parameters?.['storeProbeAddress'] as string || '');
  AppStorage.setOrCreate('remoteInputWindowActive', false);
  AppStorage.setOrCreate('remoteSessionForeground', false);
  AppStorage.setOrCreate('diagnosticMode', '');
  AppStorage.setOrCreate('diagnosticTransport', '');
  AppStorage.setOrCreate('diagnosticBitrateKbps', want.parameters?.['testBitrateKbps'] as number || 0);
  AppStorage.setOrCreate('diagnosticFPS', want.parameters?.['fps'] as number || 60);
  AppStorage.setOrCreate('diagnosticResolution', typeof want.parameters?.['testResolution'] === 'number' ? want.parameters?.['testResolution'] as number : -1);
  AppStorage.setOrCreate('diagnosticCursorLock', want.parameters?.['cursorLock'] !== 0);
  AppStorage.setOrCreate('diagnosticSystemHover', want.parameters?.['systemHover'] !== 0);
  AppStorage.setOrCreate('diagnosticRelativeCursor', want.parameters?.['relativeCursor'] !== 0);
  AppStorage.setOrCreate('diagnosticNoFallback', want.parameters?.['noFallback'] === 1);
 }
 onNewWant(want: Want): void {
  AppStorage.setOrCreate('storeProbeAddress',want.parameters?.['storeProbeAddress'] as string || '');
  AppStorage.setOrCreate('diagnosticMode', '');
  AppStorage.setOrCreate('diagnosticTransport', '');
  AppStorage.setOrCreate('diagnosticBitrateKbps', want.parameters?.['testBitrateKbps'] as number || 0);
  AppStorage.setOrCreate('diagnosticFPS', want.parameters?.['fps'] as number || 60);
  AppStorage.setOrCreate('diagnosticResolution', typeof want.parameters?.['testResolution'] === 'number' ? want.parameters?.['testResolution'] as number : -1);
  AppStorage.setOrCreate('diagnosticCursorLock', want.parameters?.['cursorLock'] !== 0);
  AppStorage.setOrCreate('diagnosticSystemHover', want.parameters?.['systemHover'] !== 0);
  AppStorage.setOrCreate('diagnosticRelativeCursor', want.parameters?.['relativeCursor'] !== 0);
  AppStorage.setOrCreate('diagnosticNoFallback', want.parameters?.['noFallback'] === 1);
 }
 private saveLifecycle(event: string): void {
  try {
   const f = fileIo.openSync(`${this.context.filesDir}/ability-status.json`, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
   try { fileIo.writeSync(f.fd, JSON.stringify({ event: event, time: Date.now(), native: JSON.parse(native.stats()) })); } finally { fileIo.closeSync(f); }
  } catch (e) { hilog.error(0xED01, 'EdgeLinkLab', 'Unable to save lifecycle'); }
 }
 // Focus loss (including a local dialog) is not a hidden streaming window.
 onForeground(): void { AppStorage.setOrCreate('remoteSessionForeground', true); }
 onBackground(): void { AppStorage.setOrCreate('remoteSessionForeground', false);native.disconnect('ability_background');this.windowFocused = false;this.publishWindowInputState();this.saveLifecycle('background'); }
 onDestroy(): void { AppStorage.setOrCreate('remoteSessionForeground', false);this.windowFocused = false;this.publishWindowInputState();native.disconnect('ability_destroyed');native.availabilityStop();this.saveLifecycle('destroy'); }
 onWindowStageCreate(stage: window.WindowStage): void {
  const mainWindow = stage.getMainWindowSync();
  this.inputWindowId = mainWindow.getWindowProperties().id;
  AppStorage.setOrCreate<window.Window>('mainWindow', mainWindow);
  stage.on('windowStageEvent', (event: window.WindowStageEventType) => {
   if (event === window.WindowStageEventType.ACTIVE) { AppStorage.setOrCreate('remoteSessionForeground', true);this.windowFocused = true;this.publishWindowInputState(); }
   else if (event === window.WindowStageEventType.INACTIVE) { this.windowFocused = false;this.publishWindowInputState(); }
   else if (event === window.WindowStageEventType.PAUSED) { this.windowPaused = true;this.publishWindowInputState(); }
   else if (event === window.WindowStageEventType.RESUMED) { this.windowPaused = false;this.publishWindowInputState(); }
   else if (event === window.WindowStageEventType.HIDDEN) {
    AppStorage.setOrCreate('remoteSessionForeground', false);this.windowFocused = false;this.windowPaused = false;this.publishWindowInputState();native.disconnect('window_hidden');
   }
   this.saveLifecycle(`window_${event}`);
  });
  stage.loadContent('pages/Index').catch((e: Error) => hilog.error(0xED01, 'EdgeLinkLab', '%{public}s', e.message));
 }
}

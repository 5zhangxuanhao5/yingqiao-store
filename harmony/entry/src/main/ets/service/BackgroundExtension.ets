import native from 'libedgelink.so';
import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';

interface ExtensionSnapshot { running: boolean; backgroundRetainSupported?: boolean; sessionID?: number; stopReason?: string; }
// Ability lifecycle and page lifecycle share one owner. Serialize OS requests so
// End racing an outstanding grant cannot leak a continuous background task.
export class BackgroundExtension {
 private static desired: boolean = false;
 private static granted: boolean = false;
 private static changing: boolean = false;
 private static failed: boolean = false;
 private static context: common.UIAbilityContext | null = null;
 static resuming: boolean = false;
 static resumeUntil: number = 0;
 static parked(): boolean { return AppStorage.get<boolean>('extensionParked') === true; }
 static arm(context: common.UIAbilityContext, supported: boolean): void {
  if (!supported || BackgroundExtension.failed) { return; }
  BackgroundExtension.context = context;BackgroundExtension.desired = true;
  if (BackgroundExtension.granted) { native.input('BACKGROUND 1'); }
  BackgroundExtension.resuming = false;
  BackgroundExtension.reconcile();
 }
 private static async reconcile(): Promise<void> {
  if (BackgroundExtension.changing || !BackgroundExtension.context) { return; }
  BackgroundExtension.changing = true;
  const context = BackgroundExtension.context;
  try {
   while (BackgroundExtension.desired !== BackgroundExtension.granted) {
    if (BackgroundExtension.desired) {
     const agent = await wantAgent.getWantAgent({ wants: [{ bundleName: 'cn.edgelink.store', abilityName: 'EntryAbility' }],
      operationType: wantAgent.OperationType.START_ABILITY, requestCode: 48,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG] });
     // End may have happened while the WantAgent was being created.
     if (!BackgroundExtension.desired) { continue; }
     await backgroundTaskManager.startBackgroundRunning(context, backgroundTaskManager.BackgroundMode.MULTI_DEVICE_CONNECTION, agent);
     BackgroundExtension.granted = true;
    } else {
     await backgroundTaskManager.stopBackgroundRunning(context);
     BackgroundExtension.granted = false;
    }
   }
   native.input(BackgroundExtension.granted ? 'BACKGROUND 1' : 'BACKGROUND 0');
   AppStorage.setOrCreate('extensionBackgroundReady', BackgroundExtension.granted);
  } catch (e) {
   BackgroundExtension.failed = true;
   native.input('BACKGROUND 0');
   AppStorage.setOrCreate('extensionBackgroundReady', false);
   AppStorage.setOrCreate('extensionBackgroundError', '系统未允许后台连接；请保持映桥在前台。');
  } finally { BackgroundExtension.changing = false; }
 }
 static suspend(): boolean {
  if (BackgroundExtension.parked()) { return true; }
  if (!BackgroundExtension.desired || !BackgroundExtension.granted) { return false; }
  let state: ExtensionSnapshot;
  try { state = JSON.parse(native.stats()) as ExtensionSnapshot; } catch (e) { return false; }
  if (!state.backgroundRetainSupported || !state.sessionID || (!state.running && state.stopReason !== 'background_suspend')) { return false; }
  AppStorage.setOrCreate('extensionParkedSession', state.sessionID);
  AppStorage.setOrCreate('extensionParked', true);
  BackgroundExtension.resuming = false;BackgroundExtension.resumeUntil = 0;
  native.input('LOCALUI 1');native.input('CURSORLOCK -1 0');
  if (state.running) { native.disconnect('background_suspend'); }
  return true;
 }
 static resumeWindowOpen(): boolean {
  if (!BackgroundExtension.resumeUntil) { BackgroundExtension.resumeUntil = Date.now() + 30000; }
  return Date.now() < BackgroundExtension.resumeUntil;
 }
 static prepareResume(): void {
  AppStorage.setOrCreate('extensionParked', false);
  BackgroundExtension.resuming = true;
  if (!BackgroundExtension.resumeUntil) { BackgroundExtension.resumeUntil = Date.now() + 30000; }
 }
 static retryResume(): boolean {
  if (!BackgroundExtension.resuming || Date.now() >= BackgroundExtension.resumeUntil) { return false; }
  AppStorage.setOrCreate('extensionParked', true);return true;
 }
 static end(): void {
  if (BackgroundExtension.parked() || BackgroundExtension.resuming) {
   const session = AppStorage.get<number>('extensionParkedSession') || 0;
   if (session > 0) { native.availabilityEnd(session); }
  }
  AppStorage.setOrCreate('extensionParked', false);AppStorage.setOrCreate('extensionParkedSession', 0);
  native.input('BACKGROUND 0');BackgroundExtension.desired = false;BackgroundExtension.failed = false;
  BackgroundExtension.resuming = false;BackgroundExtension.resumeUntil = 0;
  AppStorage.setOrCreate('extensionBackgroundError', '');
  BackgroundExtension.reconcile();
 }
}

import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { AppAiHost } from '../../../main/ets/utils/AppAiHost';
import { AccountSessionStore } from '../../../main/ets/account/AccountSessionStore';

/** Read real app state, never the instrumentation module's empty account store. */
export async function openComicTestContext(): Promise<common.Context> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  let context: common.Context | null = null;
  try {
    const current = (await delegator.getCurrentTopAbility()).context;
    if (current.preferencesDir.includes('/haps/entry/')) context = current;
  } catch (_) {}
  if (!context) {
    const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility', moduleName: 'entry' };
    await delegator.addAbilityMonitor(monitor);
    try {
      await delegator.startAbility({ bundleName: 'io.legado.read', moduleName: 'entry', abilityName: 'EntryAbility' });
      context = (await delegator.waitAbilityMonitor(monitor, 10000)).context;
    } finally { await delegator.removeAbilityMonitor(monitor); }
  }
  if (!context || !context.preferencesDir.includes('/haps/entry/')) throw new Error('Production EntryAbility context unavailable');
  AppAiHost.install();
  await AccountSessionStore.load(context);
  return context;
}

import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import testsuite from '../test/List.test';
import { openComicTestContext } from './ComicTestContext';

/** Explicit runner: instrumentation has its own ability and must not inherit production EntryAbility. */
export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare(): void {}
  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    try {
      await openComicTestContext();
      Hypium.hypiumTest(delegator, abilityDelegatorRegistry.getArguments(), testsuite);
    } catch (error) { await delegator.finishTest(`FAIL test context: ${(error as Error).message}`, -1); }
  }
}

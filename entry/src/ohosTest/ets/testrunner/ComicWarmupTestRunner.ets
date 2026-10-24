import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { verifyComicWarmup } from './ComicColorWarmupDiagnostics';

export default class ComicWarmupTestRunner implements TestRunner {
  onPrepare(): void {}
  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    try {
      await verifyComicWarmup();
      await delegator.finishTest('PASS ComicWarmup', 0);
    } catch (error) {
      await delegator.finishTest(`FAIL ComicWarmup: ${(error as Error).message}`, -1);
    }
  }
}

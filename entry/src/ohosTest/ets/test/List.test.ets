import ComicColorTestRunner from '../testrunner/ComicColorTestRunner';
import { describe, it } from '@ohos/hypium';
import { diagnoseComicEdges } from '../testrunner/ComicColorDiagnostics';
import { verifyComicComposite } from '../testrunner/ComicCompositeDiagnostics';
import { verifyComicWarmup } from '../testrunner/ComicColorWarmupDiagnostics';

export default function testsuite(): void {
  describe('ComicColor', (): void => {
    it('warmupLifecycle', 0, async (): Promise<void> => { await verifyComicWarmup(); });
    it('nativeComposite', 0, async (): Promise<void> => { await verifyComicComposite(); });
    it('diagnoseEdges', 0, async (): Promise<void> => { await diagnoseComicEdges(); });
    it('offlineInferenceCacheAndCancel', 0, async (): Promise<void> => {
      await new ComicColorTestRunner().verify();
    });
  });
}

import ComicColorTestRunner from '../testrunner/ComicColorTestRunner';
import { describe, it } from '@ohos/hypium';
import { diagnoseComicEdges } from '../testrunner/ComicColorDiagnostics';

export default function testsuite(): void {
  describe('ComicColor', (): void => {
    it('diagnoseEdges', 0, async (): Promise<void> => { await diagnoseComicEdges(); });
    it('offlineInferenceCacheAndCancel', 0, async (): Promise<void> => {
      await new ComicColorTestRunner().verify();
    });
  });
}

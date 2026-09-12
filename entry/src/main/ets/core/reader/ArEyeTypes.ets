import { NodeController } from '@ohos.arkui.node';

/** Normalized eye-turn signal derived from AR Engine face blend shapes. */
export interface ArEyeSignal {
  lookUp: number;
  lookDown: number;
  blink: number;
  confidence: number;
}

/**
 * Kit-free handle to a lazily created AR eye-turn session. The concrete
 * implementation lives in ArEngineEyeTracker.ets, which must only be loaded
 * through `import()`: the AR kit's native module is absent on some devices
 * (for example emulators), and a static import would fail to link and take the
 * whole reader page down with it.
 */
export interface ArEyeTurnHost {
  controller: NodeController;
  stop(): void;
}

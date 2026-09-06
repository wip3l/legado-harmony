import { arEngine, arViewController } from '@kit.AREngine';
import deviceInfo from '@ohos.deviceInfo';
import { Node } from '@ohos.graphics.scene';

export interface ArEyeSignal {
  lookUp: number;
  lookDown: number;
  blink: number;
  confidence: number;
}

/** ArkTS adapter for AR Engine face blend-shape data. */
export class ArEngineEyeTracker {
  static isAvailable(): boolean {
    if (deviceInfo.sdkApiVersion < 23) return false;
    try {
      return arViewController.isARTypeSupported(arEngine.ARFeatureType.ARENGINE_FEATURE_TYPE_FACE);
    } catch (_) {
      return false;
    }
  }

  static readSignal(face: arEngine.ARFace): ArEyeSignal {
    const result: ArEyeSignal = { lookUp: 0, lookDown: 0, blink: 0, confidence: 0 };
    const blendShapes = face.getBlendShapes();
    try {
      const types = blendShapes.getTypes();
      const values = new Float32Array(blendShapes.getData());
      let samples = 0;
      for (let index = 0; index < types.length && index < values.length; index++) {
        const value = Math.max(0, Math.min(1, values[index]));
        switch (types[index]) {
          case arEngine.ARBlendShapeType.EYE_LOOK_UP_LEFT:
          case arEngine.ARBlendShapeType.EYE_LOOK_UP_RIGHT:
            result.lookUp += value; samples++; break;
          case arEngine.ARBlendShapeType.EYE_LOOK_DOWN_LEFT:
          case arEngine.ARBlendShapeType.EYE_LOOK_DOWN_RIGHT:
            result.lookDown += value; samples++; break;
          case arEngine.ARBlendShapeType.EYE_BLINK_LEFT:
          case arEngine.ARBlendShapeType.EYE_BLINK_RIGHT:
            result.blink += value; break;
        }
      }
      result.lookUp = Math.min(1, result.lookUp / 2);
      result.lookDown = Math.min(1, result.lookDown / 2);
      result.blink = Math.min(1, result.blink / 2);
      result.confidence = samples > 0 ? 1 : 0;
      return result;
    } finally {
      blendShapes.release().catch(() => {});
    }
  }
}

export class ArEngineFaceCallback extends arViewController.ARViewCallback {
  private readonly onSignal: (signal: ArEyeSignal) => void;
  constructor(onSignal: (signal: ArEyeSignal) => void) { super(); this.onSignal = onSignal; }
  onFrameUpdate(ctx: arViewController.ARViewContext, _sysBootTs: number): void {
    const session = ctx.session;
    if (!session) return;
    try {
      const faces = session.getAllTrackables(arEngine.ARTrackableType.FACE);
      if (faces.length === 0) return;
      this.onSignal(ArEngineEyeTracker.readSignal(faces[0] as arEngine.ARFace));
    } catch (_) {
      // AR Engine can temporarily report no trackables while the camera is settling.
    }
  }
  onAnchorAdd(_ctx: arViewController.ARViewContext, _node: Node, _anchor: arEngine.ARAnchor): void {}
  onAnchorUpdate(_ctx: arViewController.ARViewContext, _node: Node, _anchor: arEngine.ARAnchor): void {}
}

export class ArEngineFaceSession {
  readonly context: arViewController.ARViewContext = new arViewController.ARViewContext();
  private callback: ArEngineFaceCallback | null = null;
  async start(onSignal: (signal: ArEyeSignal) => void): Promise<boolean> {
    if (!ArEngineEyeTracker.isAvailable()) return false;
    this.callback = new ArEngineFaceCallback(onSignal);
    this.context.config = { type: arEngine.ARType.FACE, powerMode: arEngine.ARPowerMode.POWER_SAVING };
    this.context.callback = this.callback;
    try { await this.context.init(); return true; } catch (_) { this.callback = null; return false; }
  }
  async stop(): Promise<void> { this.callback = null; try { await this.context.destroy(); } catch (_) {} }
}

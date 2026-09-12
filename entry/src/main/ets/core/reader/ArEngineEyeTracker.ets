import { arEngine, arViewController, ARView } from '@kit.AREngine';
import { BusinessError } from '@kit.BasicServicesKit';
import deviceInfo from '@ohos.deviceInfo';
import { Node, Scene } from '@ohos.graphics.scene';
import { BuilderNode, FrameNode, NodeController } from '@ohos.arkui.node';
import { UIContext } from '@ohos.arkui.UIContext';
import { ArEyeSignal, ArEyeTurnHost } from './ArEyeTypes';

/**
 * ArkTS adapter for AR Engine face blend-shape data.
 *
 * This module statically imports the AR kit, so it must only ever be reached
 * through `import()`: on devices whose image has no AREngine native library the
 * kit module provides no exports, and a static import chain would fail to link
 * and prevent the reader page from loading at all.
 */
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
    // getBlendShapes() throws (AnimojiBlendShape is nullptr) until the face is
    // actually tracked, so the call itself has to be guarded.
    let blendShapes: arEngine.ARBlendShapes;
    try {
      blendShapes = face.getBlendShapes();
    } catch (_) {
      return result;
    }
    if (!blendShapes) return result;
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
  private frameCount: number = 0;
  private lastLogAt: number = 0;
  private lastSignalAt: number = 0;
  // The dwell gesture only needs a steady ~10Hz stream. Forwarding every camera
  // frame floods the UI thread and makes the whole reader stutter.
  private static readonly SIGNAL_INTERVAL_MS: number = 100;

  constructor(onSignal: (signal: ArEyeSignal) => void) { super(); this.onSignal = onSignal; }

  onFrameUpdate(ctx: arViewController.ARViewContext, _sysBootTs: number): void {
    this.frameCount++;
    const now = Date.now();
    const logDue = now - this.lastLogAt >= 2000;
    if (logDue) this.lastLogAt = now;
    const session = ctx.session;
    if (!session) {
      if (logDue) console.info(`[EyeTurn] AR frames=${this.frameCount} no session`);
      return;
    }
    try {
      const faces = session.getAllTrackables(arEngine.ARTrackableType.FACE);
      if (faces.length === 0) {
        if (logDue) console.info(`[EyeTurn] AR frames=${this.frameCount} faces=0`);
        return;
      }
      const face = faces[0] as arEngine.ARFace;
      const signal = ArEngineEyeTracker.readSignal(face);
      if (logDue) {
        console.info(`[EyeTurn] AR frames=${this.frameCount} faces=${faces.length} state=${face.state} ` +
          `up=${signal.lookUp.toFixed(3)} down=${signal.lookDown.toFixed(3)} ` +
          `blink=${signal.blink.toFixed(3)} conf=${signal.confidence}`);
      }
      if (signal.confidence <= 0) return;
      if (now - this.lastSignalAt < ArEngineFaceCallback.SIGNAL_INTERVAL_MS) return;
      this.lastSignalAt = now;
      this.onSignal(signal);
    } catch (error) {
      if (logDue) console.warn('[EyeTurn] AR frame read failed:', (error as BusinessError).message);
    }
  }
  onAnchorAdd(_ctx: arViewController.ARViewContext, _node: Node, _anchor: arEngine.ARAnchor): void {}
  onAnchorUpdate(_ctx: arViewController.ARViewContext, _node: Node, _anchor: arEngine.ARAnchor): void {}
}

/** Builder arguments packed into one object to keep BuilderNode's API simple. */
class ArEngineViewHostArgs {
  readonly context: arViewController.ARViewContext;
  readonly onReady: () => void;

  constructor(context: arViewController.ARViewContext, onReady: () => void) {
    this.context = context;
    this.onReady = onReady;
  }
}

/** Tiny ALWAYS-visible ARView surface: an effectively transparent node never
 * reaches TRACKING, so keep it rendered at one pixel instead of using opacity. */
@Builder
function arEngineViewHost(args: ArEngineViewHostArgs) {
  ARView({ context: args.context })
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
    // ARView installs the 3D AR scene itself. Calling init() before the
    // component has actually appeared fails with "Graphics3D AR scene
    // required", so the session starts from the ARView's own onAppear.
    .onAppear((): void => {
      console.info('[EyeTurn] AR view appeared');
      args.onReady();
    })
}

/** Builds the ARView lazily and keeps its backend node alive while active. */
class ArEngineViewHostController extends NodeController {
  private readonly args: ArEngineViewHostArgs;
  private node: BuilderNode<[ArEngineViewHostArgs]> | null = null;

  constructor(args: ArEngineViewHostArgs) {
    super();
    this.args = args;
  }

  makeNode(uiContext: UIContext): FrameNode | null {
    const node = new BuilderNode<[ArEngineViewHostArgs]>(uiContext);
    node.build(wrapBuilder(arEngineViewHost), this.args);
    this.node = node;
    return node.getFrameNode();
  }

  release(): void {
    // Drop the reference so the backend node can be collected with the
    // controller. Disposing while NodeContainer may still be attached can
    // tear down a live node; the reader never disposes render nodes eagerly.
    this.node = null;
  }
}

class ArEngineEyeTurnHost implements ArEyeTurnHost {
  readonly controller: NodeController;
  private readonly viewController: ArEngineViewHostController;
  private readonly context: arViewController.ARViewContext;
  private readonly callback: ArEngineFaceCallback;
  private readonly onStop: () => void;
  private stopped: boolean = false;

  constructor(viewController: ArEngineViewHostController, context: arViewController.ARViewContext,
    callback: ArEngineFaceCallback, onStop: () => void) {
    this.viewController = viewController;
    this.context = context;
    this.callback = callback;
    this.onStop = onStop;
    this.controller = viewController;
  }

  stop(): void {
    if (this.stopped) return;
    this.stopped = true;
    this.onStop();
    this.viewController.release();
    try {
      this.context.destroy().catch((): void => {});
    } catch (_) {
    }
  }
}

/**
 * Creates an AR eye-turn host, or resolves to null when AR is unavailable.
 * Callers must load this module with `import()` and keep the returned host
 * mounted through its NodeController while eye tracking is active.
 */
export async function createArEngineEyeTurnHost(
  onSignal: (signal: ArEyeSignal) => void,
  onActive: (active: boolean) => void
): Promise<ArEyeTurnHost | null> {
  if (!ArEngineEyeTracker.isAvailable()) return null;
  const context = new arViewController.ARViewContext();
  const callback = new ArEngineFaceCallback(onSignal);
  context.config = { type: arEngine.ARType.FACE, powerMode: arEngine.ARPowerMode.POWER_SAVING };
  context.callback = callback;
  // ARView installs the 3D scene asynchronously, so an init issued right after
  // the view appears can still fail with "Graphics3D AR scene required".
  // Retry briefly instead of giving up on the first attempt.
  const MAX_INIT_ATTEMPTS = 12;
  let cancelled = false;
  let attempts = 0;
  let sceneCreated = false;
  // If ARView does not install the 3D scene by itself, the app can supply one
  // from the default RenderContext; init() rejects without a scene.
  const ensureScene = async (): Promise<void> => {
    if (sceneCreated) return;
    try {
      const renderContext = Scene.getDefaultRenderContext();
      if (!renderContext) return;
      const scene = await renderContext.getRenderResourceFactory().createScene();
      context.scene = scene;
      sceneCreated = true;
      console.info('[EyeTurn] AR scene supplied by app');
    } catch (error) {
      console.warn('[EyeTurn] AR scene setup failed:', (error as BusinessError).message);
    }
  };
  const attemptInit = async (): Promise<void> => {
    if (cancelled) return;
    attempts++;
    await ensureScene();
    if (attempts === 1 || attempts === MAX_INIT_ATTEMPTS) {
      try {
        console.info('[EyeTurn] AR scene present (attempt ' + attempts + '): ' + (!!context.scene));
      } catch (error) {
        console.warn('[EyeTurn] AR scene read failed (attempt ' + attempts + '):',
          (error as BusinessError).message);
      }
    }
    context.init().then((): void => {
      if (cancelled) return;
      console.info('[EyeTurn] AR session started (attempt ' + attempts + ')');
      onActive(true);
    }).catch((error: Object): void => {
      if (cancelled) return;
      const detail = error as BusinessError;
      if (attempts < MAX_INIT_ATTEMPTS) {
        console.warn('[EyeTurn] AR init attempt ' + attempts + ' failed: ' + detail.message);
        setTimeout((): void => {
          attemptInit().catch((): void => {});
        }, 200);
      } else {
        console.warn('[EyeTurn] AR session init failed:', detail.message);
        onActive(false);
      }
    });
  };
  const viewController = new ArEngineViewHostController(new ArEngineViewHostArgs(context, (): void => {
    attemptInit().catch((): void => {});
  }));
  console.info('[EyeTurn] AR host created');
  // The host keeps the callback strongly referenced for its whole lifetime.
  return new ArEngineEyeTurnHost(viewController, context, callback, (): void => {
    cancelled = true;
  });
}

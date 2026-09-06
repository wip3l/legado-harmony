export class ReaderEyeCalibrationPoint {
  score: number = 0;
  pitch: number = 0;
  eyeRatio: number = 0.5;
  eyeAvailable: boolean = false;
  targetY: number = 0;
  phase: number = 0;
  confidence: number = 0;
}
export class ReaderEyeCalibrationFit {
  slope: number = 0;
  intercept: number = 0;
  correlation: number = 0;
}

export class ComicColorJob {
  cancel: boolean = false;
  modelPath: string = '';
  imageBytes: ArrayBuffer = new ArrayBuffer(0);
}

export class ComicColorMessage {
  status: string = '';
  error: string = '';
  jpeg: ArrayBuffer = new ArrayBuffer(0);
  width: number = 0;
  height: number = 0;
  inferenceMs: number = 0;
}

export class ComicColorResult {
  uri: string = '';
  elapsedMs: number = 0;
  inferenceMs: number = 0;
  cached: boolean = false;
}

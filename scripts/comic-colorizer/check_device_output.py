"""Compare test-only ComicColorDiagnostics dumps to ONNX, including bottom-edge accuracy.

The diagnostic output is interleaved RGB regardless of the Lite model's native layout.
Requires numpy and onnxruntime in the model-export environment. No phone/account state is modified.
"""
import argparse
import json
from pathlib import Path
import numpy as np
import onnxruntime as ort


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--onnx', type=Path, required=True)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--width', type=int, required=True)
    parser.add_argument('--height', type=int, required=True)
    parser.add_argument('--max-mean-error', type=float, default=0.03)
    args = parser.parse_args()
    source = np.fromfile(args.input, np.float32).reshape(1, args.height, args.width, 5)
    actual = np.fromfile(args.output, np.float32).reshape(args.height, args.width, 3)
    session = ort.InferenceSession(str(args.onnx), providers=['CPUExecutionProvider'])
    expected = session.run(None, {'gray_hint': source.transpose(0, 3, 1, 2).copy()})[0][0].transpose(1, 2, 0)
    error = np.abs(actual - expected)
    edge_rows = max(1, args.height // 5)
    metrics = {'width': args.width, 'height': args.height, 'mean_error': float(error.mean()),
               'bottom_mean_error': float(error[-edge_rows:].mean()), 'max_error': float(error.max())}
    print(json.dumps(metrics))
    if not np.isfinite(error).all() or metrics['mean_error'] > args.max_mean_error or \
            metrics['bottom_mean_error'] > args.max_mean_error:
        raise SystemExit('FAIL: native output differs from reference, including page-bottom pixels')


if __name__ == '__main__':
    main()

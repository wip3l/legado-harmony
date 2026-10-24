"""Export pinned AlacGAN with resizable spatial dimensions; see docs/comic-colorizer.md."""
import argparse
import hashlib
import importlib
import json
import sys
from pathlib import Path
import numpy as np
import torch

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--upstream', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    for name, expected_hash in {
        'networks/alac_gan.py': '2ed96ead841e18cc492338d9361313c838f6d365be1184eddc67027bf42c88de',
        'networks/extractor.py': 'bd8ef039681ec1ca27ede3081a034515e47b9f628b957acaf7c0e271bca8b23a',
        'generator.zip': '087e6a0bc02770e732a52f33878b71a272a6123c9ac649e9b5bfb75e39e5c1d5',
    }.items():
        data = (args.upstream / name).read_bytes()
        if name.endswith('.py'):
            data = data.replace(b'\r\n', b'\n')
        if hashlib.sha256(data).hexdigest() != expected_hash:
            raise RuntimeError(f'Unexpected upstream file: {name}')
    sys.path.insert(0, str(args.upstream.resolve()))
    colorizer = importlib.import_module('networks.alac_gan').Colorizer

    class Export(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.model = colorizer().eval()
            self.model.generator.load_state_dict(torch.load(args.upstream / 'generator.zip',
                map_location='cpu', weights_only=True), strict=True)

        def forward(self, x):
            return self.model(x)[0]

    model = Export().eval()
    torch.set_num_threads(4)
    torch.manual_seed(7)
    sample = torch.zeros(1, 5, 768, 512)
    sample[:, 0] = torch.rand(1, 768, 512)
    args.output.mkdir(parents=True, exist_ok=True)
    path = args.output / 'alac.onnx'
    # Export only RGB: the auxiliary training decoder is pruned.
    torch.onnx.export(model, sample, path, input_names=['gray_hint'], output_names=['rgb'],
        opset_version=11, dynamo=False,
        dynamic_axes={'gray_hint': {2: 'height', 3: 'width'}, 'rgb': {2: 'height', 3: 'width'}})
    with torch.inference_mode():
        expected = model(sample).numpy()
    sample.numpy().transpose(0, 2, 3, 1).copy().tofile(args.output / 'alac_input.bin')
    # Keep spatial axes dynamic in the Lite conversion (omit converter --inputShape).
    # With dynamic axes the converted output stays NCHW, even if --outputDataFormat=NHWC is requested.
    expected.copy().tofile(args.output / 'alac_expected.bin')
    with (args.output / 'alac_expected.txt').open('w') as output:
        output.write('rgb 4 1 3 768 512\n')
        np.savetxt(output, expected.reshape(1, -1), fmt='%.8g')
    import onnxruntime as ort
    actual = ort.InferenceSession(str(path)).run(None, {'gray_hint': sample.numpy()})[0]
    error = float(np.max(np.abs(expected - actual)))
    if error > 0.001:
        raise RuntimeError(f'ONNX output differs from PyTorch: {error}')
    print(json.dumps({'onnx_max_error': error,
        'parameters_before_pruning': sum(p.numel() for p in model.parameters())}))

if __name__ == '__main__':
    main()

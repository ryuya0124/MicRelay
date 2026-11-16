#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 ryuya
"""Compare input/output spectrum work against build 7 on the local Mac CPU.

Requires Xcode/Accelerate. Does not access microphones, devices, or audio sessions.
Both implementations run in one process, with alternating order after warmup.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'MicRelay/Audio/SpectrumAnalyzer.swift'


def fft_class(source, name):
    return source[source.index('final class SpectrumFFT'):].replace('class SpectrumFFT', f'class {name}', 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', default='a6ef5e0', help='Git reference containing the build 7 analyzer')
    parser.add_argument('--iterations', type=int, default=1000)
    parser.add_argument('--rounds', type=int, default=7)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.iterations <= 0 or args.rounds <= 0:
        parser.error('iterations and rounds must be positive')
    previous = subprocess.check_output(['git', 'show', f'{args.baseline}:{SOURCE}'], cwd=ROOT, text=True)
    current = (ROOT / SOURCE).read_text()
    driver = '''
let baseline = BaselineFFT(), current = CurrentFFT()
let input = (0..<4096).map { Float(sin(Double($0) * 0.13) * 0.4 + cos(Double($0) * 0.317) * 0.17) }
let output = input.map { $0 * 0.7 }
@inline(never) func analyzeBaseline(_ cursor: Int) -> Double {
    var orderedInput = [Float](repeating: 0, count: 4096)
    var orderedOutput = orderedInput
    for i in 0..<4096 {
        orderedInput[i] = input[(cursor + i) % 4096]
        orderedOutput[i] = output[(cursor + i) % 4096]
    }
    let first = baseline.spectrum(orderedInput, sampleRate: 48000)
    let second = baseline.spectrum(orderedOutput, sampleRate: 48000)
    let bin = cursor % 128
    return Double(first.db[bin]) + Double(second.db[bin]) + first.frequencies[bin] * 0.000001
}
@inline(never) func analyzeCurrent(_ cursor: Int) -> Double {
    let first = current.spectrum(input, startingAt: cursor, sampleRate: 48000)
    let second = current.spectrum(output, startingAt: cursor, sampleRate: 48000)
    let bin = cursor % 128
    return Double(first.db[bin]) + Double(second.db[bin]) + first.frequencies[bin] * 0.000001
}
var beforeChecksum = 0.0, afterChecksum = 0.0
for i in 0..<32 {
    beforeChecksum += analyzeBaseline((i * 17) % 4096)
    afterChecksum += analyzeCurrent((i * 17) % 4096)
}
@inline(never) func measure(_ analyze: (Int) -> Double) -> (Double, Double) {
    var checksum = 0.0
    let began = DispatchTime.now().uptimeNanoseconds
''' + f'''    for i in 0..<{args.iterations} {{ checksum += analyze((i * 17) % 4096) }}
    return (Double(DispatchTime.now().uptimeNanoseconds - began) / 1000 / {args.iterations}, checksum)
}}
var before: [Double] = [], after: [Double] = []
for round in 0..<{args.rounds} {{
''' + '''    if round % 2 == 0 {
        let old = measure(analyzeBaseline), new = measure(analyzeCurrent)
        before.append(old.0); after.append(new.0)
        beforeChecksum += old.1; afterChecksum += new.1
    } else {
        let new = measure(analyzeCurrent), old = measure(analyzeBaseline)
        before.append(old.0); after.append(new.0)
        beforeChecksum += old.1; afterChecksum += new.1
    }
}
let report: [String: Any] = [
    "baseline": ["microseconds_per_analysis_frame": before.sorted()[before.count / 2], "trials": before, "checksum": beforeChecksum],
    "current": ["microseconds_per_analysis_frame": after.sorted()[after.count / 2], "trials": after, "checksum": afterChecksum]]
print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
'''
    with tempfile.TemporaryDirectory(prefix='MicRelay-spectrum-') as temporary:
        directory = Path(temporary)
        swift, executable = directory / 'main.swift', directory / 'benchmark'
        swift.write_text('import Foundation\nimport Accelerate\n' + fft_class(previous, 'BaselineFFT') +
                         fft_class(current, 'CurrentFFT') + driver)
        subprocess.run(['xcrun', '--sdk', 'macosx', 'swiftc', '-O', '-whole-module-optimization',
                        '-swift-version', '5', str(swift), '-o', str(executable)], check=True)
        report = json.loads(subprocess.check_output([str(executable)], text=True))
    before, after = report['baseline'], report['current']
    if before['checksum'] != after['checksum']:
        raise RuntimeError('Spectrum result checksum changed')
    report.update(baseline_ref=args.baseline, iterations=args.iterations, rounds=args.rounds,
                  reduction_percent=100 * (1 - after['microseconds_per_analysis_frame'] / before['microseconds_per_analysis_frame']),
                  scope='Local Mac CPU, two 4096-point spectra including window ordering. Not iOS audio latency.')
    result = json.dumps(report, indent=2) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(result)
    print(result, end='')


if __name__ == '__main__':
    main()

from pathlib import Path
import hashlib
import importlib.metadata
import json
import struct
import argparse
import subprocess

import numpy as np
import segyio

parser = argparse.ArgumentParser(description="Verify the fixed complete USGS DS259 06c01 line; no network request")
parser.add_argument("input", type=Path)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
ROOT = Path(__file__).resolve().parents[1]
DATA = args.input.resolve()
out = args.output.resolve()
out.parent.mkdir(parents=True, exist_ok=True)
PRODUCT = out.with_suffix(".qc.json")
EXPECTED_SHA = "50f298aa8d154895c6236d1f851228fe3cc6b590ad163c50835685243da61547"
DATA_BYTES = DATA.read_bytes()
assert len(DATA_BYTES) == 62_075_520
assert hashlib.sha256(DATA_BYTES).hexdigest() == EXPECTED_SHA
assert int("3b33280", 16) == len(DATA_BYTES), "official response ETag size component changed"

REEL = 3600
TRACE_HEADER = 240
SAMPLES_PER_TRACE = 750
SAMPLE_BYTES = SAMPLES_PER_TRACE * 4
STRIDE = TRACE_HEADER + SAMPLE_BYTES
assert (len(DATA_BYTES) - REEL) % STRIDE == 0
TRACE_COUNT = (len(DATA_BYTES) - REEL) // STRIDE
assert TRACE_COUNT == 19_158

binary = DATA_BYTES[3200:3600]
interval = struct.unpack_from(">H", binary, 16)[0]
declared_samples = struct.unpack_from(">H", binary, 20)[0]
sample_format = struct.unpack_from(">H", binary, 24)[0]
assert (interval, declared_samples, sample_format) == (40, 750, 2)

trace_groups = np.empty(TRACE_COUNT, dtype=np.int32)
traces = np.empty((TRACE_COUNT, SAMPLES_PER_TRACE), dtype=np.int32)
for i in range(TRACE_COUNT):
    header = REEL + i * STRIDE
    n = struct.unpack_from(">H", DATA_BYTES, header + 114)[0]
    dt = struct.unpack_from(">H", DATA_BYTES, header + 116)[0]
    assert n == SAMPLES_PER_TRACE and dt == interval, (i, n, dt)
    trace_groups[i] = struct.unpack_from(">i", DATA_BYTES, header + 12)[0]
    traces[i] = np.frombuffer(DATA_BYTES, dtype=">i4", count=SAMPLES_PER_TRACE, offset=header + TRACE_HEADER).astype(np.int32)
assert set(map(int, np.unique(trace_groups))) == {0, 1, 2}

command = ["node", "tools/segy.mjs", "qc", str(DATA), "examples/public/quality.json", str(PRODUCT)]
process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
assert process.returncode == 3, (process.returncode, process.stderr)
product = json.loads(PRODUCT.read_text(encoding="utf-8"))
assert product["status"] == "issues"
summary = product["summary"]
assert summary["traces"] == TRACE_COUNT
assert summary["samples"] == TRACE_COUNT * SAMPLES_PER_TRACE
assert summary["analyzed_samples"] == summary["samples"]
assert summary["minimum_samples"] == summary["maximum_samples"] == SAMPLES_PER_TRACE
assert summary["minimum_interval_us"] == summary["maximum_interval_us"] == interval
assert summary["dead_traces"] == int(np.all(traces == 0, axis=1).sum())
assert summary["dead_traces"] == 2_667
assert summary["nonfinite_samples"] == summary["integer_range_samples"] == 0

def stats(values):
    x = values.astype(np.float64, copy=False).reshape(-1)
    return {
        "samples": int(x.size),
        "minimum": int(x.min()),
        "maximum": int(x.max()),
        "mean": float(x.mean()),
        "rms": float(np.sqrt(np.mean(x * x))),
        "standard_deviation": float(x.std(ddof=0)),
    }

def compare_stats(actual, expected):
    assert actual["samples"] == expected["samples"]
    for key in ("minimum", "maximum"):
        assert actual[key] == expected[key], (key, actual[key], expected[key])
    for key in ("mean", "rms", "standard_deviation"):
        np.testing.assert_allclose(actual[key], expected[key], rtol=1e-11, atol=0.01, err_msg=key)

reference_global = stats(traces)
compare_stats(summary["statistics"], reference_global)
assert len(product["groups"]) == 3
assert {int(item["value"]) for item in product["groups"]} == {0, 1, 2}
assert len(product["details"]) == 100 and product["details_truncated"]
reference_groups = []
for item in product["groups"]:
    group = int(item["value"])
    rows = trace_groups == group
    expected_traces = int(rows.sum())
    assert item["summary"]["traces"] == expected_traces
    assert item["summary"]["dead_traces"] == int(np.all(traces[rows] == 0, axis=1).sum())
    expected = stats(traces[rows])
    compare_stats(item["summary"]["statistics"], expected)
    reference_groups.append({"value": group, "traces": expected_traces, "samples": expected["samples"], "dead_traces": int(np.all(traces[rows] == 0, axis=1).sum()), "statistics": expected})

# Independent SEG-Y reader walks every trace. segyio 1.9 exposes these int32
# samples as float32, so this is a layout/readability check, not the exact-integer
# oracle; exact values above came from raw big-endian struct/NumPy decoding.
with segyio.open(str(DATA), "r", strict=False, ignore_geometry=True) as ref:
    assert ref.tracecount == TRACE_COUNT
    assert int(ref.format) == sample_format
    assert int(ref.bin[segyio.BinField.Interval]) == interval
    for i in range(TRACE_COUNT):
        np.testing.assert_array_equal(ref.trace[i], traces[i].astype(np.float32))

receipt = {
    "input": str(DATA),
    "command": command,
    "cliExitCode": process.returncode,
    "productReportSha256": hashlib.sha256(PRODUCT.read_bytes()).hexdigest(),
    "bridgeSha256": hashlib.sha256((ROOT/"_build/js/release/build/cmd/bridge/bridge.js").read_bytes()).hexdigest(),
    "inputBytes": len(DATA_BYTES),
    "inputSha256": EXPECTED_SHA,
    "officialEtagHexSizeComponent": "3b33280",
    "officialEtagSizeMatchesBytes": True,
    "segYLayout": {
        "revisionWordBigEndian": struct.unpack_from(">H", binary, 300)[0],
        "format": sample_format,
        "traceCount": TRACE_COUNT,
        "samplesPerTrace": SAMPLES_PER_TRACE,
        "totalSamples": TRACE_COUNT * SAMPLES_PER_TRACE,
        "intervalUs": interval,
        "fixedTraceStrideBytes": STRIDE,
        "groups": reference_groups,
    },
    "independentReference": {
        "segyio": importlib.metadata.version("segyio"),
        "numpy": np.__version__,
        "rawIntegerOracle": "struct + NumPy big-endian signed int32; exact for every sample",
        "segyioRole": "all traces opened/read; int32 exposed as float32, so not exact-integer oracle",
        "fullTraceReadsMatchedRawFloat32Projection": TRACE_COUNT,
    },
    "productOutput": {
        "path": str(PRODUCT),
        "status": product["status"],
        "traces": summary["traces"],
        "samples": summary["samples"],
        "deadTraces": summary["dead_traces"],
        "statisticsMatchedIndependentRawDecode": True,
        "groupStatisticsMatchedIndependentRawDecode": True,
        "detailsReturned": len(product["details"]),
        "detailsTruncated": product["details_truncated"],
    },
    "assertions": "passed",
}
out.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"traceCount": TRACE_COUNT, "samples": TRACE_COUNT * SAMPLES_PER_TRACE, "deadTraces": summary["dead_traces"], "segyioTraceReads": TRACE_COUNT, "receipt": str(out)}))


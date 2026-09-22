///|
pub(all) struct TraceStatistics {
  samples : Int
  minimum : Double
  maximum : Double
  mean : Double
  rms : Double
  standard_deviation : Double
  dead : Bool
  clipped_samples : Int
  clipping_checked : Bool
} derive(ToJson)

///|
pub extend TraceStatistics with ToJson::{to_json}

///|
/// Raw (or optionally weighting-scaled) amplitudes, population deviation.
/// Dead means every |value|<=dead_threshold; clipping is a caller threshold,
/// not evidence of instrument saturation. clip_threshold=0 disables it.
pub fn Trace::statistics(
  self : Trace,
  dead_threshold? : Double = 0.0,
  clip_threshold? : Double = 0.0,
  weighted? : Bool = false,
) -> TraceStatistics raise {
  if !finite(dead_threshold) ||
    !finite(clip_threshold) ||
    dead_threshold < 0.0 ||
    clip_threshold < 0.0 {
    raise Failure("invalid amplitude threshold")
  }
  let values = Array::makei(self.count, i => self.amplitude(i, weighted~))
  let mut minimum = values[0]
  let mut maximum = values[0]
  let mut scale = 0.0
  let mut clipped = 0
  for v in values {
    minimum = minimum.min(v)
    maximum = maximum.max(v)
    scale = scale.max(v.abs())
    if clip_threshold > 0.0 && v.abs() >= clip_threshold {
      clipped += 1
    }
  }
  // Work in normalized coordinates: squaring raw 1e300 samples would overflow.
  let normalizer = if scale == 0.0 { 1.0 } else { scale }
  let mut sum = 0.0
  let mut squares = 0.0
  for v in values {
    let x = v / normalizer
    sum += x
    squares += x * x
  }
  let mean = sum / self.count.to_double()
  let mut variance = 0.0
  for v in values {
    let d = v / normalizer - mean
    variance += d * d
  }
  {
    samples: self.count,
    minimum,
    maximum,
    mean: mean * normalizer,
    rms: (squares / self.count.to_double()).sqrt() * normalizer,
    standard_deviation: (variance / self.count.to_double()).sqrt() * normalizer,
    dead: scale <= dead_threshold,
    clipped_samples: clipped,
    clipping_checked: clip_threshold > 0.0,
  }
}

///|
/// Inspect all samples; returns the count of nonfinite IEEE values. Exact
/// int64 samples are valid even when Double analysis would be refused.
pub fn Dataset::nonfinite_samples(self : Dataset) -> Int raise {
  let mut count = 0
  for i in 0..<self.trace_count() {
    let t = self.trace(i)
    for j in 0..<t.count {
      if t.sample(j) is Real(x) && !finite(x) {
        count += 1
      }
    }
  }
  count
}

///|
/// Long CSV with exact integer spelling and seconds. Selected traces use
/// original zero-based indices; maximum one million output samples.
pub fn Dataset::csv(self : Dataset, indices : Array[Int]) -> String raise {
  let out = StringBuilder()
  out.write_string("trace,sample,time_seconds,raw_amplitude\n")
  let mut rows = 0
  let seen : Map[Int, Bool] = Map([])
  for i in indices {
    if seen.contains(i) {
      raise Failure("duplicate CSV trace")
    }
    seen[i] = true
    let t = self.trace(i)
    rows += t.count
    if rows > 1000000 {
      raise Failure("CSV exceeds one million rows")
    }
    for j in 0..<t.count {
      let value = match t.sample(j) {
        Signed(v) => v.to_string()
        Real(v) => {
          if !finite(v) {
            raise Failure("nonfinite CSV sample")
          }
          v.to_string()
        }
      }
      out.write_string("\{i},\{j},\{t.time_seconds(j)},\{value}\n")
    }
  }
  out.to_string()
}

///|
/// Standalone, script-free waveform SVG for <=20000 samples. Normalized height
/// is visual only; title states peak amplitude and time span. No decimation.
pub fn Trace::svg(self : Trace) -> String raise {
  if self.count > 20000 {
    raise Failure("SVG needs a <=20000-sample window")
  }
  let values = Array::makei(self.count, i => self.amplitude(i))
  let mut peak = 0.0
  for v in values {
    peak = peak.max(v.abs())
  }
  let divisor = if peak == 0.0 { 1.0 } else { peak }
  let out = StringBuilder()
  out.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 960 360\"><rect width=\"960\" height=\"360\" fill=\"#f7f9fc\"/><text x=\"30\" y=\"28\" font-family=\"sans-serif\" font-size=\"16\">SEG-Y raw trace; peak=\{peak}; t=\{self.time_seconds(0)}..\{self.time_seconds(self.count-1)} s</text><path d=\"M30 180H930\" stroke=\"#aab3c2\"/><polyline fill=\"none\" stroke=\"#155e9a\" stroke-width=\"1.5\" points=\"",
  )
  for i, v in values {
    let x = 30.0 + i.to_double() * 900.0 / (self.count - 1).max(1).to_double()
    let y = 180.0 - v / divisor * 120.0
    out.write_string("\{x},\{y} ")
  }
  out.write_string(
    "\"/><text x=\"30\" y=\"338\" font-family=\"sans-serif\" font-size=\"13\">Amplitude normalized for display; no filtering or interpolation.</text></svg>\n",
  )
  out.to_string()
}

///|
/// Retained problem trace. Offsets refer to this Dataset's encoded bytes, not
/// a rewritten selection. Header identifiers are raw and need not be unique.
/// statistics is absent if ANY sample cannot be analyzed; no partial mean.
/// integer_range_samples counts |integer|>2^53, a conservative analysis
/// boundary, NOT a claim that every such integer is inexact or malformed.
pub struct TraceQuality {
  trace : Int
  header_offset : Int
  sample_offset : Int
  sequence_line : Int
  sequence_file : Int
  field_record : Int
  ensemble : Int
  identification : Int
  samples : Int
  interval_us : Double
  weighting : Int
  flags : Array[String]
  nonfinite_samples : Int
  first_nonfinite_sample : Int?
  integer_range_samples : Int
  first_integer_range_sample : Int?
  weighting_range_samples : Int
  first_weighting_range_sample : Int?
  statistics : TraceStatistics?
}

///|
fn quality_index_json(value : Int?) -> Json {
  match value {
    Some(x) => x.to_json()
    None => null
  }
}

///|
pub impl ToJson for TraceQuality with fn to_json(self) {
  {
    "trace": self.trace.to_json(),
    "header_offset": self.header_offset.to_json(),
    "sample_offset": self.sample_offset.to_json(),
    "sequence_line": self.sequence_line.to_json(),
    "sequence_file": self.sequence_file.to_json(),
    "field_record": self.field_record.to_json(),
    "ensemble": self.ensemble.to_json(),
    "identification": self.identification.to_json(),
    "samples": self.samples.to_json(),
    "interval_us": self.interval_us.to_json(),
    "weighting": self.weighting.to_json(),
    "flags": self.flags.to_json(),
    "nonfinite_samples": self.nonfinite_samples.to_json(),
    "first_nonfinite_sample": quality_index_json(self.first_nonfinite_sample),
    "integer_range_samples": self.integer_range_samples.to_json(),
    "first_integer_range_sample": quality_index_json(
      self.first_integer_range_sample,
    ),
    "weighting_range_samples": self.weighting_range_samples.to_json(),
    "first_weighting_range_sample": quality_index_json(
      self.first_weighting_range_sample,
    ),
    "statistics": match self.statistics {
      Some(x) => x.to_json()
      None => null
    },
  }
}

///|
pub extend TraceQuality with ToJson::{to_json}

///|
/// Counts cover ALL selected traces, even when details are truncated.
/// analyzed_* and pooled statistics exclude a WHOLE trace if any amplitude
/// is unavailable. Nonfinite/integer-range/weighting-range counts are sample counts; negative
/// weighting counts traces. dead/clipped counts use fully analyzable traces.
pub struct QualitySummary {
  traces : Int
  samples : Int
  analyzed_traces : Int
  analyzed_samples : Int
  problem_traces : Int
  nonfinite_samples : Int
  integer_range_samples : Int
  negative_weighting_traces : Int
  weighting_range_samples : Int
  dead_traces : Int
  header_dead_traces : Int
  clipped_traces : Int
  clipped_samples : Int
  minimum_samples : Int
  maximum_samples : Int
  minimum_interval_us : Double
  maximum_interval_us : Double
  statistics : AmplitudeStatistics?
}

///|
pub impl ToJson for QualitySummary with fn to_json(self) {
  {
    "traces": self.traces.to_json(),
    "samples": self.samples.to_json(),
    "analyzed_traces": self.analyzed_traces.to_json(),
    "analyzed_samples": self.analyzed_samples.to_json(),
    "problem_traces": self.problem_traces.to_json(),
    "nonfinite_samples": self.nonfinite_samples.to_json(),
    "integer_range_samples": self.integer_range_samples.to_json(),
    "negative_weighting_traces": self.negative_weighting_traces.to_json(),
    "weighting_range_samples": self.weighting_range_samples.to_json(),
    "dead_traces": self.dead_traces.to_json(),
    "header_dead_traces": self.header_dead_traces.to_json(),
    "clipped_traces": self.clipped_traces.to_json(),
    "clipped_samples": self.clipped_samples.to_json(),
    "minimum_samples": self.minimum_samples.to_json(),
    "maximum_samples": self.maximum_samples.to_json(),
    "minimum_interval_us": self.minimum_interval_us.to_json(),
    "maximum_interval_us": self.maximum_interval_us.to_json(),
    "statistics": match self.statistics {
      Some(x) => x.to_json()
      None => null
    },
  }
}

///|
pub extend QualitySummary with ToJson::{to_json}

///|
/// Groups are unscaled header values, in first SELECTED occurrence order.
/// No geometric grouping, coordinate-unit conversion or CRS inference.
pub struct QualityGroup {
  value : Int
  first_trace : Int
  summary : QualitySummary
} derive(ToJson)

///|
pub extend QualityGroup with ToJson::{to_json}

///|
/// status clear/issues refers only to the explicitly enabled checks. Neither
/// is instrument certification, a geological conclusion or acceptance proof.
/// Details keep the first max_details problem traces in selection order.
pub struct QualityReport {
  status : String
  source_trace_count : Int
  weighted : Bool
  dead_threshold : Double
  clip_threshold : Double
  clipping_checked : Bool
  group_by : String?
  summary : QualitySummary
  groups : Array[QualityGroup]
  details : Array[TraceQuality]
  max_details : Int
  details_truncated : Bool
}

///|
pub impl ToJson for QualityReport with fn to_json(self) {
  {
    "status": self.status.to_json(),
    "source_trace_count": self.source_trace_count.to_json(),
    "weighted": self.weighted.to_json(),
    "dead_threshold": self.dead_threshold.to_json(),
    "clip_threshold": self.clip_threshold.to_json(),
    "clipping_checked": self.clipping_checked.to_json(),
    "group_by": match self.group_by {
      Some(x) => x.to_json()
      None => null
    },
    "summary": self.summary.to_json(),
    "groups": self.groups.to_json(),
    "details": self.details.to_json(),
    "max_details": self.max_details.to_json(),
    "details_truncated": self.details_truncated.to_json(),
  }
}

///|
pub extend QualityReport with ToJson::{to_json}

///|
priv struct QualityTotals {
  mut traces : Int
  mut samples : Int
  mut analyzed_traces : Int
  mut problem_traces : Int
  mut nonfinite_samples : Int
  mut integer_range_samples : Int
  mut negative_weighting_traces : Int
  mut weighting_range_samples : Int
  mut dead_traces : Int
  mut header_dead_traces : Int
  mut clipped_traces : Int
  mut clipped_samples : Int
  mut minimum_samples : Int
  mut maximum_samples : Int
  mut minimum_interval_us : Double
  mut maximum_interval_us : Double
  moments : QualityMoments
}

///|
fn QualityTotals::new() -> QualityTotals {
  {
    traces: 0,
    samples: 0,
    analyzed_traces: 0,
    problem_traces: 0,
    nonfinite_samples: 0,
    integer_range_samples: 0,
    negative_weighting_traces: 0,
    weighting_range_samples: 0,
    dead_traces: 0,
    header_dead_traces: 0,
    clipped_traces: 0,
    clipped_samples: 0,
    minimum_samples: 0,
    maximum_samples: 0,
    minimum_interval_us: 0.0,
    maximum_interval_us: 0.0,
    moments: QualityMoments::new(),
  }
}

///|
fn QualityTotals::add(
  self : QualityTotals,
  item : TraceQuality,
  moments : QualityMoments,
) -> Unit {
  if self.traces == 0 {
    self.minimum_samples = item.samples
    self.minimum_interval_us = item.interval_us
  }
  self.minimum_samples = self.minimum_samples.min(item.samples)
  self.maximum_samples = self.maximum_samples.max(item.samples)
  self.minimum_interval_us = self.minimum_interval_us.min(item.interval_us)
  self.maximum_interval_us = self.maximum_interval_us.max(item.interval_us)
  self.traces += 1
  self.samples += item.samples
  self.nonfinite_samples += item.nonfinite_samples
  self.integer_range_samples += item.integer_range_samples
  self.weighting_range_samples += item.weighting_range_samples
  if !item.flags.is_empty() {
    self.problem_traces += 1
  }
  if item.flags.contains("negative_weighting") {
    self.negative_weighting_traces += 1
  }
  if item.identification == 2 {
    self.header_dead_traces += 1
  }
  if item.statistics is Some(stats) {
    self.analyzed_traces += 1
    self.moments.merge(moments)
    if stats.dead {
      self.dead_traces += 1
    }
    if stats.clipped_samples > 0 {
      self.clipped_traces += 1
    }
    self.clipped_samples += stats.clipped_samples
  }
}

///|
fn QualityTotals::finish(self : QualityTotals) -> QualitySummary {
  {
    traces: self.traces,
    samples: self.samples,
    analyzed_traces: self.analyzed_traces,
    analyzed_samples: self.moments.count,
    problem_traces: self.problem_traces,
    nonfinite_samples: self.nonfinite_samples,
    integer_range_samples: self.integer_range_samples,
    negative_weighting_traces: self.negative_weighting_traces,
    weighting_range_samples: self.weighting_range_samples,
    dead_traces: self.dead_traces,
    header_dead_traces: self.header_dead_traces,
    clipped_traces: self.clipped_traces,
    clipped_samples: self.clipped_samples,
    minimum_samples: self.minimum_samples,
    maximum_samples: self.maximum_samples,
    minimum_interval_us: self.minimum_interval_us,
    maximum_interval_us: self.maximum_interval_us,
    statistics: self.moments.finish(),
  }
}

///|
fn quality_trace(
  trace : Trace,
  number : Int,
  index : TraceIndex,
  dead : Double,
  clip : Double,
  weighted : Bool,
) -> (TraceQuality, QualityMoments) raise {
  let weight = trace.field("weighting")
  let bad_weight = weighted && weight < 0
  let factor = if weighted && !bad_weight {
    @math.pow(2.0, -weight.to_double())
  } else {
    1.0
  }
  let moments = QualityMoments::new()
  let mut nonfinite = 0
  let mut inexact = 0
  let mut range = 0
  let mut first_nonfinite = None
  let mut first_inexact = None
  let mut first_range = None
  let mut clipped = 0
  for i in 0..<trace.count {
    let raw = match trace.sample(i) {
      Real(x) if !finite(x) => {
        nonfinite += 1
        if first_nonfinite is None {
          first_nonfinite = Some(i)
        }
        continue
      }
      Signed(x) if x < -9007199254740992L || x > 9007199254740992L => {
        inexact += 1
        if first_inexact is None {
          first_inexact = Some(i)
        }
        continue
      }
      Real(x) => x
      Signed(x) => x.to_double()
    }
    if bad_weight {
      continue
    }
    let value = raw * factor
    if !finite(value) || (raw != 0.0 && value == 0.0) {
      range += 1
      if first_range is None {
        first_range = Some(i)
      }
      continue
    }
    moments.add(value)
    if clip > 0.0 && value.abs() >= clip {
      clipped += 1
    }
  }
  let identification = trace.field("identification")
  let flags : Array[String] = []
  if nonfinite > 0 {
    flags.push("nonfinite_samples")
  }
  if inexact > 0 {
    flags.push("integer_range_samples")
  }
  if bad_weight {
    flags.push("negative_weighting")
  }
  if range > 0 {
    flags.push("weighting_range")
  }
  let statistics : TraceStatistics? = if flags.is_empty() {
    guard moments.finish() is Some(stats) else {
      raise Failure("empty trace analysis")
    }
    let is_dead = stats.minimum.abs().max(stats.maximum.abs()) <= dead
    if is_dead {
      flags.push("dead_amplitude")
    }
    if clipped > 0 {
      flags.push("clip_threshold")
    }
    Some({
      samples: stats.samples,
      minimum: stats.minimum,
      maximum: stats.maximum,
      mean: stats.mean,
      rms: stats.rms,
      standard_deviation: stats.standard_deviation,
      dead: is_dead,
      clipped_samples: clipped,
      clipping_checked: clip > 0.0,
    })
  } else {
    None
  }
  // Standard trace header bytes 29-30: code 2 means declared dead. This is
  // independent of an amplitude threshold (a constant nonzero trace is not zero).
  if identification == 2 {
    flags.push("header_dead")
  }
  (
    {
      trace: number,
      header_offset: index.header_offset,
      sample_offset: index.sample_offset,
      sequence_line: trace.field("sequence_line"),
      sequence_file: trace.field("sequence_file"),
      field_record: trace.field("field_record"),
      ensemble: trace.field("ensemble"),
      identification,
      samples: trace.count,
      interval_us: trace.dt,
      weighting: weight,
      flags,
      nonfinite_samples: nonfinite,
      first_nonfinite_sample: first_nonfinite,
      integer_range_samples: inexact,
      first_integer_range_sample: first_inexact,
      weighting_range_samples: range,
      first_weighting_range_sample: first_range,
      statistics,
    },
    moments,
  )
}

///|
/// Scan the whole dataset or a unique nonempty original-index selection.
/// Continue after un-analyzable amplitudes; structural parse errors still raise.
/// Thresholds use raw or explicitly weighting-scaled amplitudes: dead if ALL
/// |x|<=dead_threshold; clip if |x|>=clip_threshold (0 disables clipping).
/// Statistics exclude whole un-analyzable traces, not just their bad samples.
/// Limits: max_details 0..100000, max_groups 1..100000; data limits unchanged.
pub fn Dataset::quality_check(
  self : Dataset,
  traces? : Array[Int],
  group_by? : String,
  dead_threshold? : Double = 0.0,
  clip_threshold? : Double = 0.0,
  weighted? : Bool = false,
  max_details? : Int = 256,
  max_groups? : Int = 65536,
) -> QualityReport raise {
  if !finite(dead_threshold) ||
    !finite(clip_threshold) ||
    dead_threshold < 0.0 ||
    clip_threshold < 0.0 {
    raise Failure("invalid amplitude threshold")
  }
  if max_details < 0 ||
    max_details > 100000 ||
    max_groups < 1 ||
    max_groups > 100000 {
    raise Failure("quality limits: max_details 0..100000, max_groups 1..100000")
  }
  let selected = traces.unwrap_or_else(() => {
    Array::makei(self.trace_count(), i => i)
  })
  if selected.is_empty() || selected.length() > self.trace_count() {
    raise Failure("empty/oversized quality selection")
  }
  let seen : Map[Int, Bool] = Map([])
  for i in selected {
    if i < 0 || i >= self.trace_count() || seen.contains(i) {
      raise Failure("invalid/duplicate quality trace index")
    }
    seen[i] = true
  }
  if group_by is Some(field) {
    ignore(self.trace(selected[0]).field(field))
  }
  let totals = QualityTotals::new()
  let group_lookup : Map[Int, Int] = Map([])
  let grouped : Array[(Int, Int, QualityTotals)] = []
  let details : Array[TraceQuality] = []
  for i in selected {
    let trace = self.trace(i)
    let group = match group_by {
      Some(field) => {
        let value = trace.field(field)
        let pos = match group_lookup.get(value) {
          Some(pos) => pos
          None => {
            if grouped.length() >= max_groups {
              raise Failure("quality group budget exceeded")
            }
            let pos = grouped.length()
            group_lookup[value] = pos
            grouped.push((value, i, QualityTotals::new()))
            pos
          }
        }
        Some(grouped[pos].2)
      }
      None => None
    }
    let (item, moments) = quality_trace(
      trace,
      i,
      self.index[i],
      dead_threshold,
      clip_threshold,
      weighted,
    )
    totals.add(item, moments)
    if group is Some(total) {
      total.add(item, moments)
    }
    if !item.flags.is_empty() && details.length() < max_details {
      details.push(item)
    }
  }
  {
    status: if totals.problem_traces > 0 {
      "issues"
    } else {
      "clear"
    },
    source_trace_count: self.trace_count(),
    weighted,
    dead_threshold,
    clip_threshold,
    clipping_checked: clip_threshold > 0.0,
    group_by,
    summary: totals.finish(),
    groups: grouped.map(g => {
      value: g.0,
      first_trace: g.1,
      summary: g.2.finish(),
    }),
    details,
    max_details,
    details_truncated: totals.problem_traces > details.length(),
  }
}

///|
/// Retained problem-trace rows only. Use JSON for aggregate/group statistics,
/// exclusions and truncation; an empty CSV is NOT evidence of a clear dataset.
pub fn QualityReport::issues_csv(self : QualityReport) -> String {
  let out = StringBuilder()
  out.write_string(
    "trace,header_offset,sample_offset,sequence_line,sequence_file,field_record,ensemble,samples,interval_us,flags,nonfinite_samples,first_nonfinite_sample,integer_range_samples,first_integer_range_sample,weighting_range_samples,first_weighting_range_sample,statistics_available,dead,clipped_samples,mean,rms\n",
  )
  let index = (x : Int?) => {
    match x {
      Some(v) => v.to_string()
      None => ""
    }
  }
  for d in self.details {
    out.write_string(
      "\{d.trace},\{d.header_offset},\{d.sample_offset},\{d.sequence_line},\{d.sequence_file},\{d.field_record},\{d.ensemble},\{d.samples},\{d.interval_us},\{d.flags.join(";")},\{d.nonfinite_samples},\{index(d.first_nonfinite_sample)},\{d.integer_range_samples},\{index(d.first_integer_range_sample)},\{d.weighting_range_samples},\{index(d.first_weighting_range_sample)},",
    )
    match d.statistics {
      Some(s) =>
        out.write_string(
          "true,\{s.dead},\{s.clipped_samples},\{s.mean},\{s.rms}\n",
        )
      None => out.write_string("false,,,,\n")
    }
  }
  out.to_string()
}

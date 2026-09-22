///|
/// Select/reorder unique zero-based trace indices. Preserve raw headers and
/// samples; sequence_file is re-numbered from one, original line IDs remain.
pub fn Dataset::select(self : Dataset, indices : Array[Int]) -> Dataset raise {
  if indices.is_empty() || indices.length() > self.trace_count() {
    raise Failure("empty/oversized trace selection")
  }
  let seen : Map[Int, Bool] = Map([])
  let traces = Array::makei(indices.length(), i => {
    let k = indices[i]
    if seen.contains(k) {
      raise Failure("duplicate trace index")
    }
    seen[k] = true
    let t = self.trace(k)
    let head = Array::makei(240, p => t.head[p])
    put_uint(head, 4, 4, (i + 1).to_uint64(), t.byte_order)
    { ..t, head: Bytes::from_array(head), }
  })
  assemble(self.header, traces, self.extensions)
}

///|
/// Raw signed header interval, inclusive. Returns [] when no trace matches.
pub fn Dataset::find_traces(
  self : Dataset,
  field : String,
  minimum : Int,
  maximum : Int,
) -> Array[Int] raise {
  if minimum > maximum {
    raise Failure("invalid header range")
  }
  ignore(field_location(field))
  let found = []
  for i in 0..<self.trace_count() {
    let v = self.trace(i).field(field)
    if v >= minimum && v <= maximum {
      found.push(i)
    }
  }
  found
}

///|
pub(all) struct TraceGroup {
  value : Int
  indices : Array[Int]
} derive(ToJson)

///|
pub extend TraceGroup with ToJson::{to_json}

///|
/// Group by an unscaled header value; groups retain first-occurrence order.
pub fn Dataset::groups(
  self : Dataset,
  field : String,
) -> Array[TraceGroup] raise {
  ignore(field_location(field))
  let lookup : Map[Int, Int] = Map([])
  let result : Array[TraceGroup] = []
  for i in 0..<self.trace_count() {
    let value = self.trace(i).field(field)
    if lookup.get(value) is Some(k) {
      result[k].indices.push(i)
    } else {
      lookup[value] = result.length()
      result.push({ value, indices: [i], })
    }
  }
  result
}

///|
// Keep time scalar unchanged: changing it would also change lag/mute fields.
// A window that cannot represent its new delay exactly is rejected, not rounded.
fn window_trace(t : Trace, first : Int, count : Int) -> Trace raise {
  if first < 0 || count < 1 || first > t.count || count > t.count - first {
    raise Failure("window outside trace")
  }
  let time_scale = if t.revision == 0 {
    1.0
  } else {
    scalar(t.field("time_scalar"))
  }
  let raw_delay = t.field("delay_ms").to_double() +
    first.to_double() * t.dt / 1000.0 / time_scale
  let nearest = raw_delay.round()
  if (raw_delay - nearest).abs() > 1.0e-8 ||
    nearest < -32768.0 ||
    nearest > 32767.0 {
    raise Failure("window delay not representable with existing time scalar")
  }
  let head = Array::makei(240, i => t.head[i])
  put_uint(
    head,
    108,
    2,
    nearest.to_int64().reinterpret_as_uint64(),
    t.byte_order,
  )
  put_uint(
    head,
    114,
    2,
    if count <= 65535 {
      count.to_uint64()
    } else {
      0UL
    },
    t.byte_order,
  )
  let width = sample_width(t.code)
  {
    ..t,
    head: Bytes::from_array(head),
    payload: slice(t.payload, first * width, count * width),
    count,
  }
}

///|
/// Same sample-index window on every trace; rejects any too-short trace. Raw
/// sample bytes remain exact, including int64 and nonfinite IEEE bit patterns.
pub fn Dataset::window(
  self : Dataset,
  first : Int,
  count : Int,
) -> Dataset raise {
  let traces = Array::makei(self.trace_count(), i => {
    window_trace(self.trace(i), first, count)
  })
  assemble(self.header, traces, self.extensions)
}

///|
/// Convert samples without endian/revision changes. No silent integer rounding
/// or lossy int64-to-Double conversion. Identical format returns the same data.
pub fn Dataset::convert_samples(self : Dataset, code : Int) -> Dataset raise {
  ignore(sample_width(code))
  if code == self.header.sample_code {
    return self
  }
  let prefix = Array::makei(3600, i => self.header.raw[i])
  put_uint(prefix, 3224, 2, code.to_uint64(), self.header.endian)
  let header = parse_header(
    Bytes::from_array(prefix),
    endian=self.header.endian,
    text_encoding=self.header.text_encoding,
  )
  let traces = Array::makei(self.trace_count(), i => {
    let t = self.trace(i)
    let samples = Array::makei(t.count, j => {
      let sample = t.sample(j)
      if code == 1 || code == 5 || code == 6 {
        sample
      } else {
        match sample {
          Signed(v) => Signed(v)
          Real(v) => {
            if !finite(v) || v.abs() > 9007199254740992.0 || v != v.trunc() {
              raise Failure("float cannot be converted to exact integer")
            }
            Signed(v.to_int64())
          }
        }
      }
    })
    { ..t, payload: encode_samples(samples, code, t.byte_order), code, }
  })
  assemble(header, traces, self.extensions)
}

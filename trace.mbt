///|
/// Owned raw trace. Sample bytes are retained exactly until explicitly changed.
pub struct Trace {
  priv head : Bytes
  priv payload : Bytes
  priv count : Int
  priv dt : Double
  priv byte_order : Endian
  priv code : Int
  priv revision : Int
}

///|
fn field_location(name : String) -> (Int, Int) raise {
  match name {
    "sequence_line" => (0, 4)
    "sequence_file" => (4, 4)
    "field_record" => (8, 4)
    "trace_in_record" => (12, 4)
    "source_point" => (16, 4)
    "ensemble" => (20, 4)
    "trace_in_ensemble" => (24, 4)
    "identification" => (28, 2)
    "offset" => (36, 4)
    "receiver_elevation" => (40, 4)
    "source_elevation" => (44, 4)
    "source_depth" => (48, 4)
    "elevation_scalar" => (68, 2)
    "coordinate_scalar" => (70, 2)
    "source_x" => (72, 4)
    "source_y" => (76, 4)
    "group_x" => (80, 4)
    "group_y" => (84, 4)
    "coordinate_units" => (88, 2)
    "delay_ms" => (108, 2)
    "weighting" => (168, 2)
    "cdp_x" => (180, 4)
    "cdp_y" => (184, 4)
    "inline" => (188, 4)
    "crossline" => (192, 4)
    "shotpoint" => (196, 4)
    "shotpoint_scalar" => (200, 2)
    "time_scalar" => (214, 2)
    _ => raise Failure("unknown trace field: " + name)
  }
}

///|
pub fn Trace::samples(self : Trace) -> Int {
  self.count
}

///|
pub fn Trace::interval_us(self : Trace) -> Double {
  self.dt
}

///|
/// Raw signed header value, before coordinate/elevation/time scaling.
pub fn Trace::field(self : Trace, name : String) -> Int raise {
  let (pos, w) = field_location(name)
  if self.revision == 0 && pos >= 180 {
    raise Failure("field not standardized in rev0")
  }
  int_at(self.head, pos, w, self.byte_order).to_int()
}

///|
pub fn Trace::raw_header(self : Trace) -> Bytes {
  self.head
}

///|
pub fn Trace::raw_samples(self : Trace) -> Bytes {
  self.payload
}

///|
pub fn Trace::sample(self : Trace, index : Int) -> Sample raise {
  if index < 0 || index >= self.count {
    raise Failure("sample index outside trace")
  }
  decode_sample(
    self.payload,
    index * sample_width(self.code),
    self.code,
    self.byte_order,
  )
}

///|
/// Build a trace at the file's byte order/format. fields use named signed raw
/// values, not scaled coordinates. Unknown fields and narrowed overflow raise.
pub fn make_trace(
  header : FileHeader,
  samples : Array[Sample],
  interval_us? : Double,
  fields? : Map[String, Int] = Map([]),
) -> Trace raise {
  let n = samples.length()
  let dt = interval_us.unwrap_or(header.interval_us)
  if n < 1 || n > 1000000 || !finite(dt) || dt <= 0.0 {
    raise Failure("invalid trace count or interval")
  }
  if (n > 65535 || dt > 65535.0 || dt != dt.trunc()) &&
    !(header.revision == 2 &&
    header.fixed_length &&
    n == header.samples &&
    dt == header.interval_us) {
    raise Failure(
      "wide trace needs fixed rev2 binary count/interval; extension headers unsupported",
    )
  }
  let out = Array::make(240, b'\x00')
  for name, value in fields {
    let (pos, w) = field_location(name)
    if header.revision == 0 && pos >= 180 {
      raise Failure("field not standardized in rev0")
    }
    if w == 2 && (value < -32768 || value > 32767) {
      raise Failure("16-bit trace field overflow")
    }
    put_uint(
      out,
      pos,
      w,
      value.to_int64().reinterpret_as_uint64(),
      header.endian,
    )
  }
  put_uint(
    out,
    114,
    2,
    if n <= 65535 {
      n.to_uint64()
    } else {
      0UL
    },
    header.endian,
  )
  put_uint(
    out,
    116,
    2,
    if dt <= 65535.0 && dt == dt.trunc() {
      dt.to_uint64()
    } else {
      0UL
    },
    header.endian,
  )
  {
    head: Bytes::from_array(out),
    payload: encode_samples(samples, header.sample_code, header.endian),
    count: n,
    dt,
    byte_order: header.endian,
    code: header.sample_code,
    revision: header.revision,
  }
}

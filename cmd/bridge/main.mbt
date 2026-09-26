///|
extern "js" fn fail_string(message : String) -> String =
  #| (message) => { throw new Error(message); }

///|
extern "js" fn fail_bytes(message : String) -> Bytes =
  #| (message) => { throw new Error(message); }

///|
fn object(text : String) -> Map[String, Json] raise {
  if text.length() > 8000000 {
    raise Failure("options exceed eight million characters")
  }
  match @json.parse(text) {
    Object(o) => o
    _ => raise Failure("options must be an object")
  }
}

///|
fn[T : @json.FromJson] required(o : Map[String, Json], key : String) -> T raise {
  match o.get(key) {
    Some(j) => @json.from_json(j)
    None => raise Failure("missing option: " + key)
  }
}

///|
fn[T : @json.FromJson] optional(
  o : Map[String, Json],
  key : String,
  fallback : T,
) -> T raise {
  match o.get(key) {
    Some(j) => @json.from_json(j)
    None => fallback
  }
}

///|
fn endian(o : Map[String, Json]) -> @lib.Endian raise {
  let name : String = optional(o, "endian", "big")
  match name.to_lower() {
    "big" => @lib.Big
    "little" => @lib.Little
    _ => raise Failure("endian must be big or little")
  }
}

///|
// FromJson[Int] truncates fractions. Source indices, fields and budgets must
// instead be exact Int32 values; amplitude samples have their own Int64 path.
fn integer(j : Json, key : String) -> Int raise {
  let value : Double = @json.from_json(j)
  if value.is_nan() ||
    value.is_inf() ||
    value.floor() != value ||
    value < -2147483648.0 ||
    value > 2147483647.0 {
    raise Failure(key + " must be an exact Int32 integer")
  }
  value.to_int()
}

///|
fn required_int(o : Map[String, Json], key : String) -> Int raise {
  integer(required(o, key), key)
}

///|
fn optional_int(
  o : Map[String, Json],
  key : String,
  fallback : Int,
) -> Int raise {
  match o.get(key) {
    Some(j) => integer(j, key)
    None => fallback
  }
}

///|
fn indices(o : Map[String, Json]) -> Array[Int] raise {
  let values : Array[Json] = required(o, "traces")
  values.map(j => integer(j, "traces"))
}

///|
fn fields(o : Map[String, Json]) -> Map[String, Int] raise {
  let values : Map[String, Json] = optional(o, "fields", Map([]))
  let out : Map[String, Int] = Map([])
  for key, j in values {
    out[key] = integer(j, key)
  }
  out
}

///|
fn quality(d : @lib.Dataset, o : Map[String, Json]) -> @lib.QualityReport raise {
  for key in o.keys() {
    if ![
        "command", "endian", "text_encoding", "traces", "group_by", "dead_threshold",
        "clip_threshold", "weighted", "max_details", "max_groups", "legacy_revision_one",
      ].contains(key) {
      raise Failure("unknown QC option: " + key)
    }
  }
  let selected = if o.contains("traces") { Some(indices(o)) } else { None }
  let group : String? = if o.contains("group_by") {
    Some(required(o, "group_by"))
  } else {
    None
  }
  d.quality_check(
    traces?=selected,
    group_by?=group,
    dead_threshold=optional(o, "dead_threshold", 0.0),
    clip_threshold=optional(o, "clip_threshold", 0.0),
    weighted=optional(o, "weighted", false),
    max_details=optional_int(o, "max_details", 256),
    max_groups=optional_int(o, "max_groups", 65536),
  )
}

///|
fn read(data : Bytes, o : Map[String, Json]) -> @lib.Dataset raise {
  let legacy_revision_one : Bool = optional(o, "legacy_revision_one", false)
  if o.contains("text_encoding") {
    let encoding : String = required(o, "text_encoding")
    if o.contains("endian") {
      @lib.decode(
        data,
        endian=endian(o),
        text_encoding=encoding,
        legacy_revision_one~,
      )
    } else {
      @lib.decode(data, text_encoding=encoding, legacy_revision_one~)
    }
  } else if o.contains("endian") {
    @lib.decode(data, endian=endian(o), legacy_revision_one~)
  } else {
    @lib.decode(data, legacy_revision_one~)
  }
}

///|
fn sample_json(sample : @lib.Sample) -> Json {
  match sample {
    @lib.Signed(v) => v.to_string().to_json()
    @lib.Real(v) =>
      if v.is_nan() || v.is_inf() {
        { "nonfinite": v.to_string().to_json() }
      } else {
        v.to_json()
      }
  }
}

///|
fn do_report(data : Bytes, options : String) -> String raise {
  let o = object(options)
  let d = read(data, o)
  let h = d.header
  let command : String = optional(o, "command", "inspect")
  let result : Json = match command {
    "inspect" | "validate" => {
      let bad = if command == "validate" { d.nonfinite_samples() } else { 0 }
      if bad > 0 {
        raise Failure("validation found \{bad} nonfinite IEEE samples")
      }
      {
        "revision": h.revision.to_json(),
        "raw_revision_word": h.raw_revision_word.to_json(),
        "assumed_legacy_revision_one": h.assumed_legacy_revision_one.to_json(),
        "endian": (if h.endian == @lib.Big { "big" } else { "little" }).to_json(),
        "sample_code": h.sample_code.to_json(),
        "trace_count": d.trace_count().to_json(),
        "fixed_length": h.fixed_length.to_json(),
        "sample_interval_us": h.interval_us.to_json(),
        "text_encoding": h.text_encoding.to_json(),
        "text": @lib.decode_text(
          Bytes::makei(3200, i => h.raw[i]),
          h.text_encoding,
        ).to_json(),
        "extensions": d
        .extended_headers()
        .map(b => @lib.decode_text(b, h.text_encoding))
        .to_json(),
        "index": d.trace_index().to_json(),
        "sample_validation_performed": (command == "validate").to_json(),
      }
    }
    "groups" => d.groups(required(o, "field")).to_json()
    "find" =>
      d
      .find_traces(
        required(o, "field"),
        required_int(o, "minimum"),
        required_int(o, "maximum"),
      )
      .to_json()
    "stats" =>
      d
      .trace(required_int(o, "trace"))
      .statistics(
        dead_threshold=optional(o, "dead_threshold", 0.0),
        clip_threshold=optional(o, "clip_threshold", 0.0),
        weighted=optional(o, "weighted", false),
      )
      .to_json()
    "qc" => quality(d, o).to_json()
    "qc-csv" => {
      let result = quality(d, o)
      {
        "text": result.issues_csv().to_json(),
        "status": result.status.to_json(),
      }
    }
    "csv" => { "text": d.csv(indices(o)).to_json() }
    "svg" => { "text": d.trace(required_int(o, "trace")).svg().to_json() }
    "trace" => {
      let t = d.trace(required_int(o, "trace"))
      let first = optional_int(o, "first", 0)
      let count = optional_int(o, "count", t.samples())
      if first < 0 ||
        count < 0 ||
        count > 100000 ||
        first > t.samples() ||
        count > t.samples() - first {
        raise Failure("invalid trace range; maximum 100000 per request")
      }
      let fields : Map[String, Json] = Map([])
      for
        key in [
          "sequence_line", "sequence_file", "field_record", "trace_in_record", "ensemble",
          "coordinate_scalar", "source_x", "source_y", "group_x", "group_y", "coordinate_units",
          "delay_ms", "weighting",
        ] {
        fields[key] = t.field(key).to_json()
      }
      if h.revision > 0 {
        for key in ["cdp_x", "cdp_y", "inline", "crossline", "time_scalar"] {
          fields[key] = t.field(key).to_json()
        }
      }
      {
        "samples": Array::makei(count, i => sample_json(t.sample(first + i))).to_json(),
        "times_seconds": Array::makei(count, i => t.time_seconds(first + i)).to_json(),
        "interval_us": t.interval_us().to_json(),
        "fields": fields.to_json(),
      }
    }
    "coordinate" => {
      let t = d.trace(required_int(o, "trace"))
      let field : String = required(o, "field")
      let degrees : Bool = optional(o, "degrees", false)
      (if degrees {
        t.coordinate_degrees(field)
      } else {
        t.scaled_field(field)
      }).to_json()
    }
    _ => raise Failure("unknown report command")
  }
  result.stringify()
}

///|
fn do_transform(data : Bytes, options : String) -> Bytes raise {
  let o = object(options)
  let d = read(data, o)
  let command : String = required(o, "command")
  let out = match command {
    "copy" => d
    "select" => d.select(indices(o))
    "filter" =>
      d.select(
        d.find_traces(
          required(o, "field"),
          required_int(o, "minimum"),
          required_int(o, "maximum"),
        ),
      )
    "window" => d.window(required_int(o, "first"), required_int(o, "count"))
    "convert" => d.convert_samples(required_int(o, "sample_code"))
    _ => raise Failure("unknown transform command")
  }
  out.encode()
}

///|
fn do_new(options : String) -> Bytes raise {
  let o = object(options)
  let rows : Array[Map[String, Json]] = required(o, "traces")
  if rows.is_empty() || rows.length() > 1000000 {
    raise Failure("invalid trace count")
  }
  let code = optional_int(o, "sample_code", 5)
  let revision = optional_int(o, "revision", 1)
  let interval : Double = required(o, "interval_us")
  let first : Array[Json] = required(rows[0], "samples")
  let text : String = optional(
    o,
    "text",
    "C 1 MOONSEGY SYNTHETIC SEG-Y_REV\{revision}.0",
  )
  let encoding : String = optional(o, "text_encoding", "ASCII")
  let h = @lib.make_header(
    first.length(),
    interval,
    code,
    revision~,
    endian=endian(o),
    fixed_length=revision != 0,
    text~,
    text_encoding=encoding,
  )
  let traces = rows.map(row => {
    let samples : Array[Json] = required(row, "samples")
    if samples.length() > 1000000 {
      raise Failure("trace too long")
    }
    let values = samples.map(j => {
      if code == 1 || code == 5 || code == 6 {
        @lib.Real(@json.from_json(j))
      } else {
        let value = match j {
          String(s) => @string.parse_int64(s)
          _ => {
            let x : Double = @json.from_json(j)
            if x.is_nan() ||
              x.is_inf() ||
              x.abs() > 9007199254740992.0 ||
              x != x.trunc() {
              raise Failure(
                "integer outside exact JSON-number range; supply decimal string",
              )
            }
            x.to_int64()
          }
        }
        @lib.Signed(value)
      }
    })
    @lib.make_trace(
      h,
      values,
      interval_us=optional(row, "interval_us", interval),
      fields=fields(row),
    )
  })
  let blocks : Array[String] = optional(o, "extensions", [])
  @lib.create(
    h,
    traces,
    extended_headers=blocks.map(s => @lib.encode_text(s, encoding)),
  ).encode()
}

///|
pub fn report(data : Bytes, options : String) -> String {
  do_report(data, options) catch {
    e => fail_string(@debug.to_string(e))
  }
}

///|
pub fn transform(data : Bytes, options : String) -> Bytes {
  do_transform(data, options) catch {
    e => fail_bytes(@debug.to_string(e))
  }
}

///|
pub fn new_file(options : String) -> Bytes {
  do_new(options) catch {
    e => fail_bytes(@debug.to_string(e))
  }
}

///|
fn main {

}

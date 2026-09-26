///|
pub(all) struct TraceIndex {
  header_offset : Int
  sample_offset : Int
  samples : Int
  interval_us : Double
} derive(ToJson)

///|
pub extend TraceIndex with ToJson::{to_json}

///|
pub struct Dataset {
  header : FileHeader
  priv raw : Bytes
  priv index : Array[TraceIndex]
  priv extensions : Array[Bytes]
}

///|
fn extended_text(data : Bytes, encoding : String) -> String raise {
  let text = decode_text(data, encoding)
  let compact = StringBuilder()
  for c in text {
    if !c.is_whitespace() {
      compact.write_char(c)
    }
  }
  let key = compact.to_string().to_upper()
  if key.contains("TRACEHEADERMAPPING") ||
    key.contains("TRACEHEADERLAYOUT") ||
    key.contains("SEG:USERDATA") {
    raise Failure("custom trace mapping or binary user stanza is unsupported")
  }
  text
}

///|
/// Scan fixed/variable traces with strict bounds; does not expand all samples.
/// Undefined extended-text counts stop only at the SEG EndText marker.
pub fn decode(
  data : Bytes,
  endian? : Endian,
  text_encoding? : String,
  legacy_revision_one? : Bool = false,
) -> Dataset raise {
  let h = match (endian, text_encoding) {
    (Some(e), Some(t)) =>
      parse_header(data, endian=e, text_encoding=t, legacy_revision_one~)
    (Some(e), None) => parse_header(data, endian=e, legacy_revision_one~)
    (None, Some(t)) => parse_header(data, text_encoding=t, legacy_revision_one~)
    (None, None) => parse_header(data, legacy_revision_one~)
  }
  let e = h.endian
  let extensions = []
  let mut pos = 3600
  let mut count = h.extended_count
  if h.first_trace != 0 {
    if h.first_trace < 3600 || (h.first_trace - 3600) % 3200 != 0 {
      raise Failure("unsupported first-trace layout")
    }
    count = (h.first_trace - 3600) / 3200
    if count > 1024 {
      raise Failure("too many extended text blocks")
    }
  }
  if count >= 0 {
    need(data, pos, count * 3200)
    for _ in 0..<count {
      let block = slice(data, pos, 3200)
      ignore(extended_text(block, h.text_encoding))
      extensions.push(block)
      pos += 3200
    }
  } else {
    while true {
      if extensions.length() >= 1024 {
        raise Failure("EndText not found in 1024 blocks")
      }
      need(data, pos, 3200)
      let block = slice(data, pos, 3200)
      let text = extended_text(block, h.text_encoding)
      extensions.push(block)
      pos += 3200
      // Standard EndText stanza permits spacing after the namespace colon.
      let compact = StringBuilder()
      for c in text {
        if !c.is_whitespace() {
          compact.write_char(c)
        }
      }
      if compact.to_string().to_upper().contains("((SEG:ENDTEXT))") {
        break
      }
    }
  }
  let width = sample_width(h.sample_code)
  let index = []
  let mut total = 0
  while pos < data.length() {
    need(data, pos, 240)
    let raw_count = uint_at(data, pos + 114, 2, e).to_int()
    let raw_dt = uint_at(data, pos + 116, 2, e).to_double()
    let n = if h.fixed_length { h.samples } else { raw_count }
    let dt = if h.fixed_length || raw_dt == 0.0 {
      h.interval_us
    } else {
      raw_dt
    }
    if n < 1 || n > 1000000 || dt <= 0.0 || !finite(dt) {
      raise Failure("invalid trace sample count/interval")
    }
    if h.fixed_length &&
      (
        (raw_count != 0 && n <= 65535 && raw_count != n) ||
        (raw_dt != 0.0 && raw_dt != dt)
      ) {
      raise Failure("fixed trace contradicts binary header")
    }
    need(data, pos + 240, n * width)
    index.push({
      header_offset: pos,
      sample_offset: pos + 240,
      samples: n,
      interval_us: dt,
    })
    total += n
    if index.length() > 1000000 || total > 16000000 {
      raise Failure("trace/sample resource limit exceeded")
    }
    pos += 240 + n * width
  }
  if index.is_empty() {
    raise Failure("no data traces")
  }
  if h.declared_traces != 0UL && h.declared_traces != index.length().to_uint64() {
    raise Failure("declared trace count mismatch")
  }
  { header: h, raw: data, index, extensions, }
}

///|
pub fn Dataset::trace_count(self : Dataset) -> Int {
  self.index.length()
}

///|
pub fn Dataset::trace_index(self : Dataset) -> Array[TraceIndex] {
  self.index.copy()
}

///|
pub fn Dataset::extended_headers(self : Dataset) -> Array[Bytes] {
  self.extensions.copy()
}

///|
/// Exact byte copy (Bytes is immutable); does not canonicalize unknown fields.
pub fn Dataset::encode(self : Dataset) -> Bytes {
  self.raw
}

///|
pub fn Dataset::trace(self : Dataset, index : Int) -> Trace raise {
  if index < 0 || index >= self.index.length() {
    raise Failure("trace index outside dataset")
  }
  let t = self.index[index]
  {
    head: slice(self.raw, t.header_offset, 240),
    payload: slice(
      self.raw,
      t.sample_offset,
      t.samples * sample_width(self.header.sample_code),
    ),
    count: t.samples,
    dt: t.interval_us,
    byte_order: self.header.endian,
    code: self.header.sample_code,
    revision: self.header.revision,
  }
}

///|
// Recompute structural fields only; retain all other raw header bytes. A change
// of byte order or revision needs explicit field semantics and is not guessed.
fn assemble(
  header : FileHeader,
  traces : Array[Trace],
  extensions : Array[Bytes],
) -> Dataset raise {
  if traces.is_empty() ||
    traces.length() > 1000000 ||
    extensions.length() > 1024 ||
    (header.revision == 0 && !extensions.is_empty()) {
    raise Failure("invalid assembly counts")
  }
  let width = sample_width(header.sample_code)
  let n = traces[0].count
  let dt = traces[0].dt
  let fixed = header.revision != 0 &&
    traces.all(t => t.count == n && t.dt == dt)
  let first = 3600 + extensions.length() * 3200
  let mut size = first
  let mut total = 0
  for t in traces {
    if t.byte_order != header.endian ||
      t.code != header.sample_code ||
      t.revision != header.revision {
      raise Failure("trace encoding/header mismatch")
    }
    if !fixed && (t.count > 65535 || t.dt > 65535.0 || t.dt != t.dt.trunc()) {
      raise Failure("variable trace needs unsupported wide extension")
    }
    size += 240 + t.count * width
    total += t.count
    if size > 268435456 || total > 16000000 {
      raise Failure("assembled file exceeds resource limit")
    }
  }
  let out = Array::make(size, b'\x00')
  copy_into(out, 0, header.raw)
  let e = header.endian
  put_uint(
    out,
    3216,
    2,
    if dt <= 65535.0 && dt == dt.trunc() {
      dt.to_uint64()
    } else {
      0UL
    },
    e,
  )
  put_uint(out, 3220, 2, if n <= 65535 { n.to_uint64() } else { 0UL }, e)
  if header.revision >= 1 {
    put_uint(out, 3502, 2, if fixed { 1UL } else { 0UL }, e)
    put_uint(out, 3504, 2, extensions.length().to_uint64(), e)
  }
  if header.revision == 2 {
    put_uint(out, 3268, 4, n.to_uint64(), e)
    put_uint(out, 3272, 8, dt.reinterpret_as_uint64(), e)
    put_uint(out, 3512, 8, traces.length().to_uint64(), e)
    put_uint(out, 3520, 8, first.to_uint64(), e)
  }
  let mut pos = 3600
  for block in extensions {
    ignore(extended_text(block, header.text_encoding))
    copy_into(out, pos, block)
    pos += 3200
  }
  for t in traces {
    copy_into(out, pos, t.head)
    copy_into(out, pos + 240, t.payload)
    pos += 240 + t.payload.length()
  }
  decode(
    Bytes::from_array(out),
    endian=e,
    text_encoding=header.text_encoding,
    legacy_revision_one=header.assumed_legacy_revision_one,
  )
}

///|
/// Assemble same-format traces, derive structural counts and validate by scan.
pub fn create(
  header : FileHeader,
  traces : Array[Trace],
  extended_headers? : Array[Bytes] = [],
) -> Dataset raise {
  assemble(header, traces, extended_headers)
}

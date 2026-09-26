///|
/// Immutable decoded file prefix. Raw is the original 3600-byte prefix;
/// extended blocks and traces are parsed separately. Units are microseconds.
pub struct FileHeader {
  endian : Endian
  revision : Int
  raw_revision_word : Int
  assumed_legacy_revision_one : Bool
  sample_code : Int
  samples : Int
  interval_us : Double
  fixed_length : Bool
  extended_count : Int
  declared_traces : UInt64
  first_trace : Int
  text_encoding : String
  raw : Bytes
}

///|
fn known_code(code : Int) -> Bool {
  code == 1 ||
  code == 2 ||
  code == 3 ||
  code == 5 ||
  code == 6 ||
  code == 7 ||
  code == 8 ||
  code == 9
}

///|
/// Detect byte order from rev2 sentinel or supported format code. Explicit
/// endian still must agree with a recognized sentinel. Pair-swapped is rejected.
pub fn parse_header(
  data : Bytes,
  endian? : Endian,
  text_encoding? : String,
  legacy_revision_one? : Bool = false,
) -> FileHeader raise {
  need(data, 0, 3600)
  if data.length() > 268435456 {
    raise Failure("file exceeds 256 MiB")
  }
  let marker = uint_at(data, 3296, 4, Big)
  if marker == 0x02010403UL || marker == 0x03040102UL {
    raise Failure("pair-swapped byte order is unsupported")
  }
  let detected = if marker == 0x01020304UL {
    Some(Big)
  } else if marker == 0x04030201UL {
    Some(Little)
  } else {
    None
  }
  let e = match (endian, detected) {
    (Some(a), Some(b)) => {
      if a != b {
        raise Failure("explicit byte order conflicts with sentinel")
      }
      a
    }
    (Some(a), None) => a
    (None, Some(b)) => b
    (None, None) => {
      let big = known_code(uint_at(data, 3224, 2, Big).to_int())
      let little = known_code(uint_at(data, 3224, 2, Little).to_int())
      if big == little {
        raise Failure("cannot infer endian from unsupported/ambiguous format")
      }
      if big {
        Big
      } else {
        Little
      }
    }
  }
  let code = uint_at(data, 3224, 2, e).to_int()
  ignore(sample_width(code))
  // Older writers treat the revision pair as an endian uint16. Also accept
  // literal major/minor octets for little-endian rev2 as specified by Table 2.
  let word = uint_at(data, 3500, 2, e).to_int()
  // Some old exports write big-endian integer 1 (00 01), not the standard
  // revision-1.0 octets 01 00 at zero-based byte 3500. Never guess by default.
  let assumed = word == 1 && e == Big && marker == 0UL && legacy_revision_one
  let revision = match word {
    0 => 0
    256 => 1
    512 => 2
    1 | 2 =>
      if e == Little || assumed {
        word
      } else {
        raise Failure("unsupported revision")
      }
    _ => raise Failure("unsupported SEG-Y revision (only 0/1.0/2.0)")
  }
  let mut samples = uint_at(data, 3220, 2, e).to_int()
  let mut interval = uint_at(data, 3216, 2, e).to_double()
  let mut declared = 0UL
  let mut first = 0
  if revision == 2 {
    if marker != 0UL && detected is None {
      raise Failure("unsupported rev2 byte-order sentinel")
    }
    let ext = uint_at(data, 3268, 4, e)
    if ext > 1000000UL {
      raise Failure("extended sample count exceeds one million")
    }
    if ext != 0UL {
      samples = ext.to_int()
    }
    let dt = real_at(data, 3272, 8, e)
    if dt != 0.0 {
      interval = dt
    }
    if uint_at(data, 3506, 4, e) != 0UL {
      raise Failure("additional trace headers are unsupported")
    }
    declared = uint_at(data, 3512, 8, e)
    if declared > 1000000UL {
      raise Failure("declared traces exceed one million")
    }
    let offset = uint_at(data, 3520, 8, e)
    if offset > 268435456UL {
      raise Failure("first trace offset exceeds limit")
    }
    first = offset.to_int()
    if int_at(data, 3528, 4, e) != 0L {
      raise Failure("data trailer is unsupported")
    }
  }
  let fixed = if revision == 0 { 0 } else { uint_at(data, 3502, 2, e).to_int() }
  let extensions = if revision == 0 {
    0
  } else {
    int_at(data, 3504, 2, e).to_int()
  }
  if (fixed != 0 && fixed != 1) || extensions < -1 || extensions > 1024 {
    raise Failure("invalid fixed flag or extended header count")
  }
  if !finite(interval) ||
    interval < 0.0 ||
    (fixed == 1 && (interval <= 0.0 || samples == 0)) {
    raise Failure("invalid nominal sample interval/count")
  }
  let encoding = match text_encoding {
    Some(x) => encoding_name(x)
    None => detect_text(data)
  }
  ignore(decode_text(slice(data, 0, 3200), encoding))
  {
    endian: e,
    revision,
    raw_revision_word: word,
    assumed_legacy_revision_one: assumed,
    sample_code: code,
    samples,
    interval_us: interval,
    fixed_length: fixed == 1,
    extended_count: extensions,
    declared_traces: declared,
    first_trace: first,
    text_encoding: encoding,
    raw: slice(data, 0, 3600),
  }
}

///|
/// Construct a standard prefix; revision 0 forbids extended headers and fixed
/// flag. Full dataset writers later fill first-trace offset and trace count.
pub fn make_header(
  samples : Int,
  interval_us : Double,
  sample_code : Int,
  endian? : Endian = Big,
  revision? : Int = 1,
  fixed_length? : Bool = true,
  text? : String = "C 1 MOONSEGY - SYNTHETIC DATA",
  text_encoding? : String = "ASCII",
  extended_count? : Int = 0,
) -> FileHeader raise {
  ignore(sample_width(sample_code))
  if samples < 0 ||
    samples > 1000000 ||
    !finite(interval_us) ||
    interval_us < 0.0 ||
    revision < 0 ||
    revision > 2 ||
    extended_count < 0 ||
    extended_count > 1024 ||
    (revision == 0 && (fixed_length || extended_count != 0)) {
    raise Failure("invalid header construction options")
  }
  if revision < 2 &&
    (
      samples > 65535 ||
      interval_us > 65535.0 ||
      interval_us != interval_us.trunc()
    ) {
    raise Failure("rev0/1 nominal fields exceed 16-bit integer range")
  }
  let out = Array::make(3600, b'\x00')
  copy_into(out, 0, encode_text(text, text_encoding))
  if revision == 2 && !text.contains("SEG-Y_REV2.0") {
    if text.length() > 3040 {
      raise Failure("long rev2 text must include SEG-Y_REV2.0")
    }
    // Canonical writers identify their revision in textual row 39, leaving
    // supplied earlier rows untouched (SEG section 4).
    let marker = encode_text("C39 SEG-Y_REV2.0", text_encoding)
    for i in 0..<80 {
      out[3040 + i] = marker[i]
    }
  }
  put_uint(
    out,
    3216,
    2,
    if interval_us <= 65535.0 && interval_us == interval_us.trunc() {
      interval_us.to_uint64()
    } else {
      0UL
    },
    endian,
  )
  put_uint(
    out,
    3220,
    2,
    if samples <= 65535 {
      samples.to_uint64()
    } else {
      0UL
    },
    endian,
  )
  put_uint(out, 3224, 2, sample_code.to_uint64(), endian)
  put_uint(out, 3500, 2, (revision * 256).to_uint64(), endian)
  put_uint(out, 3502, 2, if fixed_length { 1UL } else { 0UL }, endian)
  put_uint(out, 3504, 2, extended_count.to_uint64(), endian)
  if revision == 2 {
    // Rev2 defines major/minor as separate octets, not an endian integer.
    // Readers also accept historical little-endian uint16 writer convention.
    out[3500] = b'\x02'
    out[3501] = b'\x00'
    put_uint(out, 3268, 4, samples.to_uint64(), endian)
    put_uint(out, 3272, 8, interval_us.reinterpret_as_uint64(), endian)
    put_uint(out, 3296, 4, 0x01020304UL, endian)
  }
  parse_header(Bytes::from_array(out), endian~, text_encoding~)
}

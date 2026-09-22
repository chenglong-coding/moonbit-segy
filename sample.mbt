///|
/// Integers remain exact, including int64. Real includes raw IEEE nonfinite
/// values for inspection/copy; numerical analysis must call as_double().
pub(all) enum Sample {
  Signed(Int64)
  Real(Double)
}

///|
pub fn Sample::as_double(self : Sample) -> Double raise {
  match self {
    Signed(v) => {
      if v < -9007199254740992L || v > 9007199254740992L {
        raise Failure("integer exceeds exact Double analysis range")
      }
      v.to_double()
    }
    Real(v) => {
      if !finite(v) {
        raise Failure("nonfinite sample cannot be analyzed")
      }
      v
    }
  }
}

///|
/// Codes 1,2,3,5,6,7,8,9. Obsolete fixed-with-gain and unsigned codes rejected.
pub fn sample_width(code : Int) -> Int raise {
  match code {
    1 | 2 | 5 => 4
    3 => 2
    6 | 9 => 8
    7 => 3
    8 => 1
    _ => raise Failure("unsupported SEG-Y sample code")
  }
}

///|
/// Decode one unweighted sample at a byte offset; not a sample index.
pub fn decode_sample(
  data : Bytes,
  offset : Int,
  code : Int,
  endian : Endian,
) -> Sample raise {
  let w = sample_width(code)
  match code {
    1 => {
      let bits = uint_at(data, offset, 4, endian)
      let fraction = (bits & 0xffffffUL).to_double() / 16777216.0
      let exponent = ((bits >> 24) & 127UL).to_int() - 64
      let sign = if (bits & 0x80000000UL) == 0UL { 1.0 } else { -1.0 }
      Real(sign * fraction * @math.pow(16.0, exponent.to_double()))
    }
    5 | 6 => Real(real_at(data, offset, w, endian))
    _ => Signed(int_at(data, offset, w, endian))
  }
}

///|
// SEG Appendix E: sign, excess-64 radix-16 exponent, 24-bit fraction.
// Normalize and round nearest, half away from zero. Reject under/overflow;
// unlike silent clamping this tells callers the format cannot retain the input.
fn ibm_bits(value : Double) -> UInt64 raise {
  if value == 0.0 {
    return 0UL
  }
  let mut a = value.abs()
  let mut exponent = 64
  while a >= 1.0 && exponent <= 127 {
    a /= 16.0
    exponent += 1
  }
  while a < 0.0625 && exponent >= 0 {
    a *= 16.0
    exponent -= 1
  }
  if exponent < 0 || exponent > 127 {
    raise Failure("IBM32 exponent out of range")
  }
  let mut fraction = (a * 16777216.0 + 0.5).to_uint64()
  if fraction == 16777216UL {
    fraction = 1048576UL
    exponent += 1
  }
  if exponent > 127 {
    raise Failure("IBM32 rounding overflow")
  }
  let sign = if value < 0.0 { 0x80000000UL } else { 0UL }
  sign | (exponent.to_uint64() << 24) | fraction
}

///|
fn put_sample(
  out : Array[Byte],
  pos : Int,
  code : Int,
  sample : Sample,
  endian : Endian,
) -> Unit raise {
  let w = sample_width(code)
  if code == 1 || code == 5 || code == 6 {
    let v = sample.as_double()
    let bits = if code == 1 {
      ibm_bits(v)
    } else if code == 5 {
      let f = Float::from_double(v)
      if f.is_inf() || (v != 0.0 && f == 0.0) {
        raise Failure("IEEE32 overflow or underflow to zero")
      }
      f.reinterpret_as_uint().to_uint64()
    } else {
      v.reinterpret_as_uint64()
    }
    put_uint(out, pos, w, bits, endian)
  } else {
    guard sample is Signed(v) else {
      raise Failure("integer encoding requires Signed samples")
    }
    if w < 8 && (v < -(1L << (8 * w - 1)) || v >= 1L << (8 * w - 1)) {
      raise Failure("signed sample outside format range")
    }
    put_uint(out, pos, w, v.reinterpret_as_uint64(), endian)
  }
}

///|
/// Encode <= one million samples; no integer coercion/truncation is implicit.
pub fn encode_samples(
  samples : Array[Sample],
  code : Int,
  endian : Endian,
) -> Bytes raise {
  let w = sample_width(code)
  if samples.length() > 1000000 {
    raise Failure("sample array exceeds one million")
  }
  let out = Array::make(samples.length() * w, b'\x00')
  for i, s in samples {
    put_sample(out, i * w, code, s, endian)
  }
  Bytes::from_array(out)
}

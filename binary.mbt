///|
pub(all) enum Endian {
  Big
  Little
} derive(Eq)

///|
pub extend Endian with Eq::{equal, not_equal}

///|
fn need(data : Bytes, pos : Int, width : Int) -> Unit raise {
  if pos < 0 || width < 0 || pos > data.length() || width > data.length() - pos {
    raise Failure("truncated bytes at \{pos}, need \{width}")
  }
}

///|
// Every offset in this implementation is zero-based; standard tables are not.
fn uint_at(
  data : Bytes,
  pos : Int,
  width : Int,
  endian : Endian,
) -> UInt64 raise {
  need(data, pos, width)
  let mut v = 0UL
  for i in 0..<width {
    let p = if endian == Big { pos + i } else { pos + width - 1 - i }
    v = (v << 8) | data[p].to_uint64()
  }
  v
}

///|
fn int_at(data : Bytes, pos : Int, width : Int, endian : Endian) -> Int64 raise {
  let shift = (8 - width) * 8
  (uint_at(data, pos, width, endian) << shift).reinterpret_as_int64() >> shift
}

///|
fn put_uint(
  out : Array[Byte],
  pos : Int,
  width : Int,
  v : UInt64,
  endian : Endian,
) -> Unit {
  for i in 0..<width {
    out[if endian == Little { pos + i } else { pos + width - 1 - i }] = (v >>
    (i * 8)).to_byte()
  }
}

///|
fn real_at(
  data : Bytes,
  pos : Int,
  width : Int,
  endian : Endian,
) -> Double raise {
  let bits = uint_at(data, pos, width, endian)
  if width == 4 {
    Float::reinterpret_from_uint(bits.to_uint()).to_double()
  } else {
    bits.reinterpret_as_double()
  }
}

///|
fn finite(x : Double) -> Bool {
  !x.is_nan() && !x.is_inf()
}

///|
fn slice(data : Bytes, start : Int, count : Int) -> Bytes {
  Bytes::makei(count, i => data[start + i])
}

///|
fn copy_into(out : Array[Byte], at : Int, data : Bytes) -> Unit {
  for i in 0..<data.length() {
    out[at + i] = data[i]
  }
}

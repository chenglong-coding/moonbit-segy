///|
test "published IBM words and exact signed sample boundaries" {
  for
    (bits, expected) in [
      (b"\x41\x10\x00\x00", 1.0),
      (b"\xc1\x20\x00\x00", -2.0),
      (b"\x40\x80\x00\x00", 0.5),
      (b"\x00\x00\x00\x00", 0.0),
    ] {
    assert_eq(@segy.decode_sample(bits, 0, 1, @segy.Big).as_double(), expected)
    assert_eq(@segy.encode_samples([@segy.Real(expected)], 1, @segy.Big), bits)
  }
  for
    (code, low, high) in [
      (8, -128L, 127L),
      (3, -32768L, 32767L),
      (7, -8388608L, 8388607L),
      (2, -2147483648L, 2147483647L),
      (9, -9223372036854775808L, 9223372036854775807L),
    ] {
    for order in [@segy.Big, @segy.Little] {
      let bytes = @segy.encode_samples(
        [@segy.Signed(low), @segy.Signed(high)],
        code,
        order,
      )
      let width = @segy.sample_width(code)
      for (offset, expected) in [(0, low), (width, high)] {
        guard @segy.decode_sample(bytes, offset, code, order)
          is @segy.Signed(value) else {
          fail("integer coerced to real")
        }
        assert_eq(value, expected)
      }
    }
  }
  try @segy.Signed(9007199254740993L).as_double() catch {
    _ => ()
  } noraise {
    _ => fail("lossy integer analysis accepted")
  }
}

///|
test "IEEE byte order and unrepresentable writes" {
  assert_eq(
    @segy.encode_samples([@segy.Real(1.5)], 5, @segy.Big),
    b"\x3f\xc0\x00\x00",
  )
  assert_eq(
    @segy.encode_samples([@segy.Real(-2.0)], 6, @segy.Little),
    b"\x00\x00\x00\x00\x00\x00\x00\xc0",
  )
  for
    (code, value) in [(1, 1.0e100), (1, 1.0e-100), (5, 1.0e100), (5, 1.0e-100)] {
    try @segy.encode_samples([@segy.Real(value)], code, @segy.Big) catch {
      _ => ()
    } noraise {
      _ => fail("range loss accepted")
    }
  }
  try @segy.decode_sample(b"\x00", 0, 5, @segy.Big) catch {
    _ => ()
  } noraise {
    _ => fail("truncation accepted")
  }
  try @segy.encode_samples([@segy.Signed(128L)], 8, @segy.Big) catch {
    _ => ()
  } noraise {
    _ => fail("integer overflow accepted")
  }
}

///|
test "ASCII and EBCDIC explicit text with known CP037 letters" {
  let data = @segy.encode_text("C01 TEST 123", "EBCDIC")
  assert_eq(data[0], b'\xc3')
  assert_eq(data[1], b'\xf0')
  assert_eq(data[3], b'\x40')
  assert_true(@segy.decode_text(data, "EBCDIC").has_prefix("C01 TEST 123"))
  try @segy.decode_text(data, "ASCII") catch {
    _ => ()
  } noraise {
    _ => fail("wrong encoding accepted")
  }
  try @segy.encode_text("地震", "EBCDIC") catch {
    _ => ()
  } noraise {
    _ => fail("unencodable text accepted")
  }
}

///|
test "headers infer endian and preserve raw prefix while rejecting extensions" {
  for rev in [0, 1, 2] {
    for endian in [@segy.Big, @segy.Little] {
      let header = @segy.make_header(
        128,
        2000.0,
        5,
        endian~,
        revision=rev,
        fixed_length=rev != 0,
        text_encoding="EBCDIC",
      )
      let parsed = @segy.parse_header(header.raw)
      assert_true(parsed.endian == endian)
      assert_eq(parsed.revision, rev)
      assert_eq(parsed.samples, 128)
      assert_eq(parsed.interval_us, 2000.0)
      assert_eq(parsed.text_encoding, "EBCDIC")
    }
  }
  let wide = @segy.make_header(70000, 0.25, 6, revision=2)
  assert_eq(wide.samples, 70000)
  assert_eq(wide.interval_us, 0.25)
  let additional = Bytes::makei(3600, i => {
    if i == 3509 {
      b'\x01'
    } else {
      wide.raw[i]
    }
  })
  try @segy.parse_header(additional) catch {
    _ => ()
  } noraise {
    _ => fail("unknown additional header accepted")
  }
  try @segy.parse_header(wide.raw, endian=@segy.Little) catch {
    _ => ()
  } noraise {
    _ => fail("sentinel conflict accepted")
  }
}

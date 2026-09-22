///|
test "fixed and variable trace indexing preserves payload and raw header fields" {
  let h = @segy.make_header(3, 1000.0, 5, fixed_length=false)
  let a = @segy.make_trace(
    h,
    [@segy.Real(1.0), @segy.Real(-2.0), @segy.Real(3.0)],
    fields={ "ensemble": 7 },
  )
  let b = @segy.make_trace(
    h,
    [@segy.Real(4.0), @segy.Real(5.0)],
    interval_us=2000.0,
    fields={ "ensemble": 8 },
  )
  let d = @segy.create(h, [a, b])
  let offsets = d.trace_index()
  assert_eq(offsets[0].header_offset, 3600)
  assert_eq(offsets[1].header_offset, 3852)
  assert_eq(offsets[1].samples, 2)
  assert_true(!d.header.fixed_length)
  assert_eq(d.trace(1).interval_us(), 2000.0)
  assert_eq(d.trace(1).field("ensemble"), 8)
  assert_eq(d.trace(0).sample(1).as_double(), -2.0)
  let bytes = d.encode()
  let marked = Bytes::makei(bytes.length(), i => {
    if i == 3600 + 130 {
      b'\xa7'
    } else {
      bytes[i]
    }
  })
  assert_eq(@segy.decode(marked).encode(), marked)
}

///|
test "counted and EndText terminated extensions and mapping rejection" {
  let h = @segy.make_header(1, 2000.0, 3)
  let t = @segy.make_trace(h, [@segy.Signed(17L)])
  let ext = @segy.encode_text("((SEG: EndText))", "ASCII")
  let d = @segy.create(h, [t], extended_headers=[ext])
  assert_eq(d.trace_index()[0].header_offset, 6800)
  let b = d.encode()
  let unknown = Bytes::makei(b.length(), i => {
    if i == 3504 || i == 3505 {
      b'\xff'
    } else {
      b[i]
    }
  })
  assert_eq(@segy.decode(unknown).trace(0).sample(0).as_double(), 17.0)
  let mapping = @segy.encode_text("((SEG: Trace Header Mapping))", "ASCII")
  try @segy.create(h, [t], extended_headers=[mapping]) catch {
    _ => ()
  } noraise {
    _ => fail("uninterpreted mapping accepted")
  }
}

///|
test "rev2 fixed wide count interval and declared trace consistency" {
  let h = @segy.make_header(70000, 0.5, 8, revision=2, endian=@segy.Little)
  let values = Array::make(70000, @segy.Signed(12L))
  let d = @segy.create(h, [@segy.make_trace(h, values)])
  assert_eq(d.trace(0).samples(), 70000)
  assert_eq(d.trace(0).sample(69999).as_double(), 12.0)
  assert_eq(d.trace(0).interval_us(), 0.5)
  let b = d.encode()
  let wrong = Bytes::makei(b.length(), i => {
    if i == 3512 {
      b'\x02'
    } else {
      b[i]
    }
  })
  try @segy.decode(wrong) catch {
    _ => ()
  } noraise {
    _ => fail("incorrect declared count accepted")
  }
}

///|
test "truncated file and contradictory fixed header fail without overread" {
  let h = @segy.make_header(2, 1000.0, 6)
  let d = @segy.create(h, [
    @segy.make_trace(h, [@segy.Real(1.0), @segy.Real(2.0)]),
  ])
  let b = d.encode()
  for count in [0, 3199, 3599, 3839, b.length() - 1] {
    let short = Bytes::makei(count, i => b[i])
    try @segy.decode(short) catch {
      _ => ()
    } noraise {
      _ => fail("truncated file accepted")
    }
  }
  let conflict = Bytes::makei(b.length(), i => {
    if i == 3600 + 115 {
      b'\x03'
    } else {
      b[i]
    }
  })
  try @segy.decode(conflict) catch {
    _ => ()
  } noraise {
    _ => fail("conflicting count accepted")
  }
}

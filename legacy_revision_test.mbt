///|
test "legacy big endian revision requires explicit assumption and preserves raw bytes" {
  let header = @segy.make_header(3, 40.0, 2)
  let source = @segy.create(header, [
    @segy.make_trace(header, [@segy.Signed(0), @segy.Signed(0), @segy.Signed(0)]),
  ]).encode()
  let legacy = Bytes::makei(source.length(), i => {
    if i == 3500 {
      b'\x00'
    } else if i == 3501 {
      b'\x01'
    } else {
      source[i]
    }
  })
  try @segy.decode(legacy) catch {
    _ => ()
  } noraise {
    _ => fail("legacy revision guessed without authorization")
  }
  let data = @segy.decode(legacy, legacy_revision_one=true)
  assert_eq(data.header.revision, 1)
  assert_eq(data.header.raw_revision_word, 1)
  assert_true(data.header.assumed_legacy_revision_one)
  assert_eq(data.encode(), legacy)
  let report = data.quality_check()
  assert_eq(report.format_assumptions.length(), 1)
  assert_eq(report.summary.dead_traces, 1)
  let selected = data.select([0])
  assert_true(selected.header.assumed_legacy_revision_one)
  assert_eq(selected.header.raw[3500], b'\x00')
  assert_eq(selected.header.raw[3501], b'\x01')
  assert_true(data.window(0, 1).header.assumed_legacy_revision_one)
  assert_true(data.convert_samples(5).header.assumed_legacy_revision_one)
  let normal = @segy.decode(source, legacy_revision_one=true)
  assert_false(normal.header.assumed_legacy_revision_one)
  assert_eq(normal.quality_check().format_assumptions.length(), 0)
  for replacement in [b'\x02', b'\x03'] {
    let bad = Bytes::makei(legacy.length(), i => {
      if i == 3501 {
        replacement
      } else {
        legacy[i]
      }
    })
    try @segy.decode(bad, legacy_revision_one=true) catch {
      _ => ()
    } noraise {
      _ => fail("compatibility broadened to an unsupported version")
    }
  }
}

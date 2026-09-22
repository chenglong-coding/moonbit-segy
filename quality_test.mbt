///|
test "QC pools samples not trace means and preserves selected source identities" {
  let h = @segy.make_header(3, 1000.0, 6)
  let dataset = @segy.create(h, [
    @segy.make_trace(h, [Real(1.0), Real(2.0), Real(3.0)], fields={
      "ensemble": 7,
      "sequence_line": 100,
    }),
    @segy.make_trace(h, [Real(10.0)], interval_us=2000.0, fields={
      "ensemble": 7,
      "sequence_line": 101,
      "identification": 2,
    }),
    @segy.make_trace(h, [Real(0.0), Real(0.0)], fields={ "ensemble": 9 }),
  ])
  let report = dataset.quality_check(
    traces=[1, 0],
    group_by="ensemble",
    clip_threshold=3.0,
  )
  assert_eq(report.status, "issues")
  assert_eq(report.source_trace_count, 3)
  assert_eq(report.summary.samples, 4)
  assert_eq(report.summary.analyzed_samples, 4)
  guard report.summary.statistics is Some(stats) else {
    fail("missing pooled statistics")
  }
  assert_true((stats.mean - 4.0).abs() < 1.0e-12)
  assert_true((stats.rms - 28.5.sqrt()).abs() < 1.0e-12)
  assert_true((stats.standard_deviation - 12.5.sqrt()).abs() < 1.0e-12)
  assert_eq(report.summary.clipped_samples, 2)
  assert_eq(report.summary.header_dead_traces, 1)
  assert_eq(report.summary.dead_traces, 0)
  assert_eq(report.summary.minimum_interval_us, 1000.0)
  assert_eq(report.summary.maximum_interval_us, 2000.0)
  assert_eq(report.groups[0].first_trace, 1)
  assert_eq(report.details[0].trace, 1)
  assert_eq(report.details[0].sequence_line, 101)
  assert_eq(
    report.details[0].header_offset,
    dataset.trace_index()[1].header_offset,
  )
  assert_eq(report.details[1].trace, 0)
  let order = dataset.quality_check(traces=[2, 0, 1], group_by="ensemble")
  assert_eq(order.groups[0].value, 9)
  assert_eq(order.groups[1].value, 7)
}

///|
test "nonfinite IEEE samples are located without excluding later good traces" {
  let h = @segy.make_header(3, 1000.0, 6)
  let good = @segy.make_trace(h, [Real(1.0), Real(2.0), Real(3.0)])
  let source = @segy.create(h, [good, good])
  let raw = source.encode()
  let bytes = Array::makei(raw.length(), i => raw[i])
  let offset = source.trace_index()[0].sample_offset
  for (point, bits) in [(0, 0x7ff0000000000000UL), (2, 0x7ff8000000000000UL)] {
    for i in 0..<8 {
      bytes[offset + point * 8 + i] = (bits >> ((7 - i) * 8)).to_byte()
    }
  }
  let dataset = @segy.decode(Bytes::from_array(bytes))
  let report = dataset.quality_check()
  assert_eq(report.summary.nonfinite_samples, 2)
  assert_eq(report.summary.analyzed_traces, 1)
  assert_eq(report.summary.analyzed_samples, 3)
  assert_eq(report.details[0].first_nonfinite_sample, Some(0))
  assert_true(report.details[0].statistics is None)
  guard report.summary.statistics is Some(stats) else {
    fail("lost later valid trace")
  }
  assert_eq(stats.mean, 2.0)
  // Stats on a partly bad trace remain null, not statistics of the valid subset.
  assert_true(report.to_json().stringify().contains("\"statistics\":null"))
  let none = dataset.quality_check(traces=[0])
  assert_true(none.summary.statistics is None)
  assert_true(none.issues_csv().contains("false,,,,\n"))
}

///|
test "valid int64 data can be un-analyzable without becoming nonfinite or rounded" {
  let h = @segy.make_header(3, 1000.0, 9)
  let dataset = @segy.create(h, [
    @segy.make_trace(h, [
      Signed(9223372036854775807L),
      Signed(1L),
      Signed(-9223372036854775808L),
    ]),
  ])
  let report = dataset.quality_check()
  assert_eq(dataset.nonfinite_samples(), 0)
  assert_eq(report.summary.integer_range_samples, 2)
  assert_eq(report.summary.analyzed_samples, 0)
  assert_eq(report.details[0].first_integer_range_sample, Some(0))
  assert_true(report.summary.statistics is None)
  assert_true(dataset.csv([0]).contains("9223372036854775807"))
}

///|
test "weighting failures and threshold equality do not fabricate dead traces" {
  let h = @segy.make_header(2, 1000.0, 6)
  let dataset = @segy.create(h, [
    @segy.make_trace(h, [Real(-4.0), Real(4.0)], fields={ "weighting": 2 }),
    @segy.make_trace(h, [Real(1.0), Real(0.0)], fields={ "weighting": -1 }),
    @segy.make_trace(h, [Real(1.0), Real(0.0)], fields={ "weighting": 32767 }),
  ])
  let result = dataset.quality_check(
    weighted=true,
    dead_threshold=1.0,
    clip_threshold=1.0,
  )
  assert_eq(result.summary.analyzed_traces, 1)
  assert_eq(result.summary.dead_traces, 1)
  assert_eq(result.summary.clipped_samples, 2)
  assert_eq(result.summary.negative_weighting_traces, 1)
  assert_eq(result.summary.weighting_range_samples, 1)
  assert_eq(result.details[2].first_weighting_range_sample, Some(0))
  assert_true(
    result.details[1].statistics is None && result.details[2].statistics is None,
  )
  let raw = dataset.quality_check()
  assert_eq(raw.status, "clear")
  assert_eq(raw.summary.analyzed_traces, 3)
}

///|
test "QC retains full totals and groups after exhausting detail budget" {
  let h = @segy.make_header(1, 1000.0, 5)
  let dataset = @segy.create(h, [
    @segy.make_trace(h, [Real(0.0)], fields={ "ensemble": 3 }),
    @segy.make_trace(h, [Real(5.0)], fields={ "ensemble": 4 }),
    @segy.make_trace(h, [Real(0.0)], fields={ "ensemble": 3 }),
  ])
  let result = dataset.quality_check(
    group_by="ensemble",
    clip_threshold=4.0,
    max_details=1,
  )
  assert_eq(result.summary.problem_traces, 3)
  assert_eq(result.summary.dead_traces, 2)
  assert_eq(result.summary.clipped_traces, 1)
  assert_eq(result.groups[0].summary.traces, 2)
  assert_eq(result.details.length(), 1)
  assert_true(result.details_truncated)
  let none = dataset.quality_check(max_details=0)
  assert_eq(none.status, "issues")
  assert_eq(none.details.length(), 0)
  assert_true(none.details_truncated)
}

///|
test "QC moments remain finite near Double maximum and for tiny amplitudes" {
  let h = @segy.make_header(2, 1000.0, 6)
  for scale in [1.7976931348623157e308, 1.0e-300] {
    let dataset = @segy.create(h, [
      @segy.make_trace(h, [Real(scale), Real(-scale)]),
      @segy.make_trace(h, [Real(scale), Real(-scale)]),
    ])
    guard dataset.quality_check().summary.statistics is Some(s) else {
      fail("missing moments")
    }
    assert_eq(s.mean, 0.0)
    assert_eq(s.rms, scale)
    assert_eq(s.standard_deviation, scale)
  }
}

///|
test "QC rejects invalid selection, thresholds and grouping instead of truncating" {
  let h = @segy.make_header(1, 1000.0, 5, revision=0, fixed_length=false)
  let dataset = @segy.create(h, [
    @segy.make_trace(h, [Real(1.0)], fields={ "ensemble": 1 }),
    @segy.make_trace(h, [Real(1.0)], fields={ "ensemble": 2 }),
  ])
  let bad : Array[() -> Unit raise] = [
    () => ignore(dataset.quality_check(traces=[])),
    () => ignore(dataset.quality_check(traces=[0, 0])),
    () => ignore(dataset.quality_check(traces=[2])),
    () => ignore(dataset.quality_check(dead_threshold=-1.0)),
    () => ignore(dataset.quality_check(clip_threshold=1.0 / 0.0)),
    () => ignore(dataset.quality_check(dead_threshold=0.0 / 0.0)),
    () => ignore(dataset.quality_check(max_details=-1)),
    () => ignore(dataset.quality_check(max_details=100001)),
    () => ignore(dataset.quality_check(max_groups=0)),
    () => ignore(dataset.quality_check(max_groups=100001)),
    () => ignore(dataset.quality_check(group_by="inline")),
    () => ignore(dataset.quality_check(group_by="ensemble", max_groups=1)),
    () => ignore(dataset.quality_check(group_by="typo")),
  ]
  for f in bad {
    try f() catch {
      _ => ()
    } noraise {
      _ => fail("invalid QC request accepted")
    }
  }
}

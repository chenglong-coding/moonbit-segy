///|
test "coordinates, timing and weighting apply the correct independent scalars" {
  let h = @segy.make_header(3, 2000.0, 5)
  let t = @segy.make_trace(
    h,
    [@segy.Real(-3.0), @segy.Real(0.0), @segy.Real(4.0)],
    fields={
      "coordinate_scalar": -100,
      "source_x": -123304500,
      "coordinate_units": 4,
      "delay_ms": 20,
      "time_scalar": -10,
      "weighting": 2,
      "ensemble": 7,
    },
  )
  assert_true((t.coordinate_degrees("source_x") + 123.5125).abs() < 1.0e-10)
  assert_true((t.time_seconds(1) - 0.004).abs() < 1.0e-14)
  assert_eq(t.amplitude(0, weighted=true), -0.75)
  let d = @segy.create(h, [t, t])
  let cut = d.window(1, 2)
  assert_eq(cut.trace(0).samples(), 2)
  assert_eq(cut.trace(0).field("delay_ms"), 40)
  assert_eq(cut.trace(0).sample(0).as_double(), 0.0)
  assert_true(
    (cut.trace(0).time_seconds(1) - t.time_seconds(2)).abs() < 1.0e-14,
  )
  assert_eq(d.find_traces("ensemble", 7, 7).length(), 2)
  assert_eq(d.groups("ensemble")[0].indices.length(), 2)
  assert_eq(d.select([1]).trace(0).field("sequence_file"), 1)
}

///|
test "RMS and population deviation avoid square overflow; clipping is explicit" {
  let h = @segy.make_header(3, 1000.0, 6)
  let t = @segy.make_trace(h, [
    @segy.Real(-3.0),
    @segy.Real(0.0),
    @segy.Real(4.0),
  ])
  let stats = t.statistics(clip_threshold=3.0)
  assert_true((stats.mean - 1.0 / 3.0).abs() < 1.0e-14)
  assert_true((stats.rms - 5.0 / 3.0.sqrt()).abs() < 1.0e-14)
  assert_true((stats.standard_deviation - 74.0.sqrt() / 3.0).abs() < 1.0e-14)
  assert_eq(stats.clipped_samples, 2)
  assert_true(!stats.dead)
  let large = @segy.make_trace(h, [
    @segy.Real(1.0e300),
    @segy.Real(-1.0e300),
    @segy.Real(0.0),
  ])
  assert_true(
    (large.statistics().rms / 1.0e300 - (2.0 / 3.0).sqrt()).abs() < 1.0e-14,
  )
  let zero = @segy.make_trace(h, Array::make(3, @segy.Real(0.0)))
  assert_true(zero.statistics().dead)
}

///|
test "sample conversion and CSV retain int64 precision while rejecting lossy analysis" {
  let h = @segy.make_header(1, 1000.0, 9)
  let d = @segy.create(h, [
    @segy.make_trace(h, [@segy.Signed(9223372036854775807L)]),
  ])
  assert_true(d.csv([0]).contains("9223372036854775807"))
  assert_eq(d.convert_samples(9).encode(), d.encode())
  try d.convert_samples(6) catch {
    _ => ()
  } noraise {
    _ => fail("lossy int64 conversion")
  }
  let f = @segy.make_header(2, 1000.0, 5)
  let integral = @segy.create(f, [
    @segy.make_trace(f, [@segy.Real(-12.0), @segy.Real(34.0)]),
  ])
  let converted = integral.convert_samples(3)
  assert_eq(converted.trace(0).sample(1).as_double(), 34.0)
  let fractional = @segy.create(f, [
    @segy.make_trace(f, [@segy.Real(0.25), @segy.Real(1.0)]),
  ])
  try fractional.convert_samples(3) catch {
    _ => ()
  } noraise {
    _ => fail("fraction truncated")
  }
  assert_true(integral.trace(0).svg().contains("<polyline"))
}

///|
test "window time and selection cannot silently round or duplicate" {
  let h = @segy.make_header(2, 500.0, 5)
  let d = @segy.create(h, [
    @segy.make_trace(h, [@segy.Real(1.0), @segy.Real(2.0)]),
  ])
  try d.window(1, 1) catch {
    _ => ()
  } noraise {
    _ => fail("half-ms window delay rounded")
  }
  try d.select([0, 0]) catch {
    _ => ()
  } noraise {
    _ => fail("duplicate trace accepted")
  }
  try d.window(0, 3) catch {
    _ => ()
  } noraise {
    _ => fail("oversized window accepted")
  }
}

///|
test "SVG keeps a single positive negative or zero sample visible" {
  let h = @segy.make_header(1, 2000.0, 6)
  for amplitude in [4.0, -4.0, 0.0] {
    let svg = @segy.make_trace(h, [@segy.Real(amplitude)]).svg()
    // A one-vertex polyline has no painted segment. A real sample marker is
    // required even for zero; extending a line would invent a time interval.
    assert_true(svg.contains("<circle"))
    assert_true(!svg.contains("NaN") && !svg.contains("Infinity"))
  }
}

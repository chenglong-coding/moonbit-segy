///|
// Inspect all traces without rewriting, resampling or renumbering. The dead
// flag in the header and the observed amplitude criterion remain independent.
fn main raise {
  let header = @segy.make_header(3, 2000.0, 6)
  let dataset = @segy.create(header, [
    @segy.make_trace(header, [Real(-1.0), Real(0.0), Real(1.0)], fields={
      "ensemble": 10,
    }),
    @segy.make_trace(header, [Real(0.0), Real(0.0), Real(0.0)], fields={
      "ensemble": 10,
      "identification": 2,
    }),
    @segy.make_trace(header, [Real(5.0), Real(-5.0)], interval_us=1000.0, fields={
      "ensemble": 20,
    }),
  ])
  let report = dataset.quality_check(
    group_by="ensemble",
    clip_threshold=4.0,
    max_details=10,
  )
  println(report.to_json().stringify())
  println(report.issues_csv())
}

///|
// SEG scalars: positive multiplies, negative divides, zero means one.
fn scalar(value : Int) -> Double {
  if value == 0 {
    1.0
  } else if value > 0 {
    value.to_double()
  } else {
    -1.0 / value.to_double()
  }
}

///|
/// Apply only the designated SEG header scalar. No CRS conversion or unit
/// guessing: length coordinates stay in declared meters/feet, angular fields
/// in their recorded units. Use coordinate_degrees for explicit angular units.
pub fn Trace::scaled_field(self : Trace, name : String) -> Double raise {
  let scale_name = match name {
    "source_x" | "source_y" | "group_x" | "group_y" | "cdp_x" | "cdp_y" =>
      "coordinate_scalar"
    "receiver_elevation" | "source_elevation" | "source_depth" =>
      "elevation_scalar"
    "shotpoint" => "shotpoint_scalar"
    "delay_ms" => "time_scalar"
    _ => raise Failure("field has no supported scalar")
  }
  let scale = if self.revision == 0 && scale_name == "time_scalar" {
    1.0
  } else {
    scalar(self.field(scale_name))
  }
  self.field(name).to_double() * scale
}

///|
/// Angular units 2 (arc-seconds), 3 (degrees), 4 (signed DDDMMSS.ss).
/// Unknown/linear coordinates raise; do not assume a geographic CRS.
pub fn Trace::coordinate_degrees(self : Trace, name : String) -> Double raise {
  if !(name == "source_x" ||
    name == "source_y" ||
    name == "group_x" ||
    name == "group_y" ||
    name == "cdp_x" ||
    name == "cdp_y") {
    raise Failure("coordinate field required")
  }
  let v = self.scaled_field(name)
  match self.field("coordinate_units") {
    2 => v / 3600.0
    3 => v
    4 => {
      let a = v.abs()
      let degrees = (a / 10000.0).trunc()
      let rest = a - degrees * 10000.0
      let minutes = (rest / 100.0).trunc()
      let seconds = rest - minutes * 100.0
      if minutes >= 60.0 || seconds >= 60.0 {
        raise Failure("invalid packed DMS coordinate")
      }
      (if v < 0.0 { -1.0 } else { 1.0 }) *
      (degrees + minutes / 60.0 + seconds / 3600.0)
    }
    _ => raise Failure("coordinate units are not explicitly angular")
  }
}

///|
/// Time relative to trace source time; scaled delay (ms) plus index*dt (us).
pub fn Trace::time_seconds(self : Trace, index : Int) -> Double raise {
  if index < 0 || index >= self.count {
    raise Failure("sample index outside trace")
  }
  let value = self.scaled_field("delay_ms") / 1000.0 +
    index.to_double() * self.dt / 1000000.0
  if !finite(value) {
    raise Failure("sample time overflow")
  }
  value
}

///|
/// Optional 2^(-weighting) header gain only; does not apply transduction/units.
pub fn Trace::amplitude(
  self : Trace,
  index : Int,
  weighted? : Bool = false,
) -> Double raise {
  let raw = self.sample(index).as_double()
  if !weighted {
    return raw
  }
  let weight = self.field("weighting")
  if weight < 0 {
    raise Failure("negative trace weighting is unsupported")
  }
  let result = raw * @math.pow(2.0, -weight.to_double())
  if !finite(result) || (raw != 0.0 && result == 0.0) {
    raise Failure("trace weighting loses numerical range")
  }
  result
}

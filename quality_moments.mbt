///|
/// Sample-weighted amplitude moments over fully analyzable traces only.
/// No duration weighting, resampling or physical-unit calibration is implied.
pub struct AmplitudeStatistics {
  samples : Int
  minimum : Double
  maximum : Double
  mean : Double
  rms : Double
  standard_deviation : Double
} derive(ToJson)

///|
pub extend AmplitudeStatistics with ToJson::{to_json}

///|
// Welford moments in peak-normalized coordinates. Values/squares never need
// raw x*x or x-y, which may overflow even when the final moments are finite.
priv struct QualityMoments {
  mut count : Int
  mut minimum : Double
  mut maximum : Double
  mut scale : Double
  mut mean : Double
  mut m2 : Double
  mut squares : Double
}

///|
fn QualityMoments::new() -> QualityMoments {
  {
    count: 0,
    minimum: 0.0,
    maximum: 0.0,
    scale: 0.0,
    mean: 0.0,
    m2: 0.0,
    squares: 0.0,
  }
}

///|
fn QualityMoments::add(self : QualityMoments, value : Double) -> Unit {
  if self.count == 0 {
    self.minimum = value
    self.maximum = value
  } else {
    self.minimum = self.minimum.min(value)
    self.maximum = self.maximum.max(value)
  }
  if value.abs() > self.scale {
    let ratio = self.scale / value.abs()
    self.mean *= ratio
    self.m2 *= ratio * ratio
    self.squares *= ratio * ratio
    self.scale = value.abs()
  }
  let x = if self.scale == 0.0 { 0.0 } else { value / self.scale }
  self.count += 1
  let delta = x - self.mean
  self.mean += delta / self.count.to_double()
  self.m2 += delta * (x - self.mean)
  self.squares += x * x
}

///|
// Parallel population-moment merge. Weight by sample count, not trace count;
// different intervals do NOT change weights. Empty accumulators are neutral.
fn QualityMoments::merge(self : QualityMoments, other : QualityMoments) -> Unit {
  if other.count == 0 {
    return
  }
  if self.count == 0 {
    self.minimum = other.minimum
    self.maximum = other.maximum
  } else {
    self.minimum = self.minimum.min(other.minimum)
    self.maximum = self.maximum.max(other.maximum)
  }
  let scale = self.scale.max(other.scale)
  let a = if scale == 0.0 { 0.0 } else { self.scale / scale }
  let b = if scale == 0.0 { 0.0 } else { other.scale / scale }
  let n = self.count + other.count
  let fraction = other.count.to_double() / n.to_double()
  let mean_a = self.mean * a
  let delta = other.mean * b - mean_a
  self.m2 = self.m2 * a * a +
    other.m2 * b * b +
    delta * delta * self.count.to_double() * fraction
  self.squares = self.squares * a * a + other.squares * b * b
  self.mean = mean_a + delta * fraction
  self.scale = scale
  self.count = n
}

///|
fn QualityMoments::finish(self : QualityMoments) -> AmplitudeStatistics? {
  if self.count == 0 {
    return None
  }
  // Exact normalized mean lies in [-1,1], population variance and mean square
  // in [0,1]. Clamp rounding drift to these proven bounds before restoring
  // a scale near Double.max; do not invent a finite result after raw overflow.
  Some({
    samples: self.count,
    minimum: self.minimum,
    maximum: self.maximum,
    mean: self.mean.max(-1.0).min(1.0) * self.scale,
    rms: (self.squares / self.count.to_double()).max(0.0).min(1.0).sqrt() *
    self.scale,
    standard_deviation: (self.m2 / self.count.to_double())
    .max(0.0)
    .min(1.0)
    .sqrt() *
    self.scale,
  })
}

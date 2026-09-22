///|
// IBM code page 037 byte-to-Unicode mapping; all codepoints fit Latin-1.
// Data table checked against Python's independent cp037 codec, not host FFI.
let cp037 : Array[Int] = [
  0, 1, 2, 3, 156, 9, 134, 127, 151, 141, 142, 11, 12, 13, 14, 15, 16, 17, 18, 19,
  157, 133, 8, 135, 24, 25, 146, 143, 28, 29, 30, 31, 128, 129, 130, 131, 132, 10,
  23, 27, 136, 137, 138, 139, 140, 5, 6, 7, 144, 145, 22, 147, 148, 149, 150, 4,
  152, 153, 154, 155, 20, 21, 158, 26, 32, 160, 226, 228, 224, 225, 227, 229, 231,
  241, 162, 46, 60, 40, 43, 124, 38, 233, 234, 235, 232, 237, 238, 239, 236, 223,
  33, 36, 42, 41, 59, 172, 45, 47, 194, 196, 192, 193, 195, 197, 199, 209, 166, 44,
  37, 95, 62, 63, 248, 201, 202, 203, 200, 205, 206, 207, 204, 96, 58, 35, 64, 39,
  61, 34, 216, 97, 98, 99, 100, 101, 102, 103, 104, 105, 171, 187, 240, 253, 254,
  177, 176, 106, 107, 108, 109, 110, 111, 112, 113, 114, 170, 186, 230, 184, 198,
  164, 181, 126, 115, 116, 117, 118, 119, 120, 121, 122, 161, 191, 208, 221, 222,
  174, 94, 163, 165, 183, 169, 167, 182, 188, 189, 190, 91, 93, 175, 168, 180, 215,
  123, 65, 66, 67, 68, 69, 70, 71, 72, 73, 173, 244, 246, 242, 243, 245, 125, 74,
  75, 76, 77, 78, 79, 80, 81, 82, 185, 251, 252, 249, 250, 255, 92, 247, 83, 84,
  85, 86, 87, 88, 89, 90, 178, 212, 214, 210, 211, 213, 48, 49, 50, 51, 52, 53, 54,
  55, 56, 57, 179, 219, 220, 217, 218, 159,
]

///|
fn encoding_name(encoding : String) -> String raise {
  let e = encoding.to_upper()
  if e != "ASCII" && e != "EBCDIC" {
    raise Failure("text encoding must be ASCII or EBCDIC (CP037)")
  }
  e
}

///|
/// Decode exactly one 3200-byte block. No trimming or guessed line endings.
pub fn decode_text(data : Bytes, encoding : String) -> String raise {
  if data.length() != 3200 {
    raise Failure("text block must be 3200 bytes")
  }
  let e = encoding_name(encoding)
  let out = StringBuilder()
  for i in 0..<3200 {
    let b = data[i].to_int()
    if e == "ASCII" && b > 127 {
      raise Failure("non-ASCII byte in text block")
    }
    let point = if e == "ASCII" { b } else { cp037[b] }
    out.write_char(point.to_byte().to_char())
  }
  out.to_string()
}

///|
/// Pad a flat <=3200-character header with spaces. Supply your own 80-column
/// layout for the main header; embedded line breaks are not expanded to rows.
pub fn encode_text(text : String, encoding : String) -> Bytes raise {
  let e = encoding_name(encoding)
  if text.length() > 3200 {
    raise Failure("text block exceeds 3200 characters")
  }
  let out = Array::make(3200, if e == "ASCII" { b' ' } else { b'\x40' })
  let reverse = Array::make(256, 0)
  for i, p in cp037 {
    reverse[p] = i
  }
  for i in 0..<text.length() {
    let p = text[i].to_int()
    if p < 0 || p > 255 || (e == "ASCII" && p > 127) {
      raise Failure("character outside selected encoding")
    }
    out[i] = (if e == "ASCII" { p } else { reverse[p] }).to_byte()
  }
  Bytes::from_array(out)
}

///|
// A heuristic only: ambiguous printable blocks require an explicit override.
fn detect_text(data : Bytes) -> String raise {
  let mut ascii = 0
  let mut ebcdic = 0
  for i in 0..<3200 {
    let b = data[i].to_int()
    let c = cp037[b]
    if b >= 32 && b <= 126 {
      ascii += 1
    }
    if c >= 32 && c <= 126 {
      ebcdic += 1
    }
  }
  if ascii == ebcdic || ascii.max(ebcdic) < 2880 {
    raise Failure("ambiguous text encoding; specify ASCII or EBCDIC")
  }
  if ascii > ebcdic {
    "ASCII"
  } else {
    "EBCDIC"
  }
}

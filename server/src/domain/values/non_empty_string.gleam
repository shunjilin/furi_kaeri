import gleam/string

pub opaque type NonEmptyString {
  NonEmptyString(value: String)
}

pub type ValueError {
  EmptyString
}

pub fn new(input: String) -> Result(NonEmptyString, ValueError) {
  case string.trim(input) {
    "" -> Error(EmptyString)
    trimmed -> Ok(NonEmptyString(trimmed))
  }
}

pub fn to_string(nes: NonEmptyString) -> String {
  nes.value
}

pub fn append(to to: NonEmptyString, suffix suffix: String) -> NonEmptyString {
  NonEmptyString(string.append(to: to.value, suffix:))
}

pub type Phase {
  Draft
  Preview
  Voting
}

pub fn authorize_phase(
  current current: Phase,
  allowed allowed: Phase,
  error error,
  fun fun: fn() -> Result(output, error),
) -> Result(output, error) {
  case current {
    phase if phase == allowed -> {
      fun()
    }
    _ -> {
      Error(error)
    }
  }
}

pub fn to_string(phase: Phase) -> String {
  case phase {
    Draft -> "Draft"
    Preview -> "Preview"
    Voting -> "Voting"
  }
}

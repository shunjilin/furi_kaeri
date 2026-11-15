import gleam/list

pub type NonEmptyList(a) {
  NonEmptyList(first: a, rest: List(a))
}

pub fn as_list(non_empty_list: NonEmptyList(a)) -> List(a) {
  list.append([non_empty_list.first], non_empty_list.rest)
}

pub type ValueError {
  EmptyList
}

pub fn from_list(list: List(a)) -> Result(NonEmptyList(a), ValueError) {
  case list {
    [first, ..rest] -> Ok(NonEmptyList(first: first, rest: rest))
    [] -> Error(EmptyList)
  }
}

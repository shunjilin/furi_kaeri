import domain/board
import domain/card
import domain/lane
import domain/user
import domain/values/non_empty_string as nes
import domain/vote

pub fn non_empty_string(content: String) -> nes.NonEmptyString {
  let assert Ok(nes) = nes.new(content)
  nes
}

pub fn user() -> user.User {
  user.new(user.gen_id())
}

pub fn card() -> card.Card {
  let author = user()

  card.new(user.id(author), non_empty_string("Content"))
}

pub fn lane() -> lane.Lane {
  lane.new(non_empty_string("Lane"))
}

pub fn vote() -> vote.Vote {
  vote.Vote(user.gen_id())
}

pub fn board() -> board.Board {
  board.new(non_empty_string("Board"), [lane()])
}

import domain/phase
import domain/user
import domain/values/non_empty_string as nes
import domain/vote
import gleam/set
import youid/uuid

pub type CardId {
  CardId(uuid.Uuid)
}

pub opaque type Card(phase) {
  Card(
    id: CardId,
    author_id: user.UserId,
    content: nes.NonEmptyString,
    votes: set.Set(vote.Vote),
  )
}

pub fn id(card: Card(phase)) -> CardId {
  card.id
}

pub fn author_id(card: Card(phase)) -> user.UserId {
  card.author_id
}

pub fn content(card: Card(phase)) -> nes.NonEmptyString {
  card.content
}

pub fn vote_count(card: Card(phase.Reviewing)) -> Int {
  set.size(card.votes)
}

pub fn new(
  author_id: user.UserId,
  content: nes.NonEmptyString,
) -> Card(phase.Drafting) {
  Card(
    id: CardId(uuid.v7()),
    author_id: author_id,
    content: content,
    votes: set.new(),
  )
}

pub type UpdateCardError {
  NotAuthor
}

pub fn edit(
  card: Card(phase.Drafting),
  author_id: user.UserId,
  new_content: nes.NonEmptyString,
) -> Result(Card(phase.Drafting), UpdateCardError) {
  let is_author = card.author_id == author_id

  case is_author {
    False -> Error(NotAuthor)
    True -> Ok(Card(..card, content: new_content))
  }
}

pub fn reveal(card: Card(phase.Drafting)) -> Card(phase.Reviewing) {
  let card: Card(phase.Reviewing) =
    Card(
      id: card.id,
      author_id: card.author_id,
      content: card.content,
      votes: card.votes,
    )
  card
}

pub type VoteError {
  AlreadyVoted
}

pub type RemoveVoteError {
  VoteNotFound
}

pub fn vote(
  card: Card(phase.Reviewing),
  vote: vote.Vote,
) -> Result(Card(phase.Reviewing), VoteError) {
  case set.contains(card.votes, vote) {
    True -> Error(AlreadyVoted)
    False -> Ok(Card(..card, votes: set.insert(card.votes, vote)))
  }
}

pub fn remove_vote(
  card: Card(phase.Reviewing),
  vote: vote.Vote,
) -> Result(Card(phase.Reviewing), RemoveVoteError) {
  case set.contains(card.votes, vote) {
    True -> Ok(Card(..card, votes: set.delete(card.votes, vote)))
    False -> Error(VoteNotFound)
  }
}

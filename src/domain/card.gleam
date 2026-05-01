import domain/phase
import domain/user
import domain/values/non_empty_string as nes
import domain/vote
import gleam/set
import youid/uuid

pub type CardId {
  CardId(uuid.Uuid)
}

pub opaque type Card {
  Card(
    id: CardId,
    author_id: user.UserId,
    content: nes.NonEmptyString,
    votes: set.Set(vote.Vote),
  )
}

pub fn new_id() -> CardId {
  CardId(uuid.v7())
}

pub fn id(card: Card) -> CardId {
  card.id
}

pub fn author_id(card: Card) -> user.UserId {
  card.author_id
}

pub fn content(card: Card) -> nes.NonEmptyString {
  card.content
}

pub fn vote_count(card: Card) -> Int {
  set.size(card.votes)
}

pub fn new(author_id: user.UserId, content: nes.NonEmptyString) -> Card {
  Card(id: new_id(), author_id: author_id, content: content, votes: set.new())
}

pub type EditError {
  EditNotAuthor
  EditNotDraft
}

pub fn edit(
  card: Card,
  author_id: user.UserId,
  new_content: nes.NonEmptyString,
  phase: phase.Phase,
) -> Result(Card, EditError) {
  use <- phase.authorize_phase(
    current: phase,
    allowed: phase.Draft,
    error: EditNotDraft,
  )
  let is_author = card.author_id == author_id

  case is_author {
    False -> Error(EditNotAuthor)
    True -> Ok(Card(..card, content: new_content))
  }
}

pub type VoteError {
  VoteAlreadyVoted
  VoteNotReviewPhase
}

pub type RemoveVoteError {
  RemoveVoteNotFound
  RemoveVoteNotReviewPhase
}

pub fn vote(
  card: Card,
  vote: vote.Vote,
  phase: phase.Phase,
) -> Result(Card, VoteError) {
  use <- phase.authorize_phase(
    current: phase,
    allowed: phase.Voting,
    error: VoteNotReviewPhase,
  )
  case set.contains(card.votes, vote) {
    True -> Error(VoteAlreadyVoted)
    False -> Ok(Card(..card, votes: set.insert(card.votes, vote)))
  }
}

pub fn remove_vote(
  card: Card,
  vote: vote.Vote,
  phase: phase.Phase,
) -> Result(Card, RemoveVoteError) {
  use <- phase.authorize_phase(
    current: phase,
    allowed: phase.Voting,
    error: RemoveVoteNotReviewPhase,
  )
  case set.contains(card.votes, vote) {
    True -> Ok(Card(..card, votes: set.delete(card.votes, vote)))
    False -> Error(RemoveVoteNotFound)
  }
}

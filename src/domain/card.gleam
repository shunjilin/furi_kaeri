import domain/user
import domain/values/non_empty_string
import domain/vote
import gleam/bool
import gleam/set
import gleam/string
import youid/uuid

pub type Draft {
  Draft
}

pub type Review {
  Review
}

pub type Voting {
  Voting(votes: set.Set(vote.Vote))
}

pub type Tallied {
  Tallied(votes: set.Set(vote.Vote))
}

pub type CardId {
  CardId(uuid.Uuid)
}

pub opaque type Card(phase) {
  Card(
    id: CardId,
    author_id: user.UserId,
    content: non_empty_string.NonEmptyString,
    phase: phase,
  )
}

pub fn new_id() -> CardId {
  CardId(uuid.v7())
}

pub fn id(card: Card(phase)) -> CardId {
  card.id
}

pub fn author_id(card: Card(phase)) -> user.UserId {
  card.author_id
}

pub fn content(card: Card(phase)) -> non_empty_string.NonEmptyString {
  card.content
}

pub fn vote_count(card: Card(Tallied)) -> Int {
  set.size(card.phase.votes)
}

pub fn voted(card: Card(Voting), user_id: user.UserId) -> Bool {
  set.contains(card.phase.votes, vote.Vote(user_id))
}

pub fn new(
  author_id: user.UserId,
  content: non_empty_string.NonEmptyString,
) -> Card(Draft) {
  Card(id: new_id(), author_id: author_id, content: content, phase: Draft)
}

pub type EditError {
  EditNotAuthor
}

pub fn edit(
  card card: Card(Draft),
  author_id author_id: user.UserId,
  content new_content: non_empty_string.NonEmptyString,
) -> Result(Card(Draft), EditError) {
  let is_author = card.author_id == author_id

  case is_author {
    False -> Error(EditNotAuthor)
    True -> Ok(Card(..card, content: new_content, phase: Draft))
  }
}

pub type RemoveError {
  RemoveNotAuthor
}

pub fn remove(
  card card: Card(phase),
  author_id author_id: user.UserId,
) -> Result(Nil, RemoveError) {
  let is_author = card.author_id == author_id
  case is_author {
    True -> Ok(Nil)
    False -> Error(RemoveNotAuthor)
  }
}

pub type VoteError {
  VoteAlreadyVoted
}

pub type RemoveVoteError {
  RemoveVoteNotFound
}

pub fn vote(
  card card: Card(Voting),
  vote vote: vote.Vote,
) -> Result(Card(Voting), VoteError) {
  case set.contains(card.phase.votes, vote) {
    True -> Error(VoteAlreadyVoted)
    False ->
      Ok(Card(..card, phase: Voting(votes: set.insert(card.phase.votes, vote))))
  }
}

pub fn remove_vote(
  card card: Card(Voting),
  vote vote: vote.Vote,
) -> Result(Card(Voting), RemoveVoteError) {
  case set.contains(card.phase.votes, vote) {
    True ->
      Ok(Card(..card, phase: Voting(votes: set.delete(card.phase.votes, vote))))
    False -> Error(RemoveVoteNotFound)
  }
}

pub type MergeError {
  MergeCannotMergeToSelf
}

/// Naive merge that just merges the child's content to the parent's content.
/// Caller must follow up by removing the child card from the board.
pub fn merge(
  from source: Card(Review),
  into target: Card(Review),
) -> Result(Card(Review), MergeError) {
  use <- bool.guard(
    when: source.id == target.id,
    return: Error(MergeCannotMergeToSelf),
  )

  let delimiter = "\n" <> string.repeat("-", 4) <> "\n"

  let merged_content =
    non_empty_string.append(
      target.content,
      string.append(
        to: delimiter,
        suffix: non_empty_string.to_string(source.content),
      ),
    )

  Ok(Card(..target, content: merged_content))
}

pub fn reveal_content(card: Card(Draft)) -> Card(Review) {
  Card(..card, phase: Review)
}

pub fn reveal_votes(card: Card(Voting)) -> Card(Tallied) {
  Card(..card, phase: Tallied(votes: card.phase.votes))
}

pub fn start_voting(card: Card(Review)) -> Card(Voting) {
  Card(..card, phase: Voting(votes: set.new()))
}

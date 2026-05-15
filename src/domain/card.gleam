import domain/user
import domain/values/non_empty_string as nes
import domain/vote
import gleam/bool
import gleam/set
import gleam/string
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
    children_ids: List(CardId),
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

pub fn voted(card: Card, user_id: user.UserId) -> Bool {
  set.contains(card.votes, vote.Vote(user_id))
}

pub fn new(author_id: user.UserId, content: nes.NonEmptyString) -> Card {
  Card(
    id: new_id(),
    author_id: author_id,
    content: content,
    votes: set.new(),
    children_ids: [],
  )
}

pub type EditError {
  EditNotAuthor
}

pub fn edit(
  card card: Card,
  author_id author_id: user.UserId,
  content new_content: nes.NonEmptyString,
) -> Result(Card, EditError) {
  let is_author = card.author_id == author_id

  case is_author {
    False -> Error(EditNotAuthor)
    True -> Ok(Card(..card, content: new_content))
  }
}

pub type VoteError {
  VoteAlreadyVoted
}

pub type RemoveVoteError {
  RemoveVoteNotFound
}

pub fn vote(card card: Card, vote vote: vote.Vote) -> Result(Card, VoteError) {
  case set.contains(card.votes, vote) {
    True -> Error(VoteAlreadyVoted)
    False -> Ok(Card(..card, votes: set.insert(card.votes, vote)))
  }
}

pub fn remove_vote(card: Card, vote: vote.Vote) -> Result(Card, RemoveVoteError) {
  case set.contains(card.votes, vote) {
    True -> Ok(Card(..card, votes: set.delete(card.votes, vote)))
    False -> Error(RemoveVoteNotFound)
  }
}

pub type MergeError {
  MergeAlreadyMerged
  MergeCannotMergeToSelf
}

/// Naive merge that just merges the child's content to the parent's content.
/// Caller must follow up by removing the child card from the board.
pub fn merge(from child: Card, to parent: Card) -> Result(Card, MergeError) {
  use <- bool.guard(
    when: child.id == parent.id,
    return: Error(MergeCannotMergeToSelf),
  )

  let delimiter = "\n" <> string.repeat("-", 4) <> "\n"

  let merged_content =
    nes.append(
      parent.content,
      string.append(to: delimiter, suffix: nes.to_string(child.content)),
    )

  Ok(Card(..parent, content: merged_content))
}

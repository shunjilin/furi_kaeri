import domain/card
import domain/user
import domain/values/non_empty_string as nes
import domain/vote
import gleam/string
import gleeunit/should
import helpers/factories as f

pub fn new_test() {
  let author = user.new(user.gen_id())
  let author_id = user.id(author)
  let content = f.non_empty_string("Good vibes")

  let card = card.new(author_id, content)

  assert nes.to_string(card.content(card)) == "Good vibes"
  assert card.author_id(card) == author_id
}

pub fn edit_test() {
  let card = f.card()
  card
  |> card.edit(card.author_id(card), f.non_empty_string("New improved content"))
  |> should.be_ok
  |> card.content()
  |> should.equal(f.non_empty_string("New improved content"))
}

pub fn edit_not_author_test() {
  let card = f.card()
  card
  |> card.edit(user.id(f.user()), f.non_empty_string("Bad vibes"))
  |> should.be_error
  |> should.equal(card.EditNotAuthor)
}

pub fn vote_test() {
  let card = f.card()
  let vote_1 = f.vote()
  let vote_2 = f.vote()
  let card =
    card
    |> card.reveal_content()
    |> card.start_voting()
    |> card.vote(vote_1)
    |> should.be_ok
    |> card.vote(vote_2)
    |> should.be_ok

  card
  |> card.vote_count()
  |> should.equal(2)

  let vote.Vote(user_id_1) = vote_1
  let vote.Vote(user_id_2) = vote_1

  card
  |> card.voted(user_id_1)
  |> should.be_true()

  card
  |> card.voted(user_id_2)
  |> should.be_true()
}

pub fn vote_already_voted_test() {
  let card = f.card()
  let vote = f.vote()

  card
  |> card.reveal_content()
  |> card.start_voting()
  |> card.vote(vote)
  |> should.be_ok
  |> card.vote(vote)
  |> should.be_error
  |> should.equal(card.VoteAlreadyVoted)
}

pub fn remove_vote_test() {
  let card = f.card()
  let vote = f.vote()
  let card =
    card
    |> card.reveal_content()
    |> card.start_voting()
    |> card.vote(vote)
    |> should.be_ok
    |> card.remove_vote(vote)
    |> should.be_ok

  card
  |> card.vote_count()
  |> should.equal(0)

  let vote.Vote(user_id) = vote
  card
  |> card.voted(user_id)
  |> should.be_false()
}

pub fn remove_vote_not_found_test() {
  let card = f.card()

  card
  |> card.reveal_content()
  |> card.start_voting()
  |> card.vote(f.vote())
  |> should.be_ok
  |> card.remove_vote(f.vote())
  |> should.be_error
  |> should.equal(card.RemoveVoteNotFound)
}

pub fn merge_card_test() {
  let child = f.card() |> card.reveal_content()
  let parent = f.card() |> card.reveal_content()

  let expected_content =
    f.non_empty_string(
      nes.to_string(card.content(parent))
      |> string.append(to: _, suffix: "\n----\n")
      |> string.append(to: _, suffix: nes.to_string(card.content(child))),
    )

  card.merge(from: child, into: parent)
  |> should.be_ok
  |> card.content()
  |> should.equal(expected_content)
}

pub fn cannot_merge_to_self() {
  let self = f.card() |> card.reveal_content()

  card.merge(from: self, into: self)
  |> should.be_error
  |> should.equal(card.MergeCannotMergeToSelf)
}

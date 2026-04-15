import domain/card
import domain/phase
import domain/user
import domain/values/non_empty_string as nes
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
  |> card.edit(
    card.author_id(card),
    f.non_empty_string("New improved content"),
    phase.Draft,
  )
  |> should.be_ok
  |> card.content()
  |> should.equal(f.non_empty_string("New improved content"))
}

pub fn edit_not_author_test() {
  let card = f.card()
  card
  |> card.edit(user.id(f.user()), f.non_empty_string("Bad vibes"), phase.Draft)
  |> should.be_error
  |> should.equal(card.EditNotAuthor)
}

pub fn vote_test() {
  let card = f.card()
  let phase = phase.Review
  card
  |> card.vote(f.vote(), phase)
  |> should.be_ok
  |> card.vote(f.vote(), phase)
  |> should.be_ok
  |> card.vote_count()
  |> should.equal(2)
}

pub fn vote_already_voted_test() {
  let card = f.card()
  let vote = f.vote()
  let phase = phase.Review

  card
  |> card.vote(vote, phase)
  |> should.be_ok
  |> card.vote(vote, phase)
  |> should.be_error
  |> should.equal(card.VoteAlreadyVoted)
}

pub fn cannot_vote_when_draft_test() {
  let card = f.card()
  let vote = f.vote()
  let phase = phase.Draft

  card
  |> card.vote(vote, phase)
  |> should.be_error
  |> should.equal(card.VoteNotReviewPhase)
}

pub fn remove_vote_test() {
  let card = f.card()
  let vote = f.vote()
  let phase = phase.Review
  card
  |> card.vote(vote, phase)
  |> should.be_ok
  |> card.remove_vote(vote, phase)
  |> should.be_ok
  |> card.vote_count()
  |> should.equal(0)
}

pub fn remove_vote_not_found_test() {
  let card = f.card()
  let phase = phase.Review

  card
  |> card.vote(f.vote(), phase)
  |> should.be_ok
  |> card.remove_vote(f.vote(), phase)
  |> should.be_error
  |> should.equal(card.RemoveVoteNotFound)
}

pub fn cannot_remove_vote_when_draft_test() {
  let card = f.card()
  let vote = f.vote()

  card
  |> card.vote(vote, phase.Review)
  |> should.be_ok
  |> card.remove_vote(vote, phase.Draft)
  |> should.be_error
  |> should.equal(card.RemoveVoteNotReviewPhase)
}

import domain/card
import domain/lane
import domain/user
import gleeunit/should
import helpers/factories as f

pub fn new_test() {
  let title = f.non_empty_string("Pros")
  let lane = lane.new(title)

  assert lane.title(lane) == title
  assert lane.cards(lane) == []
}

pub fn lane_add_card_test() {
  let card = f.card()
  let lane = f.lane()
  let lane = lane.add_card(lane, card)

  let cards = lane.cards(lane)
  let assert [inserted_card] = cards
  assert inserted_card == card
}

pub fn update_card_test() {
  let card = f.card()

  f.lane()
  |> lane.add_card(card)
  |> lane.update_card(card.id(card), fn(card) {
    card.edit(card, card.author_id(card), f.non_empty_string("Updated"))
  })
  |> should.be_ok
  |> lane.cards()
  |> fn(cards) {
    let assert [updated_card] = cards
    assert card.content(updated_card) == f.non_empty_string("Updated")
  }
}

pub fn update_card_propagate_error_test() {
  let card = f.card()
  let unauthorized_user = f.user()

  f.lane()
  |> lane.add_card(card)
  |> lane.update_card(card.id(card), fn(card) {
    card.edit(card, user.id(unauthorized_user), f.non_empty_string("Updated"))
  })
  |> should.be_error
  |> should.equal(lane.TransformError(card.NotAuthor))
}

pub fn update_card_not_found_test() {
  let card = f.card()
  let another_card = f.card()

  f.lane()
  |> lane.add_card(card)
  |> lane.update_card(card.id(another_card), fn(card) {
    card.edit(card, card.author_id(another_card), f.non_empty_string("Updated"))
  })
  |> should.be_error
  |> should.equal(lane.CardToUpdateNotFound)
}

pub fn remove_card_test() {
  let card_1 = f.card()
  let card_2 = f.card()

  f.lane()
  |> lane.add_card(card_1)
  |> lane.add_card(card_2)
  |> lane.remove_card(card.id(card_1), card.author_id(card_1))
  |> should.be_ok
  |> lane.cards()
  |> should.equal([card_2])
}

pub fn remove_card_not_found() {
  f.lane()
  |> lane.remove_card(card.id(f.card()), user.id(f.user()))
  |> should.be_error
  |> should.equal(lane.NotAuthorOfCardToRemove)
}

pub fn remove_card_unauthorized_test() {
  let card = f.card()

  let not_owner = f.user()

  f.lane()
  |> lane.add_card(card)
  |> lane.remove_card(card.id(card), user.id(not_owner))
  |> should.be_error
  |> should.equal(lane.NotAuthorOfCardToRemove)
}

pub fn lane_reveal_test() {
  let card = f.card()

  f.lane()
  |> lane.add_card(card)
  |> lane.reveal()
}

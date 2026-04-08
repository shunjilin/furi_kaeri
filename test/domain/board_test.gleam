import domain/board
import domain/card
import domain/lane
import gleam/list
import gleeunit/should
import helpers/factories as f

pub fn new_test() {
  let title = f.non_empty_string("Retro")

  let lane_1 = lane.new(f.non_empty_string("Yes"))
  let lane_2 = lane.new(f.non_empty_string("No"))

  let board = board.new(title, [lane_1, lane_2])
  assert board.title(board) == title
  assert board.lanes(board) == [lane_1, lane_2]
}

pub fn reveal_test() {
  let board = f.board()

  let assert [lane] = board.lanes(board)

  board
  |> board.update_lane(lane.id(lane), fn(lane) {
    Ok(lane.add_card(lane, f.card()))
  })
  |> should.be_ok
  |> board.reveal_board()
}

pub fn update_lane_test() {
  let board = f.board()
  let card = f.card()

  let assert [lane] = board.lanes(board)

  board
  |> board.update_lane(lane.id(lane), fn(lane) { Ok(lane.add_card(lane, card)) })
  |> should.be_ok
  |> board.lanes
  |> list.first
  |> should.be_ok
  |> lane.cards
  |> list.find(fn(added) { added == card })
  |> should.be_ok
}

pub fn update_lane_card_test() {
  let board = f.board()
  let card = f.card()

  let assert [lane] = board.lanes(board)

  board
  |> board.update_lane(lane.id(lane), fn(lane) { Ok(lane.add_card(lane, card)) })
  |> should.be_ok
  |> board.update_lane(lane.id(lane), fn(lane) {
    lane.update_card(lane, card.id(card), fn(card) {
      card.edit(card, card.author_id(card), f.non_empty_string("Updated"))
    })
  })
  |> should.be_ok
  |> board.lanes
  |> list.first
  |> should.be_ok
  |> lane.cards
  |> list.find(fn(added) {
    card.id(added) == card.id(card)
    && card.content(added) == f.non_empty_string("Updated")
  })
  |> should.be_ok
}

pub fn update_lane_propagate_error_test() {
  let board = f.board()
  let card = f.card()
  let vote = f.vote()

  let assert [lane] = board.lanes(board)

  board
  |> board.update_lane(lane.id(lane), fn(lane) { Ok(lane.add_card(lane, card)) })
  |> should.be_ok
  |> board.reveal_board()
  |> board.update_lane(lane.id(lane), fn(lane) {
    lane.update_card(lane, card.id(card), fn(card) { card.vote(card, vote) })
  })
  |> should.be_ok
  |> board.update_lane(lane.id(lane), fn(lane) {
    lane.update_card(lane, card.id(card), fn(card) { card.vote(card, vote) })
  })
  |> should.be_error
  |> should.equal(board.TransformError(lane.TransformError(card.AlreadyVoted)))
}

pub fn update_lane_not_found_test() {
  let board = f.board()
  let card = f.card()
  let vote = f.vote()

  let assert [lane] = board.lanes(board)

  board
  |> board.update_lane(lane.id(lane), fn(lane) { Ok(lane.add_card(lane, card)) })
  |> should.be_ok
  |> board.reveal_board()
  |> board.update_lane(lane.id(f.lane()), fn(lane) {
    lane.update_card(lane, card.id(card), fn(card) { card.vote(card, vote) })
  })
  |> should.be_error
  |> should.equal(board.LaneToUpdateNotFound)
}

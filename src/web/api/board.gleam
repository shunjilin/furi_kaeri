import domain/board
import domain/card
import domain/lane
import domain/user
import domain/values/non_empty_string
import domain/vote
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/otp/actor
import gleam/result

pub type Message {
  GetBoard(reply_to: Subject(board.Board))
  AddCard(
    user_id: user.UserId,
    lane_id: lane.LaneId,
    content: String,
    reply_to: Subject(Result(board.Board, String)),
  )
  EditCard(
    user_id: user.UserId,
    lane_id: lane.LaneId,
    card_id: card.CardId,
    content: String,
    reply_to: Subject(Result(board.Board, String)),
  )
  RemoveCard(
    user_id: user.UserId,
    lane_id: lane.LaneId,
    card_id: card.CardId,
    reply_to: Subject(Result(board.Board, String)),
  )
  Vote(
    user_id: user.UserId,
    lane_id: lane.LaneId,
    card_id: card.CardId,
    reply_to: Subject(Result(board.Board, String)),
  )
  RemoveVote(
    user_id: user.UserId,
    lane_id: lane.LaneId,
    card_id: card.CardId,
    reply_to: Subject(Result(board.Board, String)),
  )
  RevealBoard(reply_to: Subject(Result(board.Board, String)))
}

pub fn start_link() -> Result(actor.Started(Subject(Message)), actor.StartError) {
  init_board()
  |> actor.new
  |> actor.on_message(handle_message)
  |> actor.start
}

pub fn get_board(server: Subject(Message)) -> board.Board {
  process.call(server, 1000, GetBoard)
}

fn handle_message(
  board: board.Board,
  message: Message,
) -> actor.Next(board.Board, Message) {
  case message {
    GetBoard(reply_to) -> handle_get_board(board, reply_to)
    AddCard(user_id, lane_id, content, reply_to) -> {
      do_add_card(board, user_id, lane_id, content)
      |> respond(board, reply_to)
    }
    EditCard(user_id, lane_id, card_id, content, reply_to) -> {
      do_edit_card(board, user_id, lane_id, card_id, content)
      |> respond(board, reply_to)
    }
    RemoveCard(user_id, lane_id, card_id, reply_to) -> {
      do_remove_card(board, user_id, lane_id, card_id)
      |> respond(board, reply_to)
    }
    Vote(user_id, lane_id, card_id, reply_to) -> {
      do_vote(board, user_id, lane_id, card_id)
      |> respond(board, reply_to)
    }
    RemoveVote(user_id, lane_id, card_id, reply_to) -> {
      do_remove_vote(board, user_id, lane_id, card_id)
      |> respond(board, reply_to)
    }
    RevealBoard(reply_to) -> {
      do_reveal_board(board)
      |> respond(board, reply_to)
    }
  }
}

fn handle_get_board(board: board.Board, reply_to: Subject(board.Board)) {
  process.send(reply_to, board)
  actor.continue(board)
}

fn do_add_card(
  board: board.Board,
  user_id: user.UserId,
  lane_id: lane.LaneId,
  content: String,
) -> Result(board.Board, String) {
  use validated_content <- result.try(
    content
    |> non_empty_string.new()
    |> result.replace_error("Invalid content."),
  )

  let card = card.new(user_id, validated_content)

  board
  |> board.update_lane(lane_id, fn(lane) { Ok(lane.add_card(lane, card)) })
  |> map_lane_error(function.identity)
}

fn do_edit_card(
  board: board.Board,
  user_id: user.UserId,
  lane_id: lane.LaneId,
  card_id: card.CardId,
  content: String,
) -> Result(board.Board, String) {
  use validated_content <- result.try(
    content
    |> non_empty_string.new()
    |> result.replace_error("Invalid content."),
  )

  update_card_in_board(board, lane_id, card_id, fn(card) {
    card.edit(card, user_id, validated_content, board.phase(board))
  })
  |> map_card_error(fn(error) {
    case error {
      card.EditNotAuthor -> "Can only edit as author."
      card.EditNotDraft -> "Can only edit in draft phase."
    }
  })
}

fn do_remove_card(
  board: board.Board,
  user_id: user.UserId,
  lane_id: lane.LaneId,
  card_id: card.CardId,
) -> Result(board.Board, String) {
  board.update_lane(board, lane_id, fn(lane) {
    lane.remove_card(lane, card_id, user_id)
  })
  |> map_lane_error(fn(error) {
    case error {
      lane.CardToRemoveNotFound -> "Card does not exist."
      lane.NotAuthorOfCardToRemove -> "Can only remove as author."
    }
  })
}

fn do_vote(
  board: board.Board,
  user_id: user.UserId,
  lane_id: lane.LaneId,
  card_id: card.CardId,
) -> Result(board.Board, String) {
  let vote = vote.Vote(user_id)
  board
  |> update_card_in_board(lane_id, card_id, fn(card) {
    card.vote(card, vote, board.phase(board))
  })
  |> map_card_error(fn(error) {
    case error {
      card.VoteAlreadyVoted -> "Already voted for card."
      card.VoteNotReviewPhase -> "Can only vote in review phase."
    }
  })
}

fn do_remove_vote(
  board: board.Board,
  user_id: user.UserId,
  lane_id: lane.LaneId,
  card_id: card.CardId,
) -> Result(board.Board, String) {
  let vote = vote.Vote(user_id)
  board
  |> update_card_in_board(lane_id, card_id, fn(card) {
    card.remove_vote(card, vote, board.phase(board))
  })
  |> map_card_error(fn(error) {
    case error {
      card.RemoveVoteNotFound -> "No vote found."
      card.RemoveVoteNotReviewPhase -> "Can only remove vote in review phase."
    }
  })
}

fn do_reveal_board(board: board.Board) -> Result(board.Board, String) {
  board
  |> board.reveal_board()
  |> result.map_error(fn(error) {
    case error {
      board.RevealBoardAlreadyInReview -> "Board is already in review."
    }
  })
}

pub fn init_board() -> board.Board {
  board.new(new_string("Retro"), [
    lane.new(new_string("Start")),
    lane.new(new_string("Stop")),
    lane.new(new_string("Continue")),
  ])
}

fn new_string(str: String) {
  let assert Ok(val) = non_empty_string.new(str)
  val
}

fn respond(
  result: Result(board.Board, String),
  original_board: board.Board,
  reply_to: Subject(Result(board.Board, String)),
) -> actor.Next(board.Board, Message) {
  case result {
    Ok(updated_board) -> {
      process.send(reply_to, Ok(updated_board))
      actor.continue(updated_board)
    }
    Error(message) -> {
      process.send(reply_to, Error(message))
      actor.continue(original_board)
    }
  }
}

fn update_card_in_board(
  board: board.Board,
  lane_id: lane.LaneId,
  card_id: card.CardId,
  updater: fn(card.Card) -> Result(card.Card, e),
) -> Result(board.Board, board.UpdateLaneError(lane.UpdateCardError(e))) {
  board.update_lane(board, lane_id, fn(lane) {
    lane.update_card(lane, card_id, updater)
  })
}

fn map_lane_error(
  res: Result(a, board.UpdateLaneError(e)),
  mapper: fn(e) -> String,
) -> Result(a, String) {
  case res {
    Ok(val) -> Ok(val)
    Error(board.LaneToUpdateNotFound) -> Error("Lane not found.")
    Error(board.TransformError(e)) -> Error(mapper(e))
  }
}

fn map_card_error(
  res: Result(board.Board, board.UpdateLaneError(lane.UpdateCardError(e))),
  mapper: fn(e) -> String,
) -> Result(board.Board, String) {
  use lane_error <- map_lane_error(res)
  case lane_error {
    lane.CardToUpdateNotFound -> "Card not found."
    lane.TransformError(e) -> mapper(e)
  }
}

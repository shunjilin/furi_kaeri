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
    card_id: card.CardId,
    content: String,
    reply_to: Subject(Result(board.Board, String)),
  )
  RemoveCard(
    user_id: user.UserId,
    card_id: card.CardId,
    reply_to: Subject(Result(board.Board, String)),
  )
  MergeCard(
    from_card_id: card.CardId,
    to_card_id: card.CardId,
    reply_to: Subject(Result(board.Board, String)),
  )
  Vote(
    user_id: user.UserId,
    card_id: card.CardId,
    reply_to: Subject(Result(board.Board, String)),
  )
  RemoveVote(
    user_id: user.UserId,
    card_id: card.CardId,
    reply_to: Subject(Result(board.Board, String)),
  )
  RevealBoard(reply_to: Subject(Result(board.Board, String)))
  StartVoting(reply_to: Subject(Result(board.Board, String)))
}

pub fn start_link() -> Result(actor.Started(Subject(Message)), actor.StartError) {
  init_board()
  |> actor.new
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  board: board.Board,
  message: Message,
) -> actor.Next(board.Board, Message) {
  case message {
    GetBoard(reply_to) -> handle_get_board(board, reply_to)
    AddCard(user_id, lane_id, content, reply_to) -> {
      board
      |> do_add_card(user_id, lane_id, content)
      |> respond(board, reply_to)
    }
    EditCard(user_id, card_id, content, reply_to) -> {
      board
      |> do_edit_card(user_id, card_id, content)
      |> respond(board, reply_to)
    }
    RemoveCard(user_id, card_id, reply_to) -> {
      board
      |> do_remove_card(user_id, card_id)
      |> respond(board, reply_to)
    }
    MergeCard(from_card_id, to_card_id, reply_to) -> {
      board
      |> do_merge_card(from_card_id, to_card_id)
      |> respond(board, reply_to)
    }
    Vote(user_id, card_id, reply_to) -> {
      board
      |> do_vote(user_id, card_id)
      |> respond(board, reply_to)
    }
    RemoveVote(user_id, card_id, reply_to) -> {
      board
      |> do_remove_vote(user_id, card_id)
      |> respond(board, reply_to)
    }
    RevealBoard(reply_to) -> {
      board
      |> do_reveal_board()
      |> respond(board, reply_to)
    }
    StartVoting(reply_to) -> {
      board
      |> do_start_voting()
      |> respond(board, reply_to)
    }
  }
}

fn handle_get_board(board: board.Board, reply_to: Subject(board.Board)) {
  process.send(reply_to, board)
  actor.continue(board)
}

fn do_merge_card(
  board: board.Board,
  from_card_id: card.CardId,
  to_card_id: card.CardId,
) -> Result(board.Board, String) {
  board.merge_cards(board:, from_card_id:, to_card_id:)
  |> result.map_error(fn(error) {
    case error {
      board.MergeCardsFromCardNotFound -> "Card to merge from not found."
      board.MergeCardsToCardNotFound -> "Card to merge to not found."
      board.MergeCardsNotInPreviewPhase -> "Can only merge in preview phase."
      board.MergeCardsCardError(card.MergeAlreadyMerged) ->
        "Cannot merge already merged card"
      board.MergeCardsCardError(card.MergeCannotMergeToSelf) ->
        "Cannot merge card to itself."
    }
  })
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
  |> board.add_card_to_lane(lane_id:, card:)
  |> map_lane_error(function.identity)
}

fn do_edit_card(
  board: board.Board,
  author_id: user.UserId,
  card_id: card.CardId,
  content: String,
) -> Result(board.Board, String) {
  use content <- result.try(
    content
    |> non_empty_string.new()
    |> result.replace_error("Invalid content."),
  )

  board.edit_card_content(board:, author_id:, card_id:, content:)
  |> result.map_error(fn(error) {
    case error {
      board.EditCardError(card.EditNotAuthor) -> "Can only edit as author."
      board.EditCardNotFound -> "Card to edit not found."
      board.EditCardNotDraftPhase -> "Can only edit in draft phase."
    }
  })
}

fn do_remove_card(
  board: board.Board,
  author_id: user.UserId,
  card_id: card.CardId,
) -> Result(board.Board, String) {
  board.remove_card(board:, author_id:, card_id:)
  |> result.map_error(fn(error) {
    case error {
      board.RemoveCardNotDraftPhase -> "Can only remove card in draft phase."
      board.RemoveCardNotAuthor -> "Can only remove as author."
      board.RemoveCardNotFound -> "Card to remove not found."
    }
  })
}

fn do_vote(
  board: board.Board,
  user_id: user.UserId,
  card_id: card.CardId,
) -> Result(board.Board, String) {
  let vote = vote.Vote(user_id)
  board.vote_for_card(board:, vote:, card_id:)
  |> result.map_error(fn(error) {
    case error {
      board.VoteCardNotFound -> "Card to vote for not found."
      board.VoteNotVotingPhase -> "Can only vote in review phase."
      board.VoteCardError(card.VoteAlreadyVoted) -> "Already voted for card."
    }
  })
}

fn do_remove_vote(
  board: board.Board,
  user_id: user.UserId,
  card_id: card.CardId,
) -> Result(board.Board, String) {
  let vote = vote.Vote(user_id)
  board.remove_vote_for_card(board:, vote:, card_id:)
  |> result.map_error(fn(error) {
    case error {
      board.RemoveVoteCardNotFound -> "Card to remove vote for not found."
      board.RemoveVoteNotVotingPhase -> "Can only remove vote in review phase."
      board.RemoveVoteCardError(card.RemoveVoteNotFound) ->
        "No vote found for card."
    }
  })
}

fn do_reveal_board(board: board.Board) -> Result(board.Board, String) {
  board
  |> board.reveal_board()
  |> result.map_error(fn(error) {
    case error {
      board.RevealBoardAlreadyRevealed -> "Board is already revealed."
      board.RevealBoardNoCardsToReveal -> "No cards to reveal."
    }
  })
}

fn do_start_voting(board: board.Board) -> Result(board.Board, String) {
  board
  |> board.start_voting()
  |> result.map_error(fn(error) {
    case error {
      board.StartVotingAlreadyVoting -> "Already in voting phase."
      board.StartVotingCardsNotReveled -> "Cards not yet revealed."
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

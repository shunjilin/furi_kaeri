import domain/board
import domain/card
import domain/lane
import domain/user
import domain/values/non_empty_string
import domain/vote
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/option
import gleam/otp/actor
import gleam/result
import web/shared_message

pub type State {
  State(
    board: board.Board,
    subscribers: dict.Dict(String, Subject(shared_message.SharedMsg)),
    stale_timer: option.Option(process.Timer),
    subject: Subject(Message),
  )
}

pub type Message {
  GetBoard(reply_to: Subject(board.Board))
  AddCard(user_id: user.UserId, lane_id: lane.LaneId, content: String)
  EditCard(user_id: user.UserId, card_id: card.CardId, content: String)
  RemoveCard(user_id: user.UserId, card_id: card.CardId)
  MergeCard(from_card_id: card.CardId, to_card_id: card.CardId)
  Vote(user_id: user.UserId, card_id: card.CardId)
  RemoveVote(user_id: user.UserId, card_id: card.CardId)
  RevealBoard
  StartVoting
  Subscribe(id: String, client: Subject(shared_message.SharedMsg))
  Unsubscribe(id: String)
  DeleteBoard
}

pub fn start_link(
  id: String,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(subject) {
    State(
      board: init_board(id),
      subscribers: dict.new(),
      stale_timer: option.None,
      subject: subject,
    )
    |> actor.initialised
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  state: State,
  message: Message,
) -> actor.Next(State, Message) {
  case message {
    GetBoard(reply_to) -> handle_get_board(state, reply_to)
    AddCard(user_id, lane_id, content) -> {
      state.board
      |> do_add_card(user_id, lane_id, content)
      |> respond(state)
    }
    EditCard(user_id, card_id, content) -> {
      state.board
      |> do_edit_card(user_id, card_id, content)
      |> respond(state)
    }
    RemoveCard(user_id, card_id) -> {
      state.board
      |> do_remove_card(user_id, card_id)
      |> respond(state)
    }
    MergeCard(from_card_id, to_card_id) -> {
      state.board
      |> do_merge_card(from_card_id, to_card_id)
      |> respond(state)
    }
    Vote(user_id, card_id) -> {
      state.board
      |> do_vote(user_id, card_id)
      |> respond(state)
    }
    RemoveVote(user_id, card_id) -> {
      state.board
      |> do_remove_vote(user_id, card_id)
      |> respond(state)
    }
    RevealBoard -> {
      state.board
      |> do_reveal_board()
      |> respond(state)
    }
    StartVoting -> {
      state.board
      |> do_start_voting()
      |> respond(state)
    }
    Subscribe(id, client) -> {
      let subscribers = dict.insert(state.subscribers, id, client)
      let next_state =
        State(..state, subscribers:)
        |> stop_stale_timer()
      actor.continue(next_state)
    }

    Unsubscribe(id) -> {
      let subscribers = dict.delete(state.subscribers, id)
      let next_state =
        State(..state, subscribers:)
        |> start_stale_timer_if_no_subscribers()

      actor.continue(next_state)
    }

    DeleteBoard -> {
      actor.stop()
    }
  }
}

fn stop_stale_timer(state: State) {
  case state.stale_timer {
    option.Some(timer) -> {
      process.cancel_timer(timer)
      State(..state, stale_timer: option.None)
    }
    option.None -> state
  }
}

/// removes a board if there are no subscribers, after 1hr
fn start_stale_timer_if_no_subscribers(state: State) {
  case dict.is_empty(state.subscribers) {
    True -> {
      State(
        ..state,
        stale_timer: option.Some(process.send_after(
          state.subject,
          60 * 60 * 1000,
          DeleteBoard,
        )),
      )
    }
    False -> state
  }
}

fn handle_get_board(state: State, reply_to: Subject(board.Board)) {
  process.send(reply_to, state.board)

  actor.continue(state)
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

pub fn init_board(id) -> board.Board {
  board.new(id, new_string("Retro"), [
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
  state: State,
) -> actor.Next(State, Message) {
  case result {
    Ok(updated_board) -> {
      dict.each(state.subscribers, fn(_, sub) {
        process.send(sub, shared_message.ApiReturnedBoard(updated_board))
      })
      actor.continue(State(..state, board: updated_board))
    }
    Error(message) -> {
      dict.each(state.subscribers, fn(_, sub) {
        process.send(sub, shared_message.ApiReturnedError(message))
      })
      actor.continue(state)
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

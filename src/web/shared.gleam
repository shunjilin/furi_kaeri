import domain/board
import domain/card
import domain/lane
import domain/user
import gleam/erlang/process.{type Subject}

// Board API Messages
pub type SharedMsg {
  ApiReturnedBoard(board: board.Board)
  ApiReturnedError(String)
}

pub type BoardApiMessage {
  GetBoard(reply_to: Subject(board.Board))
  AddCard(user_id: user.UserId, lane_id: lane.LaneId, content: String)
  EditCard(user_id: user.UserId, card_id: card.CardId, content: String)
  RemoveCard(user_id: user.UserId, card_id: card.CardId)
  MergeCard(from_card_id: card.CardId, to_card_id: card.CardId)
  Vote(user_id: user.UserId, card_id: card.CardId)
  RemoveVote(user_id: user.UserId, card_id: card.CardId)
  RevealBoard
  StartVoting
  Subscribe(id: String, client: Subject(SharedMsg))
  Unsubscribe(id: String)
}

// Router Messages
pub type RouterCreateError {
  BoardAlreadyExist
}

pub type RouterGetError {
  BoardDoesNotExist
}

pub type RouterMessage {
  RouterCreateBoard(
    id: String,
    reply_to: Subject(Result(Subject(BoardApiMessage), RouterCreateError)),
  )
  RouterGetBoard(
    id: String,
    reply_to: Subject(Result(Subject(BoardApiMessage), RouterGetError)),
  )
  RouterRegisterBoard(id: String, subject: Subject(BoardApiMessage))
}

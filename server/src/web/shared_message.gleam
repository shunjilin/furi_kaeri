import domain/board
import domain/timer
import gleam/option

pub type BoardSnapshot {
  BoardSnapshot(board: board.Board, countdown_timer: option.Option(timer.Timer))
}

pub type SharedMsg {
  ApiReturnedBoardSnapshot(BoardSnapshot)
  ApiReturnedError(String)
}

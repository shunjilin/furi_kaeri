import domain/board

pub type SharedMsg {
  ApiReturnedBoard(board: board.Board)
  ApiReturnedError(String)
}

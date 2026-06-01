import domain/board_v2

pub type SharedMsg {
  ApiReturnedBoard(board: board_v2.Board)
  ApiReturnedError(String)
}

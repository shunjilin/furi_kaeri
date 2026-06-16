import domain/board

pub type StorageError {
  StorageError(message: String)
}

pub type BoardRepository {
  BoardRepository(
    save: fn(board.Board, Int) -> Result(Nil, StorageError),
    fetch: fn(String) -> Result(board.Board, StorageError),
    delete: fn(String) -> Result(board.Board, StorageError),
  )
}

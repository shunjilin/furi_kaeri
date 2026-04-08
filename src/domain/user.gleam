import youid/uuid

pub type UserId {
  UserId(uuid.Uuid)
}

pub opaque type User {
  User(id: UserId)
}

pub fn new() -> User {
  User(UserId(uuid.v7()))
}

pub fn id(user: User) -> UserId {
  user.id
}

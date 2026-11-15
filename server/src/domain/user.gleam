import youid/uuid

pub type UserId {
  UserId(uuid.Uuid)
}

pub opaque type User {
  User(id: UserId)
}

pub fn new(id: UserId) -> User {
  User(id)
}

pub fn id(user: User) -> UserId {
  user.id
}

pub fn gen_id() -> UserId {
  UserId(uuid.v7())
}

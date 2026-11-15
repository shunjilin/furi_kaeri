import domain/user
import gleam/bytes_tree
import gleam/http/cookie
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import gleam/option
import gleam/result
import mist.{type Connection, type ResponseData}
import youid/uuid

const user_id_key: String = "user_id"

pub type Handler(req_body, res_body) =
  fn(Request(req_body)) -> Response(res_body)

pub fn security_headers_middleware(
  handler: Handler(req_body, res_body),
) -> Handler(req_body, res_body) {
  fn(req: Request(req_body)) {
    let res = handler(req)

    res
    |> response.set_header("content-security-policy", "default-src 'self'")
    |> response.set_header("x-xss-protection", "1; mode=block")
    |> response.set_header("x-frame-options", "DENY")
    |> response.set_header("x-content-type-options", "nosniff")
    |> response.set_header("referrer-policy", "no-referrer")
  }
}

pub type GetUserResult {
  NewUser(user.User)
  ExistingUser(user.User)
}

fn get_user(req: Request(Connection)) -> GetUserResult {
  let result =
    req
    |> request.get_cookies
    |> list.find_map(fn(cookie) {
      case cookie {
        #(key, user_id_string) if key == user_id_key -> {
          user_id_string
          |> uuid.from_string()
          |> result.map(fn(uuid) { user.new(user.UserId(uuid)) })
        }
        _ -> Error(Nil)
      }
    })

  case result {
    Ok(user) -> ExistingUser(user)
    Error(Nil) -> NewUser(user.new(user.gen_id()))
  }
}

fn cookie_attributes(cookie_secure: Bool) {
  cookie.Attributes(
    option.Some(60 * 60 * 12),
    // 12 hours
    option.None,
    option.None,
    cookie_secure,
    True,
    // HttpOnly
    option.Some(cookie.Strict),
  )
}

fn is_valid_origin(req: Request(Connection), allowed_origin: String) -> Bool {
  let path = request.path_segments(req)
  let is_ws_route = list.last(path) == Ok("ws")

  case request.get_header(req, "origin"), is_ws_route {
    Ok(origin), True -> {
      origin == allowed_origin
    }
    _, _ -> !is_ws_route
  }
}

pub fn auth_middleware(
  handler: fn(Request(Connection), GetUserResult) -> Response(ResponseData),
  cookie_secure: Bool,
  allowed_origin: String,
) -> fn(Request(Connection)) -> Response(ResponseData) {
  fn(req: Request(Connection)) {
    case is_valid_origin(req, allowed_origin) {
      False ->
        response.new(403)
        |> response.set_body(
          mist.Bytes(bytes_tree.from_string("Forbidden Origin")),
        )
      True -> {
        let user_result = get_user(req)

        let result = handler(req, user_result)

        case user_result {
          NewUser(user) -> {
            let user.UserId(uuid) = user.id(user)
            response.set_cookie(
              result,
              user_id_key,
              uuid.to_string(uuid),
              cookie_attributes(cookie_secure),
            )
          }
          ExistingUser(_) -> result
        }
      }
    }
  }
}

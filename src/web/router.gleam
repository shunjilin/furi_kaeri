import domain/board
import domain/lane
import domain/user
import domain/values/non_empty_list
import domain/values/non_empty_string
import gleam/bit_array
import gleam/bytes_tree
import gleam/erlang/application
import gleam/erlang/process.{type Subject}
import gleam/http
import gleam/http/cookie
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/uri
import lustre
import lustre/attribute
import lustre/element
import lustre/element/html.{html}
import lustre/server_component
import mist.{type Connection, type ResponseData}
import web/api/board as board_api
import web/board_registry
import web/views/board as board_view
import web/views/home
import youid/uuid

const user_id_key: String = "user_id"

pub type Context {
  Context(
    board_registry: process.Name(board_registry.Message),
    cookie_secure: Bool,
    asset_version: String,
    cache_assets: Bool,
  )
}

type GetUserResult {
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

pub fn handle_request(
  req: Request(Connection),
  ctx: Context,
) -> Response(ResponseData) {
  let user_result = get_user(req)

  let user = case user_result {
    NewUser(user) -> {
      user
    }
    ExistingUser(user) -> user
  }

  let board_registry = process.named_subject(ctx.board_registry)
  case request.path_segments(req), req.method {
    [], http.Get -> serve_home_layout(ctx) |> serve_page(user_result, ctx)
    ["board", board_id], http.Get -> {
      case board_registry.get_board(board_registry, board.BoardId(board_id)) {
        Ok(_) ->
          serve_board_layout(board_id, ctx) |> serve_page(user_result, ctx)
        Error(board_registry.BoardDoesNotExist) ->
          response.new(404)
          |> response.set_body(
            mist.Bytes(bytes_tree.from_string("Board not found.")),
          )
      }
    }
    ["board", "create"], http.Post -> handle_create_board(board_registry, req)
    ["static", "css", "main.css"], http.Get ->
      serve_static("priv/static/css/main.css", "text/css", ctx)
    ["static", "js", "client.mjs"], http.Get ->
      serve_static("priv/static/js/client.mjs", "text/javascript", ctx)
    ["lustre", "runtime.mjs"], http.Get -> serve_runtime()
    ["home", "ws"], http.Get -> {
      let number_of_active_boards =
        board_registry.get_number_of_active_boards(board_registry)
      serve_home_page(req, number_of_active_boards)
    }
    ["board", board_id, "ws"], http.Get ->
      serve_board_page(req, board_registry, user, board.BoardId(board_id))
    _, _ -> not_found()
  }
}

fn cookie_attributes(ctx: Context) {
  cookie.Attributes(
    // 12 hours
    option.Some(60 * 60 * 12),
    option.Some(""),
    option.None,
    ctx.cookie_secure,
    True,
    option.Some(cookie.Strict),
  )
}

pub fn parse_board_form(
  body_bit_array: BitArray,
  board_id: board.BoardId,
) -> Result(board.Board, Nil) {
  use body_string <- result.try(
    bit_array.to_string(body_bit_array) |> result.replace_error(Nil),
  )

  use key_values <- result.try(
    uri.parse_query(body_string) |> result.replace_error(Nil),
  )

  use lanes <- result.try(
    list.filter_map(key_values, fn(pair) {
      let #(key, value) = pair
      case key {
        "lanes[]" -> {
          non_empty_string.new(value)
          |> result.map(lane.new)
          |> result.map_error(fn(error) {
            case error {
              non_empty_string.EmptyString -> Nil
            }
          })
        }
        _ -> Error(Nil)
      }
    })
    |> non_empty_list.from_list
    |> result.map_error(fn(error) {
      case error {
        non_empty_list.EmptyList -> Nil
      }
    }),
  )

  use title <- result.try(
    non_empty_string.new("Retro")
    |> result.map_error(fn(error) {
      case error {
        non_empty_string.EmptyString -> Nil
      }
    }),
  )

  Ok(board.new(board_id, title, lanes))
}

fn handle_create_board(
  board_registry: Subject(board_registry.Message),
  req: Request(Connection),
) -> Response(ResponseData) {
  case mist.read_body(req, 102_400) {
    Ok(req_with_body) -> {
      case parse_board_form(req_with_body.body, board.generate_id()) {
        Error(Nil) ->
          response.new(422)
          |> response.set_body(
            mist.Bytes(bytes_tree.from_string(
              "Failed to create board due to invalid input.",
            )),
          )
        Ok(board) -> {
          case board_registry.create_board(board_registry, board) {
            Ok(_) -> {
              let board.BoardId(id) = board.id(board)
              response.new(303)
              |> response.set_header("location", "/board/" <> id)
              |> response.set_body(mist.Bytes(bytes_tree.new()))
            }
            Error(board_registry.BoardAlreadyExist) -> {
              response.new(409)
              |> response.set_body(
                mist.Bytes(bytes_tree.from_string(
                  "Failed to create board as it already exists.",
                )),
              )
            }
          }
        }
      }
    }
    Error(error) -> {
      case error {
        mist.ExcessBody -> {
          response.new(413)
          |> response.set_body(
            mist.Bytes(bytes_tree.from_string("Request body too large.")),
          )
        }
        mist.MalformedBody -> {
          response.new(400)
          |> response.set_body(
            mist.Bytes(bytes_tree.from_string("Malformed request body.")),
          )
        }
      }
    }
  }
}

fn serve_static(
  path: String,
  mime_type: String,
  ctx: Context,
) -> Response(ResponseData) {
  mist.send_file(path, offset: 0, limit: None)
  |> result.map(fn(file) {
    let res =
      response.new(200)
      |> response.prepend_header("content-type", mime_type)

    case ctx.cache_assets {
      True ->
        res |> response.prepend_header("cache-control", "public, max-age=3600")
      False ->
        res
        |> response.prepend_header(
          "cache-control",
          "no-store, no-cache, must-revalidate, max-age=0",
        )
        |> response.prepend_header("pragma", "no-cache")
        |> response.prepend_header("expires", "0")
    }
    |> response.set_body(file)
  })
  |> result.lazy_unwrap(fn() { not_found() })
}

fn serve_page(
  html_body: bytes_tree.BytesTree,
  user_result: GetUserResult,
  ctx: Context,
) -> Response(ResponseData) {
  response.new(200)
  |> response.set_body(mist.Bytes(html_body))
  |> response.set_header("content-type", "text/html")
  |> assign_user(user_result, ctx)
}

fn serve_board_layout(board_id: String, ctx: Context) -> bytes_tree.BytesTree {
  let ws_route = "/board/" <> board_id <> "/ws"

  let extra_head = [
    html.script(
      [attribute.type_("module"), attribute.src("/lustre/runtime.mjs")],
      "",
    ),
    html.script(
      [
        attribute.type_("module"),
        attribute.src("/static/js/client.mjs?v=" <> ctx.asset_version),
      ],
      "",
    ),
  ]

  let body_content = [
    server_component.element([server_component.route(ws_route)], []),
  ]

  layout("Board", extra_head, body_content, ctx)
}

fn serve_home_layout(ctx: Context) -> bytes_tree.BytesTree {
  let ws_route = "/home/ws"

  let extra_head = [
    html.script(
      [attribute.type_("module"), attribute.src("/lustre/runtime.mjs")],
      "",
    ),
    html.script(
      [
        attribute.type_("module"),
        attribute.src("/static/js/client.mjs?v=" <> ctx.asset_version),
      ],
      "",
    ),
  ]

  let body_content = [
    server_component.element([server_component.route(ws_route)], []),
  ]

  layout("Home", extra_head, body_content, ctx)
}

fn layout(
  title_suffix: String,
  page_specific_head: List(element.Element(msg)),
  body_content: List(element.Element(msg)),
  ctx: Context,
) -> bytes_tree.BytesTree {
  html([attribute.lang("en")], [
    html.head([], [
      html.link([
        attribute.rel("stylesheet"),
        attribute.href("/static/css/main.css?v=" <> ctx.asset_version),
      ]),
      html.meta([attribute.charset("utf-8")]),
      html.meta([
        attribute.name("viewport"),
        attribute.content("width=device-width"),
      ]),
      html.title([], "Furi Kaeri - " <> title_suffix),
      ..page_specific_head
    ]),
    html.body([attribute.style("height", "100dvh")], body_content),
  ])
  |> element.to_document_string_tree
  |> bytes_tree.from_string_tree
}

fn assign_user(
  response: Response(ResponseData),
  user_result: GetUserResult,
  ctx: Context,
) -> Response(ResponseData) {
  case user_result {
    NewUser(user) -> {
      let user.UserId(uuid) = user.id(user)
      response.set_cookie(
        response,
        user_id_key,
        uuid.to_string(uuid),
        cookie_attributes(ctx),
      )
    }
    ExistingUser(_) -> {
      response
    }
  }
}

fn serve_runtime() -> Response(ResponseData) {
  let assert Ok(priv) = application.priv_directory("lustre")
  let path = priv <> "/static/lustre-server-component.min.mjs"

  case mist.send_file(path, offset: 0, limit: None) {
    Ok(file) ->
      response.new(200)
      |> response.prepend_header("content-type", "application/javascript")
      |> response.set_body(file)
    Error(_) -> not_found()
  }
}

fn serve_board_page(
  req: Request(Connection),
  board_registry: Subject(board_registry.Message),
  user: user.User,
  board_id: board.BoardId,
) -> Response(ResponseData) {
  case board_registry.get_board(board_registry, board_id) {
    Ok(board_manager) -> {
      mist.websocket(
        request: req,
        on_init: fn(_) {
          let connection_id = uuid.v7() |> uuid.to_string()
          let init_subject = process.new_subject()
          process.send(
            board_manager,
            board_api.GetBoardSnapshot(reply_to: init_subject),
          )

          let assert Ok(snapshot) = process.receive(init_subject, 1000)
          let component =
            board_view.component(
              board_manager,
              user,
              snapshot.board,
              connection_id,
            )
          let assert Ok(runtime) = lustre.start_server_component(component, Nil)

          let self = process.new_subject()
          let selector = process.new_selector() |> process.select(self)

          server_component.register_subject(self) |> lustre.send(to: runtime)

          #(SocketState(runtime, connection_id), Some(selector))
        },
        handler: loop_socket,
        on_close: fn(state) {
          process.send(
            board_manager,
            board_api.Unsubscribe(state.connection_id),
          )
          lustre.shutdown() |> lustre.send(to: state.runtime)
        },
      )
    }
    Error(_) -> {
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.new()))
    }
  }
}

fn serve_home_page(
  req: Request(Connection),
  number_of_active_boards: Int,
) -> Response(ResponseData) {
  mist.websocket(
    request: req,
    on_init: fn(_) {
      let connection_id = uuid.v7() |> uuid.to_string()
      let component = home.component()

      let assert Ok(runtime) =
        lustre.start_server_component(component, number_of_active_boards)

      let self = process.new_subject()
      let selector = process.new_selector() |> process.select(self)

      server_component.register_subject(self) |> lustre.send(to: runtime)

      #(SocketState(runtime, connection_id), Some(selector))
    },
    handler: loop_socket,
    on_close: fn(state) { lustre.shutdown() |> lustre.send(to: state.runtime) },
  )
}

type SocketState(msg) {
  SocketState(runtime: lustre.Runtime(msg), connection_id: String)
}

fn loop_socket(state: SocketState(msg), msg, conn) {
  case msg {
    mist.Text(json) -> {
      let decoder = server_component.runtime_message_decoder()
      case json.parse(json, decoder) {
        Ok(action) -> lustre.send(state.runtime, action)
        Error(_) -> Nil
      }
      mist.continue(state)
    }
    mist.Custom(client_msg) -> {
      let json = server_component.client_message_to_json(client_msg)
      let _ = mist.send_text_frame(conn, json.to_string(json))
      mist.continue(state)
    }
    mist.Closed | mist.Shutdown -> mist.stop()
    _ -> mist.continue(state)
  }
}

fn not_found() {
  response.new(404) |> response.set_body(mist.Bytes(bytes_tree.new()))
}
